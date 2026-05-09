import Foundation

/// Known macOS browser bundle IDs (best-effort). User-linked apps are separate; this drives window-title web-mail detection.
public enum StyleBrowserBundle {
	/// Stored lowercased so matching is case-insensitive — bundle IDs are technically case-sensitive but
	/// inconsistencies (e.g. Dia ships as `company.thebrowser.dia` while Arc uses `company.thebrowser.Browser`)
	/// caused real misses in practice.
	public static let identifiers: Set<String> = [
		"com.apple.safari",
		"com.apple.safaritechnologypreview",
		"com.google.chrome",
		"com.google.chrome.canary",
		"com.google.chrome.beta",
		"com.google.chrome.dev",
		"com.microsoft.edgemac",
		"com.microsoft.edgemac.beta",
		"com.microsoft.edgemac.dev",
		"company.thebrowser.browser", // Arc
		"company.thebrowser.dia",     // Dia
		"org.mozilla.firefox",
		"org.mozilla.firefoxdeveloperedition",
		"org.mozilla.nightly",
		"com.brave.browser",
		"com.brave.browser.beta",
		"com.brave.browser.nightly",
		"com.vivaldi.vivaldi",
		"com.operasoftware.opera",
		"com.operasoftware.operagx",
		"app.zen-browser.zen",        // Zen Browser
		"com.kagi.kagimacos",         // Orion
		"com.thebrowser.orion",       // Orion (alternate)
		"com.duckduckgo.macos.browser",
	]

	public static func isBrowser(bundleID: String) -> Bool {
		identifiers.contains(bundleID.lowercased())
	}
}

/// Heuristic substrings for webmail in the focused window title (any browser).
public enum StyleWebMailHeuristics {
	public static let titleSubstrings: [String] = [
		"gmail",
		"mail.google",
		"google mail",
		"inbox",
		"outlook",
		"hotmail",
		"fastmail",
		"hey.com",
		"proton.me",
		"proton mail",
		"icloud.com/mail",
		"superhuman",
		"mail.yahoo",
		"yahoo mail",
		"zoho mail",
	]

	public static func looksLikeWebMailWindow(title: String?) -> Bool {
		guard let title, !title.isEmpty else { return false }
		let lowered = title.lowercased()
		return titleSubstrings.contains { lowered.contains($0) }
	}
}
