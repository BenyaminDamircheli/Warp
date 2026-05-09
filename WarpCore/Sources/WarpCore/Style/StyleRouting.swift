import Foundation

public enum StyleRouting: Sendable {
	/// Priority when the same bundle ID appears in multiple buckets: work → personal → email (native list) → other.
	/// Web-mail (browser title) always wins first. Email contexts are pinned to the Formal preset
	/// regardless of the email bucket's selected slot — emails should always sound formal.
	public static func resolve(
		frontmostBundleID: String?,
		browserWindowTitle: String?,
		settings: WarpSettings
	) -> (context: StyleMessageContext, presetSlot: StylePresetSlot) {
		if let bid = frontmostBundleID,
		   StyleBrowserBundle.isBrowser(bundleID: bid),
		   StyleWebMailHeuristics.looksLikeWebMailWindow(title: browserWindowTitle)
		{
			return (.email, .formal)
		}

		guard let bid = frontmostBundleID else {
			return (.other, settings.styleOther.selectedPresetSlot)
		}

		if settings.styleWork.linkedBundleIDs.contains(bid) {
			return (.work, settings.styleWork.selectedPresetSlot)
		}
		if settings.stylePersonal.linkedBundleIDs.contains(bid) {
			return (.personal, settings.stylePersonal.selectedPresetSlot)
		}
		if settings.styleEmail.linkedBundleIDs.contains(bid) {
			return (.email, .formal)
		}
		if settings.styleOther.linkedBundleIDs.contains(bid) {
			return (.other, settings.styleOther.selectedPresetSlot)
		}

		return (.other, settings.styleOther.selectedPresetSlot)
	}
}

extension WarpSettings {
	/// Combined routing label, Style preset appendix, and optional `mercuryTransformInstructions` user supplement.
	public func resolvedMercuryAdditionalInstructions(
		frontmostBundleID: String?,
		browserWindowTitle: String?
	) -> String {
		let route = StyleRouting.resolve(
			frontmostBundleID: frontmostBundleID,
			browserWindowTitle: browserWindowTitle,
			settings: self
		)
		let routing = "ACTIVE ROUTING: Style context=\(route.context.rawValue), preset=\(route.presetSlot.rawValue)."
		let preset = StyleMercuryPresets.mercuryAppendix(
			context: route.context,
			slot: route.presetSlot
		)
		let extra = mercuryTransformInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
		if extra.isEmpty {
			return routing + "\n\n" + preset
		}
		return routing + "\n\n" + preset + "\n\n---\nUser supplement (optional):\n\n" + extra
	}

	public func resolvedStyleRoute(
		frontmostBundleID: String?,
		browserWindowTitle: String?
	) -> (context: StyleMessageContext, presetSlot: StylePresetSlot) {
		StyleRouting.resolve(
			frontmostBundleID: frontmostBundleID,
			browserWindowTitle: browserWindowTitle,
			settings: self
		)
	}
}
