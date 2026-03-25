import ComposableArchitecture
import Dependencies
import Foundation
import WarpCore

// Re-export types so the app target can use them without WarpCore prefixes.
typealias RecordingAudioBehavior = WarpCore.RecordingAudioBehavior
typealias WarpSettings = WarpCore.WarpSettings

extension SharedReaderKey
	where Self == FileStorageKey<WarpSettings>.Default
{
	static var warpSettings: Self {
		Self[
			.fileStorage(.warpSettingsURL),
			default: .init()
		]
	}
}

// MARK: - Storage Migration

extension URL {
	static var warpSettingsURL: URL {
		get {
			URL.warpMigratedFileURL(named: "warp_settings.json")
		}
	}
}
