import XCTest
@testable import WarpCore

final class StyleRoutingTests: XCTestCase {
	func testWebMailInChromePinsToFormal() {
		var s = WarpSettings()
		s.styleEmail.selectedPresetSlot = .casual
		s.styleOther.selectedPresetSlot = .expressive

		let route = StyleRouting.resolve(
			frontmostBundleID: "com.google.Chrome",
			browserWindowTitle: "Inbox (12) - user@gmail.com - Gmail",
			settings: s
		)

		XCTAssertEqual(route.context, .email)
		XCTAssertEqual(route.presetSlot, .formal)
	}

	func testNativeEmailAppPinsToFormal() {
		var s = WarpSettings()
		s.styleEmail.selectedPresetSlot = .expressive

		let route = StyleRouting.resolve(
			frontmostBundleID: "com.apple.mail",
			browserWindowTitle: nil,
			settings: s
		)

		XCTAssertEqual(route.context, .email)
		XCTAssertEqual(route.presetSlot, .formal)
	}

	func testLinkedWorkWinsOverPersonalWhenBothContainBundle() {
		var s = WarpSettings()
		s.styleWork.linkedBundleIDs = ["com.tinyspeck.slackmacgap"]
		s.stylePersonal.linkedBundleIDs = ["com.tinyspeck.slackmacgap"]
		s.styleWork.selectedPresetSlot = .formal
		s.stylePersonal.selectedPresetSlot = .expressive

		let route = StyleRouting.resolve(
			frontmostBundleID: "com.tinyspeck.slackmacgap",
			browserWindowTitle: nil,
			settings: s
		)

		XCTAssertEqual(route.context, .work)
		XCTAssertEqual(route.presetSlot, .formal)
	}

	func testUnknownBundleFallsBackToOtherPreset() {
		var s = WarpSettings()
		s.styleOther.selectedPresetSlot = .expressive

		let route = StyleRouting.resolve(
			frontmostBundleID: "com.example.unknown",
			browserWindowTitle: nil,
			settings: s
		)

		XCTAssertEqual(route.context, .other)
		XCTAssertEqual(route.presetSlot, .expressive)
	}

	func testWebMailTakesPriorityOverWorkBucketContainingSameBrowser() {
		var s = WarpSettings()
		s.styleWork.linkedBundleIDs = ["com.google.Chrome"]
		s.styleWork.selectedPresetSlot = .casual
		s.styleEmail.selectedPresetSlot = .casual

		let route = StyleRouting.resolve(
			frontmostBundleID: "com.google.Chrome",
			browserWindowTitle: "Mail - Jane Doe - Outlook",
			settings: s
		)

		XCTAssertEqual(route.context, .email)
		XCTAssertEqual(route.presetSlot, .formal)
	}
}
