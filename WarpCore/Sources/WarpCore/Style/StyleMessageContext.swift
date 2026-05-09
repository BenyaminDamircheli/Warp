import Foundation

/// Top-level Style tabs: where the user routes different formatting presets.
public enum StyleMessageContext: String, Codable, CaseIterable, Sendable, Equatable {
	case personal
	case work
	case email
	case other
}

/// One of three selectable cards per context (Formal / Casual / Expressive third slot).
public enum StylePresetSlot: String, Codable, CaseIterable, Sendable, Equatable {
	case formal
	case casual
	case expressive
}

/// Per-tab configuration: which apps use this bucket and which preset card is selected.
public struct StyleBucketSettings: Codable, Equatable, Sendable {
	public var linkedBundleIDs: [String]
	public var selectedPresetSlot: StylePresetSlot

	public init(
		linkedBundleIDs: [String] = [],
		selectedPresetSlot: StylePresetSlot = .formal
	) {
		self.linkedBundleIDs = linkedBundleIDs
		self.selectedPresetSlot = selectedPresetSlot
	}
}

public enum StyleDefaults {
	public static let personalBundleIDs: [String] = [
		"com.apple.MobileSMS",
		"net.whatsapp.WhatsApp",
		"org.telegram.desktop",
		"com.facebook.archon",    // Messenger
		"com.hnc.Discord",
		"com.instagram.mac",
	]

	public static let workBundleIDs: [String] = [
		"com.tinyspeck.slackmacgap",
		"com.microsoft.teams2",
		"com.microsoft.teams",
		"com.linkedin.LinkedInHelper",
	]

	public static let emailBundleIDs: [String] = [
		"com.apple.mail",
		"com.microsoft.Outlook",
		"com.readdle.smartemail-macos",
		"com.superhuman.mail",
	]

	public static let otherBundleIDs: [String] = [
		"com.apple.Notes",
	]
}

extension WarpSettings {
	public mutating func updateStyleBucket(
		_ context: StyleMessageContext,
		transform: (inout StyleBucketSettings) -> Void
	) {
		switch context {
		case .personal: transform(&stylePersonal)
		case .work: transform(&styleWork)
		case .email: transform(&styleEmail)
		case .other: transform(&styleOther)
		}
	}

	public func styleBucket(for context: StyleMessageContext) -> StyleBucketSettings {
		switch context {
		case .personal: stylePersonal
		case .work: styleWork
		case .email: styleEmail
		case .other: styleOther
		}
	}
}
