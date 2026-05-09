import ComposableArchitecture
import CoreGraphics
import Foundation
import WarpCore
import Inject
import SwiftUI
import WhisperKit

private let transcriptionFeatureLogger = WarpLog.transcription
private let mercuryTransformLogger = WarpLog.mercuryTransform

/// When `true`, the CGEvent tap discards the event so it never reaches macOS (or other apps).
fileprivate func shouldConsumeKeyboardEventForHotkey(
  hotkey: HotKey,
  useDoubleTapOnly: Bool,
  keyEvent: KeyEvent
) -> Bool {
  if useDoubleTapOnly { return true }
  if keyEvent.key != nil { return true }
  // Modifier-only fn: leaving events enabled makes macOS show the emoji & symbols picker on repeat taps.
  if hotkey.key == nil, hotkey.modifiers.contains(kind: .fn) {
    return true
  }
  return false
}

@Reducer
struct TranscriptionFeature {
  @ObservableState
  struct State {
    var isRecording: Bool = false
    var isTranscribing: Bool = false
    /// True while waiting on Inception Mercury 2 after local ASR (same overlay as transcribing).
    var isMercuryTransforming: Bool = false
    var isPrewarming: Bool = false
    var error: String?
    var recordingStartTime: Date?
    var meter: Meter = .init(averagePower: 0, peakPower: 0)
    var sourceAppBundleID: String?
    var sourceAppName: String?
    /// Focused window title when frontmost app is a browser (web-mail routing). Not persisted.
    var sourceBrowserWindowTitle: String?
    @Shared(.warpSettings) var warpSettings: WarpSettings
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
  }

  enum Action {
    case task
    case audioLevelUpdated(Meter)

    // Hotkey actions
    case hotKeyPressed
    case hotKeyReleased

    // Recording flow
    case startRecording
    case stopRecording

    // Cancel/discard flow
    case cancel   // Explicit cancellation with sound
    case discard  // Silent discard (too short/accidental)

    // Transcription result flow
    case transcriptionResult(String, URL)
    case transcriptionError(Error, URL?)

    // Model availability
    case modelMissing

    // Mercury 2 post-processing
    case mercuryTransformDidFinish
    case reportMercuryIssue(String)
  }

  enum CancelID {
    case metering
    case transcription
  }

  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.soundEffects) var soundEffect
  @Dependency(\.sleepManagement) var sleepManagement
  @Dependency(\.date.now) var now
  @Dependency(\.transcriptPersistence) var transcriptPersistence
  @Dependency(\.inceptionAPIKey) var inceptionAPIKey
  @Dependency(\.mercuryTransform) var mercuryTransform
  @Dependency(\.hostContext) var hostContext

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: - Lifecycle / Setup

      case .task:
        // Starts two concurrent effects:
        // 1) Observing audio meter
        // 2) Monitoring hot key events
        // 3) Priming the recorder for instant startup
        return .merge(
          startMeteringEffect(),
          startHotKeyMonitoringEffect(),
          warmUpRecorderEffect()
        )

      // MARK: - Metering

      case let .audioLevelUpdated(meter):
        state.meter = meter
        return .none

      // MARK: - HotKey Flow

      case .hotKeyPressed:
        // If we're transcribing or post-processing with Mercury, send a cancel first. Otherwise start recording immediately.
        // We'll decide later (on release) whether to keep or discard the recording.
        return handleHotKeyPressed(
          isTranscribing: state.isTranscribing || state.isMercuryTransforming
        )

      case .hotKeyReleased:
        // If we're currently recording, then stop. Otherwise, just cancel
        // the delayed "startRecording" effect if we never actually started.
        return handleHotKeyReleased(isRecording: state.isRecording)

      // MARK: - Recording Flow

      case .startRecording:
        return handleStartRecording(&state)

      case .stopRecording:
        return handleStopRecording(&state)

      // MARK: - Transcription Results

      case let .transcriptionResult(result, audioURL):
        return handleTranscriptionResult(&state, result: result, audioURL: audioURL)

      case let .transcriptionError(error, audioURL):
        return handleTranscriptionError(&state, error: error, audioURL: audioURL)

      case .modelMissing:
        return .none

      // MARK: - Cancel/Discard Flow

      case .cancel:
        // Only cancel if we're in the middle of recording, transcribing, or Mercury post-processing
        guard state.isRecording || state.isTranscribing || state.isMercuryTransforming else {
          return .none
        }
        return handleCancel(&state)

      case .mercuryTransformDidFinish:
        state.isMercuryTransforming = false
        return .none

      case let .reportMercuryIssue(message):
        state.error = message
        return .none

      case .discard:
        // Silent discard for quick/accidental recordings
        guard state.isRecording else {
          return .none
        }
        return handleDiscard(&state)
      }
    }
  }
}

// MARK: - Effects: Metering & HotKey

private extension TranscriptionFeature {
  /// Effect to begin observing the audio meter.
  func startMeteringEffect() -> Effect<Action> {
    .run { send in
      for await meter in await recording.observeAudioLevel() {
        await send(.audioLevelUpdated(meter))
      }
    }
    .cancellable(id: CancelID.metering, cancelInFlight: true)
  }

  /// Effect to start monitoring hotkey events through the `keyEventMonitor`.
  func startHotKeyMonitoringEffect() -> Effect<Action> {
    .run { send in
      var hotKeyProcessor: HotKeyProcessor = .init(hotkey: HotKey(key: nil, modifiers: [.option]))
      @Shared(.isSettingHotKey) var isSettingHotKey: Bool
      @Shared(.warpSettings) var warpSettings: WarpSettings

      // Serialize hotkey-driven actions. Unstructured `Task { await send }` per event allowed
      // `hotKeyReleased` / `hotKeyPressed` to reorder on fast double-taps (e.g. fn double-tap lock).
      let (actionStream, actionContinuation) = AsyncStream<Action>.makeStream()
      let consumer = Task.detached(priority: .userInitiated) {
        for await action in actionStream {
          await send(action)
        }
      }

      // Handle incoming input events (keyboard and mouse)
      let token = keyEventMonitor.handleInputEvent { inputEvent in
        // Skip if the user is currently setting a hotkey
        if isSettingHotKey {
          return false
        }

        // Always keep hotKeyProcessor in sync with current user hotkey preference
        hotKeyProcessor.hotkey = warpSettings.hotkey
        let useDoubleTapOnly = warpSettings.doubleTapLockEnabled && warpSettings.useDoubleTapOnly
        hotKeyProcessor.doubleTapLockEnabled = warpSettings.doubleTapLockEnabled
        hotKeyProcessor.useDoubleTapOnly = useDoubleTapOnly
        hotKeyProcessor.minimumKeyTime = warpSettings.minimumKeyTime

        switch inputEvent {
        case .keyboard(let keyEvent):
          // If Escape is pressed with no modifiers while idle, let's treat that as `cancel`.
          if keyEvent.key == .escape, keyEvent.modifiers.isEmpty,
             hotKeyProcessor.state == .idle
          {
            actionContinuation.yield(.cancel)
            return false
          }

          // Process the key event
          switch hotKeyProcessor.process(keyEvent: keyEvent) {
          case .startRecording:
            // If double-tap lock is triggered, we start recording immediately
            if hotKeyProcessor.state == .doubleTapLock {
              actionContinuation.yield(.startRecording)
            } else {
              actionContinuation.yield(.hotKeyPressed)
            }
            return shouldConsumeKeyboardEventForHotkey(
              hotkey: hotKeyProcessor.hotkey,
              useDoubleTapOnly: useDoubleTapOnly,
              keyEvent: keyEvent
            )

          case .stopRecording:
            actionContinuation.yield(.hotKeyReleased)
            return shouldConsumeKeyboardEventForHotkey(
              hotkey: hotKeyProcessor.hotkey,
              useDoubleTapOnly: useDoubleTapOnly,
              keyEvent: keyEvent
            )

          case .cancel:
            actionContinuation.yield(.cancel)
            return true

          case .discard:
            actionContinuation.yield(.discard)
            return shouldConsumeKeyboardEventForHotkey(
              hotkey: hotKeyProcessor.hotkey,
              useDoubleTapOnly: useDoubleTapOnly,
              keyEvent: keyEvent
            )

          case .none:
            // If we detect repeated same chord, maybe intercept.
            if let pressedKey = keyEvent.key,
               pressedKey == hotKeyProcessor.hotkey.key,
               keyEvent.modifiers == hotKeyProcessor.hotkey.modifiers
            {
              return true
            }
            return false
          }

        case .mouseClick:
          // Process mouse click - for modifier-only hotkeys, this may cancel/discard
          switch hotKeyProcessor.processMouseClick() {
          case .cancel:
            actionContinuation.yield(.cancel)
            return false // Don't intercept the click itself
          case .discard:
            actionContinuation.yield(.discard)
            return false // Don't intercept the click itself
          case .startRecording, .stopRecording, .none:
            return false
          }
        }
      }

      defer {
        actionContinuation.finish()
        token.cancel()
      }

      await withTaskCancellationHandler {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
        }
      } onCancel: {}

      await consumer.value
    }
  }

  func warmUpRecorderEffect() -> Effect<Action> {
    .run { _ in
      await recording.warmUpRecorder()
    }
  }
}

// MARK: - HotKey Press/Release Handlers

private extension TranscriptionFeature {
  func handleHotKeyPressed(isTranscribing: Bool) -> Effect<Action> {
    // If already transcribing, cancel first. Otherwise start recording immediately.
    let maybeCancel = isTranscribing ? Effect.send(Action.cancel) : .none
    let startRecording = Effect.send(Action.startRecording)
    return .merge(maybeCancel, startRecording)
  }

  func handleHotKeyReleased(isRecording: Bool) -> Effect<Action> {
    // Always stop recording when hotkey is released
    return isRecording ? .send(.stopRecording) : .none
  }
}

// MARK: - Recording Handlers

private extension TranscriptionFeature {
  func handleStartRecording(_ state: inout State) -> Effect<Action> {
    guard state.modelBootstrapState.isModelReady else {
      return .merge(
        .send(.modelMissing),
        .run { _ in soundEffect.play(.cancel) }
      )
    }
    state.isRecording = true
    let startTime = Date()
    state.recordingStartTime = startTime
    
    // Capture the active application (and browser window title for web-mail style routing)
    if let activeApp = NSWorkspace.shared.frontmostApplication {
      state.sourceAppBundleID = activeApp.bundleIdentifier
      state.sourceAppName = activeApp.localizedName
    }
    let browserTitle = hostContext.focusedBrowserWindowTitle()
    state.sourceBrowserWindowTitle = browserTitle.isEmpty ? nil : browserTitle
    let bundleForLog = state.sourceAppBundleID ?? "nil"
    let isBrowser = StyleBrowserBundle.isBrowser(bundleID: bundleForLog)
    let webmailMatched = StyleWebMailHeuristics.looksLikeWebMailWindow(title: browserTitle)
    transcriptionFeatureLogger.notice("Recording started at \(startTime.ISO8601Format())")
    transcriptionFeatureLogger.notice(
      "Host context bundle=\(bundleForLog, privacy: .public) isBrowser=\(isBrowser, privacy: .public) titleLen=\(browserTitle.count, privacy: .public) webmail=\(webmailMatched, privacy: .public) title=\(browserTitle, privacy: .private)"
    )

    let selectedModel = state.warpSettings.selectedModel
    let isParakeetEOU = ParakeetModel(rawValue: selectedModel)?.isStreamingEOU == true

    // Prevent system sleep during recording
    return .run { [sleepManagement, preventSleep = state.warpSettings.preventSystemSleep] _ in
      // Play sound immediately for instant feedback
      soundEffect.play(.startRecording)

      if preventSleep {
        await sleepManagement.preventSleep(reason: "Warp Voice Recording")
      }

      if isParakeetEOU {
        do {
          try await transcription.beginStreamingParakeetSession(selectedModel) { _ in }
          await recording.setStreamingPCMHandler { buffer in
            Task {
              try? await transcription.feedStreamingParakeetBuffer(buffer)
            }
          }
        } catch {
          transcriptionFeatureLogger.error(
            "Failed to begin Parakeet EOU streaming session: \(error.localizedDescription)"
          )
          await recording.clearStreamingPCMHandler()
        }
      }

      await recording.startRecording()
    }
  }

  func handleStopRecording(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    
    let stopTime = now
    let startTime = state.recordingStartTime
    let duration = startTime.map { stopTime.timeIntervalSince($0) } ?? 0

    let decision = RecordingDecisionEngine.decide(
      .init(
        hotkey: state.warpSettings.hotkey,
        minimumKeyTime: state.warpSettings.minimumKeyTime,
        recordingStartTime: state.recordingStartTime,
        currentTime: stopTime
      )
    )

    let startStamp = startTime?.ISO8601Format() ?? "nil"
    let stopStamp = stopTime.ISO8601Format()
    let minimumKeyTime = state.warpSettings.minimumKeyTime
    let hotkeyHasKey = state.warpSettings.hotkey.key != nil
    transcriptionFeatureLogger.notice(
      "Recording stopped duration=\(String(format: "%.3f", duration))s start=\(startStamp) stop=\(stopStamp) decision=\(String(describing: decision)) minimumKeyTime=\(String(format: "%.2f", minimumKeyTime)) hotkeyHasKey=\(hotkeyHasKey)"
    )

    guard decision == .proceedToTranscription else {
      // If the user recorded for less than minimumKeyTime and the hotkey is modifier-only,
      // discard the audio to avoid accidental triggers.
      transcriptionFeatureLogger.notice("Discarding short recording per decision \(String(describing: decision))")
      return .run { _ in
        await recording.clearStreamingPCMHandler()
        await transcription.resetStreamingParakeet()
        let url = await recording.stopRecording()
        try? FileManager.default.removeItem(at: url)
      }
    }

    // Otherwise, proceed to transcription
    state.isTranscribing = true
    state.error = nil
    let model = state.warpSettings.selectedModel
    let language = state.warpSettings.outputLanguage

    state.isPrewarming = true

    let isParakeetEOU = ParakeetModel(rawValue: model)?.isStreamingEOU == true

    return .run { [sleepManagement] send in
      // Allow system to sleep again
      await sleepManagement.allowSleep()

      var audioURL: URL?
      do {
        let capturedURL = await recording.stopRecording()
        soundEffect.play(.stopRecording)
        audioURL = capturedURL
        await recording.clearStreamingPCMHandler()

        let decodeOptions = DecodingOptions(
          language: language,
          detectLanguage: language == nil,
          chunkingStrategy: .vad,
        )

        let result: String
        if isParakeetEOU {
          let usedCaptureEngine = await recording.lastRecordingUsedCaptureEngine()
          if usedCaptureEngine {
            var streamResult: String
            do {
              streamResult = try await transcription.finishStreamingParakeetTranscription()
            } catch {
              transcriptionFeatureLogger.notice(
                "Parakeet EOU finish failed; falling back to file: \(error.localizedDescription)"
              )
              streamResult = try await transcription.transcribe(
                capturedURL, model, decodeOptions
              ) { _ in }
            }
            if streamResult.isEmpty {
              transcriptionFeatureLogger.notice("Parakeet EOU: empty stream output; transcribing from file")
              streamResult = try await transcription.transcribe(
                capturedURL, model, decodeOptions
              ) { _ in }
            }
            result = streamResult
            await transcription.resetStreamingParakeet()
          } else {
            transcriptionFeatureLogger.notice(
              "Parakeet EOU: capture engine unavailable; transcribing from file instead"
            )
            result = try await transcription.transcribe(capturedURL, model, decodeOptions) { _ in }
            await transcription.resetStreamingParakeet()
          }
        } else {
          result = try await transcription.transcribe(capturedURL, model, decodeOptions) { _ in }
        }

        transcriptionFeatureLogger.notice("Transcribed audio from \(capturedURL.lastPathComponent) to text length \(result.count)")
        await send(.transcriptionResult(result, capturedURL))
      } catch {
        transcriptionFeatureLogger.error("Transcription failed: \(error.localizedDescription)")
        await transcription.resetStreamingParakeet()
        await send(.transcriptionError(error, audioURL))
      }
    }
    .cancellable(id: CancelID.transcription)
  }
}

// MARK: - Transcription Handlers

private extension TranscriptionFeature {
  func handleTranscriptionResult(
    _ state: inout State,
    result: String,
    audioURL: URL
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false
    state.error = nil

    // Check for force quit command (emergency escape hatch)
    if ForceQuitCommandDetector.matches(result) {
      transcriptionFeatureLogger.fault("Force quit voice command recognized; terminating Warp.")
      return .run { _ in
        try? FileManager.default.removeItem(at: audioURL)
        await MainActor.run {
          NSApp.terminate(nil)
        }
      }
    }

    // If empty text, nothing else to do
    guard !result.isEmpty else {
      return .none
    }

    let duration = state.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

    transcriptionFeatureLogger.info("Raw transcription: '\(result)'")
    let remappings = state.warpSettings.wordRemappings
    let removalsEnabled = state.warpSettings.wordRemovalsEnabled
    let removals = state.warpSettings.wordRemovals
    let applyUserModifications = !state.isRemappingScratchpadFocused
    if !applyUserModifications {
      transcriptionFeatureLogger.info("Scratchpad focused; skipping word modifications")
    }

    let shouldRunMercury =
      state.warpSettings.mercuryTransformEnabled
      && !state.isRemappingScratchpadFocused

    if shouldRunMercury {
      state.isMercuryTransforming = true
    }

    let instructions = state.warpSettings.resolvedMercuryAdditionalInstructions(
      frontmostBundleID: state.sourceAppBundleID,
      browserWindowTitle: state.sourceBrowserWindowTitle
    )
    let route = state.warpSettings.resolvedStyleRoute(
      frontmostBundleID: state.sourceAppBundleID,
      browserWindowTitle: state.sourceBrowserWindowTitle
    )
    mercuryTransformLogger.notice(
      "Mercury style routing context=\(String(describing: route.context)) preset=\(String(describing: route.presetSlot))"
    )
    let sourceAppBundleID = state.sourceAppBundleID
    let sourceAppName = state.sourceAppName
    let transcriptionHistory = state.$transcriptionHistory

    return .run { send in
      // Pipeline: Mercury post-processing → word removals → word remappings.
      // Remappings run last so user-defined substitutions are always the final word,
      // even if Mercury rewrites or normalizes wording.
      var textToPaste = result

      if shouldRunMercury {
        do {
          let key = try await inceptionAPIKey.load()
          if let key, !key.isEmpty {
            do {
              textToPaste = try await mercuryTransform.transform(
                result,
                instructions,
                key
              )
            } catch {
              mercuryTransformLogger.error("Mercury transform failed: \(error.localizedDescription)")
              await send(.reportMercuryIssue(String(localized: "mercury.transformFailed", bundle: .main)))
            }
          } else {
            mercuryTransformLogger.notice("Mercury post-processing enabled but no API key in Keychain")
            await send(.reportMercuryIssue(String(localized: "mercury.missingKey", bundle: .main)))
          }
        } catch {
          mercuryTransformLogger.error("Keychain error loading Inception API key: \(error.localizedDescription)")
          await send(.reportMercuryIssue(String(localized: "mercury.keychainError", bundle: .main)))
        }
        await send(.mercuryTransformDidFinish)
      }

      if applyUserModifications {
        if removalsEnabled {
          let removed = WordRemovalApplier.apply(textToPaste, removals: removals)
          if removed != textToPaste {
            let enabledRemovalCount = removals.filter(\.isEnabled).count
            transcriptionFeatureLogger.info("Applied \(enabledRemovalCount) word removal(s) post-Mercury")
          }
          textToPaste = removed
        }
        let remapped = WordRemappingApplier.apply(textToPaste, remappings: remappings)
        if remapped != textToPaste {
          transcriptionFeatureLogger.info("Applied \(remappings.count) word remapping(s) post-Mercury")
        }
        textToPaste = remapped
      }

      guard !textToPaste.isEmpty else { return }

      do {
        try await finalizeRecordingAndStoreTranscript(
          result: textToPaste,
          duration: duration,
          sourceAppBundleID: sourceAppBundleID,
          sourceAppName: sourceAppName,
          audioURL: audioURL,
          transcriptionHistory: transcriptionHistory
        )
      } catch {
        await send(.transcriptionError(error, audioURL))
      }
    }
    .cancellable(id: CancelID.transcription)
  }

  func handleTranscriptionError(
    _ state: inout State,
    error: Error,
    audioURL: URL?
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isMercuryTransforming = false
    state.isPrewarming = false
    state.error = error.localizedDescription
    
    if let audioURL {
      try? FileManager.default.removeItem(at: audioURL)
    }

    return .none
  }

  /// Move file to permanent location, create a transcript record, paste text, and play sound.
  func finalizeRecordingAndStoreTranscript(
    result: String,
    duration: TimeInterval,
    sourceAppBundleID: String?,
    sourceAppName: String?,
    audioURL: URL,
    transcriptionHistory: Shared<TranscriptionHistory>
  ) async throws {
    @Shared(.warpSettings) var warpSettings: WarpSettings

    if warpSettings.saveTranscriptionHistory {
      let transcript = try await transcriptPersistence.save(
        result,
        audioURL,
        duration,
        sourceAppBundleID,
        sourceAppName
      )

      transcriptionHistory.withLock { history in
        history.history.insert(transcript, at: 0)

        if let maxEntries = warpSettings.maxHistoryEntries, maxEntries > 0 {
          while history.history.count > maxEntries {
            if let removedTranscript = history.history.popLast() {
              Task {
                 try? await transcriptPersistence.deleteAudio(removedTranscript)
              }
            }
          }
        }
      }
    } else {
      try? FileManager.default.removeItem(at: audioURL)
    }

    await pasteboard.paste(result)
    soundEffect.play(.pasteTranscript)
  }
}

// MARK: - Cancel/Discard Handlers

private extension TranscriptionFeature {
  func handleCancel(_ state: inout State) -> Effect<Action> {
    state.isTranscribing = false
    state.isMercuryTransforming = false
    state.isRecording = false
    state.isPrewarming = false

    return .merge(
      .cancel(id: CancelID.transcription),
      .run { [sleepManagement] _ in
        // Allow system to sleep again
        await sleepManagement.allowSleep()
        await recording.clearStreamingPCMHandler()
        await transcription.resetStreamingParakeet()
        // Stop the recording to release microphone access
        let url = await recording.stopRecording()
        try? FileManager.default.removeItem(at: url)
        soundEffect.play(.cancel)
      }
    )
  }

  func handleDiscard(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    state.isPrewarming = false

    // Silently discard - no sound effect
    return .run { [sleepManagement] _ in
      // Allow system to sleep again
      await sleepManagement.allowSleep()
      await recording.clearStreamingPCMHandler()
      await transcription.resetStreamingParakeet()
      let url = await recording.stopRecording()
      try? FileManager.default.removeItem(at: url)
    }
  }
}

// MARK: - View

struct TranscriptionView: View {
  @Bindable var store: StoreOf<TranscriptionFeature>
  @ObserveInjection var inject

  var status: TranscriptionIndicatorView.Status {
    if store.isTranscribing || store.isMercuryTransforming {
      return .transcribing
    } else if store.isRecording {
      return .recording
    } else if store.isPrewarming {
      return .prewarming
    } else {
      return .hidden
    }
  }

  private var appIcon: NSImage? {
    guard let bundleID = store.sourceAppBundleID,
          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: appURL.path)
  }

  private var presetLabel: String? {
    guard store.warpSettings.mercuryTransformEnabled else { return nil }
    let route = store.warpSettings.resolvedStyleRoute(
      frontmostBundleID: store.sourceAppBundleID,
      browserWindowTitle: store.sourceBrowserWindowTitle
    )
    let slot = route.presetSlot.rawValue.capitalized
    return route.context == .email ? "Email · \(slot)" : slot
  }

  var body: some View {
    TranscriptionIndicatorView(
      status: status,
      meter: store.meter,
      appName: store.sourceAppName,
      appIcon: appIcon,
      presetLabel: presetLabel
    )
    .task {
      await store.send(.task).finish()
    }
    .enableInjection()
  }
}

// MARK: - Force Quit Command

private enum ForceQuitCommandDetector {
  static func matches(_ text: String) -> Bool {
    let normalized = normalize(text)
    return normalized == "force quit warp now" || normalized == "force quit warp"
  }

  private static func normalize(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
