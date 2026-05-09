# Warp

A macOS menu bar app for voice-to-text. Hold a hotkey, talk, release — your words land in the active app.

## Private and local-first by default

Transcription runs entirely on your Mac. No accounts, no telemetry, no audio leaving the device. Your microphone goes to a Core ML model on-device and the result goes to your clipboard or the focused text field.

The default model is **Parakeet TDT v3** (multilingual) via FluidAudio. **Whisper** (Small / Medium / Large v3) is also available via WhisperKit. Models are downloaded once into the app's sandbox container and run offline from then on.

## Optional cloud post-processing

If you want a cleanup pass — fixing punctuation, removing filler words, applying a writing style — you can turn on **Post-processing** in Settings. When enabled, the transcript (text only, never audio) is sent to [Inception Labs' Mercury](https://docs.inceptionlabs.ai/get-started/get-started) model with your own API key. The key lives in your macOS Keychain on this Mac only.

This is opt-in. With the toggle off, nothing leaves the device.

## Why I use it

For my workflow, Warp is on average about **~15% faster than Wispr Flow** end-to-end and roughly **~35% cheaper** (though "cheaper" depends entirely on how much post-processing you do). With post-processing off, **it's free**: you're paying $0 for transcription because it runs locally. With post-processing on, you pay Inception per token for the cleanup pass and nothing else.

Your mileage will vary based on dictation volume, model choice, and how aggressive your style preset is.

## Features

- **Hotkey modes** — press-and-hold or double-tap, configured per hotkey. Modifier-only hotkeys (e.g. Option) use a 0.3s threshold to avoid clashing with OS shortcuts.
- **Word remappings** — local find-and-replace rules applied before any cloud step.
- **Style presets** — saved instruction blocks for the post-processing pass (tone, punctuation, formatting).
- **Transcription history** — stored locally; clearable from Settings.
- **Auto-paste** — drops the result into the focused text field via the pasteboard.
- **Sound cues** — start/stop/cancel feedback, toggleable.

## Architecture

Built with [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). The main pieces:

- `AppFeature` — root reducer, app lifecycle.
- `TranscriptionFeature` — recording + transcription pipeline.
- `SettingsFeature` — preferences, model management, API keys.
- `HistoryFeature` — past transcriptions.

Dependency clients (`TranscriptionClient`, `RecordingClient`, `PasteboardClient`, `KeyEventMonitorClient`, `MercuryTransformClient`) wrap the underlying frameworks so features stay testable.

Core logic — hotkey processing, settings models — lives in the `WarpCore` Swift package and is unit-tested separately.

## Build

Requires macOS 14+ and Xcode 15+.

```bash
# Open in Xcode (recommended)
open Warp.xcodeproj

# Or build from the command line
xcodebuild -scheme Warp -configuration Release

# Run unit tests
cd WarpCore && swift test
```

## Storage locations

Models are kept inside the app sandbox so they survive across launches and respect macOS's container model:

- **WhisperKit** — `~/Library/Application Support/com.benyamindamircheli.warp/models/argmaxinc/whisperkit-coreml/<model>`
- **Parakeet (FluidAudio)** — `~/Library/Containers/com.benyamindamircheli.warp/Data/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml`

`XDG_CACHE_HOME` is set at launch so FluidAudio caches inside the container rather than `~/.cache`, which the sandbox can't see.

## Permissions

Warp asks for:

- **Microphone** — to record what you're saying.
- **Accessibility / Apple Events** — to paste into the focused app and read the active app context.
- **Network** — only for model downloads and (if enabled) the post-processing API call.

## License

Personal project. No license granted; do not redistribute.
