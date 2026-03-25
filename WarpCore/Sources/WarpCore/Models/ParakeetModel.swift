import Foundation

/// Known Parakeet Core ML bundles that Hex supports.
public enum ParakeetModel: String, CaseIterable, Sendable {
	case englishV2 = "parakeet-tdt-0.6b-v2-coreml"
	case multilingualV3 = "parakeet-tdt-0.6b-v3-coreml"
	/// Parakeet EOU streaming ASR (FluidAudio `StreamingEouAsrManager`, 160ms chunks; English-oriented).
	case eouStreaming160 = "parakeet-eou-streaming-160ms"

	/// The identifier used throughout the app (matches the on-disk folder name).
	public var identifier: String { rawValue }

	/// TDT batch models (`AsrManager`).
	public var isTDT: Bool {
		self == .englishV2 || self == .multilingualV3
	}

	/// Streaming EOU model (`StreamingEouAsrManager`).
	public var isStreamingEOU: Bool {
		self == .eouStreaming160
	}

	/// Whether the model only supports English transcription.
	public var isEnglishOnly: Bool {
		self == .englishV2 || self == .eouStreaming160
	}

	/// Short capability label for UI copy.
	public var capabilityLabel: String {
		switch self {
		case .eouStreaming160:
			return "English · Streaming"
		case .englishV2, .multilingualV3:
			return isEnglishOnly ? "English" : "Multilingual"
		}
	}

	/// Convenience text for recommendation badges.
	public var recommendationLabel: String {
		isEnglishOnly ? "Recommended (English)" : "Recommended (Multilingual)"
	}
}
