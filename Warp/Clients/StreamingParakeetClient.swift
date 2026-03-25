import AVFoundation
import Foundation
import WarpCore

#if canImport(FluidAudio)
import FluidAudio

private let streamingParakeetLogger = WarpLog.parakeet

/// Wraps FluidAudio `StreamingEouAsrManager` for Parakeet EOU streaming ASR.
actor StreamingParakeetClient {
  private var manager: StreamingEouAsrManager?
  private var loadedVariant: ParakeetModel?
  private var activeBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
  private var activeBufferProcessorTask: Task<Void, Error>?

  func isModelAvailable(_ modelName: String) async -> Bool {
    guard let variant = ParakeetModel(rawValue: modelName), variant.isStreamingEOU else {
      return false
    }
    let modelDir = Self.eouModelDirectory()
    let required = ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc", "vocab.json"]
    return required.allSatisfy { FileManager.default.fileExists(atPath: modelDir.appendingPathComponent($0).path) }
  }

  func ensureLoaded(modelName: String, progress: @escaping (Progress) -> Void) async throws {
    guard let variant = ParakeetModel(rawValue: modelName), variant.isStreamingEOU else {
      throw NSError(
        domain: "StreamingParakeet",
        code: -4,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported streaming Parakeet variant: \(modelName)"]
      )
    }
    if loadedVariant == variant, manager != nil { return }

    let p = Progress(totalUnitCount: 100)
    p.completedUnitCount = 1
    progress(p)

    let modelDir = Self.eouModelDirectory()
    if !Self.eouModelsOnDisk(at: modelDir) {
      streamingParakeetLogger.notice("Downloading Parakeet EOU 160ms models from Hugging Face…")
      p.completedUnitCount = 5
      progress(p)
      // Use Warp downloader: FluidAudio's `downloadRepo` verifies `tokenizer.model` + preprocessor
      // which this HF layout does not ship; `StreamingEouAsrManager` only needs encoder/decoder/joint + vocab.
      try await ParakeetEouStreamingDownloader.download160msIfMissing(
        fluidAudioModelsDirectory: Self.fluidAudioModelsDirectory()
      )
      p.completedUnitCount = 90
      progress(p)
    }

    let manager = StreamingEouAsrManager(chunkSize: .ms160, eouDebounceMs: 1280, debugFeatures: false)
    try await manager.loadModels(modelDir: modelDir)
    self.manager = manager
    self.loadedVariant = variant
    p.completedUnitCount = 100
    progress(p)
    streamingParakeetLogger.notice("Streaming Parakeet EOU ensureLoaded variant=\(variant.identifier)")
  }

  func beginSession(modelName: String, progress: @escaping (Progress) -> Void) async throws {
    await stopBufferProcessor()
    try await ensureLoaded(modelName: modelName, progress: progress)
    guard let manager else {
      throw NSError(
        domain: "StreamingParakeet",
        code: -6,
        userInfo: [NSLocalizedDescriptionKey: "Streaming Parakeet not initialized"]
      )
    }

    await manager.reset()

    var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    let stream = AsyncStream<AVAudioPCMBuffer> { continuation = $0 }
    self.activeBufferContinuation = continuation
    self.activeBufferProcessorTask = Task {
      for await buffer in stream {
        try Task.checkCancellation()
        _ = try await manager.process(audioBuffer: buffer)
      }
    }
  }

  func reset() async {
    await stopBufferProcessor()
    await manager?.reset()
  }

  func process(buffer: AVAudioPCMBuffer) async throws {
    guard manager != nil else {
      throw NSError(
        domain: "StreamingParakeet",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Streaming Parakeet not initialized"]
      )
    }
    guard let activeBufferContinuation else {
      throw NSError(
        domain: "StreamingParakeet",
        code: -7,
        userInfo: [NSLocalizedDescriptionKey: "Streaming Parakeet session is not active"]
      )
    }
    activeBufferContinuation.yield(buffer)
  }

  func finish() async throws -> String {
    guard let manager else {
      throw NSError(
        domain: "StreamingParakeet",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Streaming Parakeet not initialized"]
      )
    }
    try await finishBufferProcessor()
    return try await manager.finish()
  }

  /// Batch-style transcription for a file (e.g. recorder fallback with no live PCM tap).
  func transcribeFile(_ url: URL) async throws -> String {
    guard let manager else {
      throw NSError(
        domain: "StreamingParakeet",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Streaming Parakeet not initialized"]
      )
    }
    await stopBufferProcessor()
    await manager.reset()
    let audioFile = try AVAudioFile(forReading: url)
    let format = audioFile.processingFormat
    let frameCount = AVAudioFrameCount(audioFile.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      throw NSError(
        domain: "StreamingParakeet",
        code: -5,
        userInfo: [NSLocalizedDescriptionKey: "Failed to allocate audio buffer"]
      )
    }
    try audioFile.read(into: buffer)
    _ = try await manager.process(audioBuffer: buffer)
    return try await manager.finish()
  }

  func deleteCaches(modelName: String) async throws {
    guard let variant = ParakeetModel(rawValue: modelName), variant.isStreamingEOU else { return }
    await stopBufferProcessor()
    let dir = Self.parakeetEouStreamingRootDirectory()
    if FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.removeItem(at: dir)
    }
    manager = nil
    loadedVariant = nil
  }

  private static func fluidAudioModelsDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("FluidAudio/Models", isDirectory: true)
  }

  /// `…/FluidAudio/Models/parakeet-eou-streaming` (matches FluidAudio `Repo.parakeetEou160` cache layout).
  private static func parakeetEouStreamingRootDirectory() -> URL {
    fluidAudioModelsDirectory().appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
  }

  private static func eouModelDirectory() -> URL {
    fluidAudioModelsDirectory().appendingPathComponent("parakeet-eou-streaming/160ms", isDirectory: true)
  }

  private static func eouModelsOnDisk(at modelDir: URL) -> Bool {
    let required = ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc", "vocab.json"]
    return required.allSatisfy { FileManager.default.fileExists(atPath: modelDir.appendingPathComponent($0).path) }
  }

  private func finishBufferProcessor() async throws {
    activeBufferContinuation?.finish()
    activeBufferContinuation = nil

    if let activeBufferProcessorTask {
      self.activeBufferProcessorTask = nil
      try await activeBufferProcessorTask.value
    }
  }

  private func stopBufferProcessor() async {
    activeBufferContinuation?.finish()
    activeBufferContinuation = nil

    if let activeBufferProcessorTask {
      activeBufferProcessorTask.cancel()
      self.activeBufferProcessorTask = nil
      _ = try? await activeBufferProcessorTask.value
    }
  }
}

#else

actor StreamingParakeetClient {
  func isModelAvailable(_ modelName: String) async -> Bool { false }
  func ensureLoaded(modelName: String, progress: @escaping (Progress) -> Void) async throws {
    throw NSError(
      domain: "StreamingParakeet",
      code: -2,
      userInfo: [NSLocalizedDescriptionKey: "Parakeet support not linked."]
    )
  }
  func beginSession(modelName: String, progress: @escaping (Progress) -> Void) async throws {
    throw NSError(
      domain: "StreamingParakeet",
      code: -2,
      userInfo: [NSLocalizedDescriptionKey: "Parakeet support not linked."]
    )
  }
  func reset() async {}
  func process(buffer: AVAudioPCMBuffer) async throws {}
  func finish() async throws -> String {
    throw NSError(
      domain: "StreamingParakeet",
      code: -2,
      userInfo: [NSLocalizedDescriptionKey: "Parakeet support not linked."]
    )
  }
  func transcribeFile(_ url: URL) async throws -> String {
    throw NSError(
      domain: "StreamingParakeet",
      code: -2,
      userInfo: [NSLocalizedDescriptionKey: "Parakeet support not linked."]
    )
  }
  func deleteCaches(modelName: String) async throws {}
}

#endif
