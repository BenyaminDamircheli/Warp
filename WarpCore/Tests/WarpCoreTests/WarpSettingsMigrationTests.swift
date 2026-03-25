import XCTest
@testable import WarpCore

final class WarpSettingsMigrationTests: XCTestCase {
	func testV1FixtureMigratesToCurrentDefaults() throws {
		let data = try loadFixture(named: "v1")
		let decoded = try JSONDecoder().decode(WarpSettings.self, from: data)

		XCTAssertEqual(decoded.recordingAudioBehavior, .pauseMedia, "Legacy pauseMediaOnRecord bool should map to pauseMedia behavior")
		XCTAssertEqual(decoded.soundEffectsEnabled, false)
		XCTAssertEqual(decoded.soundEffectsVolume, WarpSettings.baseSoundEffectsVolume)
		XCTAssertEqual(decoded.openOnLogin, true)
		XCTAssertEqual(decoded.showDockIcon, false)
		XCTAssertEqual(decoded.selectedModel, "whisper-large-v3")
		XCTAssertEqual(decoded.useClipboardPaste, false)
		XCTAssertEqual(decoded.preventSystemSleep, true)
		XCTAssertEqual(decoded.minimumKeyTime, 0.25)
		XCTAssertEqual(decoded.copyToClipboard, true)
		XCTAssertFalse(decoded.superFastModeEnabled)
		XCTAssertEqual(decoded.useDoubleTapOnly, true)
		XCTAssertEqual(decoded.doubleTapLockEnabled, true)
		XCTAssertEqual(decoded.outputLanguage, "en")
		XCTAssertEqual(decoded.selectedMicrophoneID, "builtin:mic")
		XCTAssertEqual(decoded.saveTranscriptionHistory, false)
		XCTAssertEqual(decoded.maxHistoryEntries, 10)
		XCTAssertEqual(decoded.hasCompletedModelBootstrap, true)
		XCTAssertEqual(decoded.hasCompletedStorageMigration, true)
		XCTAssertFalse(decoded.mercuryTransformEnabled)
		XCTAssertEqual(decoded.mercuryTransformInstructions, "")
	}

	func testEncodeDecodeRoundTripPreservesDefaults() throws {
		let settings = WarpSettings()
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(WarpSettings.self, from: data)
		XCTAssertEqual(decoded, settings)
	}

	func testMercuryTransformSettingsRoundTrip() throws {
		var settings = WarpSettings()
		settings.mercuryTransformEnabled = true
		settings.mercuryTransformInstructions = "Prefer UK spelling."
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(WarpSettings.self, from: data)
		XCTAssertTrue(decoded.mercuryTransformEnabled)
		XCTAssertEqual(decoded.mercuryTransformInstructions, "Prefer UK spelling.")
	}

	func testDecodeNormalizesLegacyMercuryFullPromptFieldToEmpty() throws {
		var settings = WarpSettings()
		settings.mercuryTransformInstructions = WarpSettings.defaultMercuryTransformInstructions
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(WarpSettings.self, from: data)
		XCTAssertEqual(decoded.mercuryTransformInstructions, "")
	}

	func testInitNormalizesDoubleTapOnlyWhenLockDisabled() {
		let settings = WarpSettings(useDoubleTapOnly: true, doubleTapLockEnabled: false)

		XCTAssertFalse(settings.useDoubleTapOnly)
		XCTAssertFalse(settings.doubleTapLockEnabled)
	}

	func testDecodeNormalizesDoubleTapOnlyWhenLockDisabled() throws {
		let payload = "{\"useDoubleTapOnly\":true,\"doubleTapLockEnabled\":false}"
		guard let data = payload.data(using: .utf8) else {
			XCTFail("Failed to encode JSON payload")
			return
		}

		let decoded = try JSONDecoder().decode(WarpSettings.self, from: data)

		XCTAssertFalse(decoded.useDoubleTapOnly)
		XCTAssertFalse(decoded.doubleTapLockEnabled)
	}

	func testEncodeDecodeRoundTripPreservesNormalizedDoubleTapValues() throws {
		let settings = WarpSettings(useDoubleTapOnly: true, doubleTapLockEnabled: false)
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(WarpSettings.self, from: data)

		XCTAssertFalse(settings.useDoubleTapOnly)
		XCTAssertFalse(decoded.useDoubleTapOnly)
		XCTAssertEqual(decoded, settings)
	}

	private func loadFixture(named name: String) throws -> Data {
		guard let url = Bundle.module.url(
			forResource: name,
			withExtension: "json",
			subdirectory: "Fixtures/WarpSettings"
		) else {
			XCTFail("Missing fixture \(name).json")
			throw NSError(domain: "Fixture", code: 0)
		}
		return try Data(contentsOf: url)
	}
}
