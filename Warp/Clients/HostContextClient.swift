//
//  HostContextClient.swift
//  Hex
//

import AppKit
import ApplicationServices
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import WarpCore

private let hostContextLogger = WarpLog.transcription

@DependencyClient
struct HostContextClient {
	/// Best-effort signal for routing webmail. When the frontmost app is a known browser, returns
	/// the focused window title (preferred) or the active tab URL when the title isn't exposed.
	/// All AX calls run with a tight timeout so this never blocks the recording-start path.
	var focusedBrowserWindowTitle: @Sendable () -> String = { "" }
}

extension HostContextClient: DependencyKey {
	static let liveValue: HostContextClient = HostContextClient(
		focusedBrowserWindowTitle: {
			MainActor.assumeIsolated {
				guard let app = NSWorkspace.shared.frontmostApplication,
				      let bundleID = app.bundleIdentifier,
				      StyleBrowserBundle.isBrowser(bundleID: bundleID)
				else {
					return ""
				}

				let appElement = AXUIElementCreateApplication(app.processIdentifier)
				// 0.4s ceiling per AX request — chrome- and webkit-derived browsers respond
				// in single-digit ms; Dia's wedged AX path will fail fast instead of hanging.
				AXUIElementSetMessagingTimeout(appElement, 0.4)

				guard let window = focusedWindow(of: appElement) else {
					return ""
				}

				if let title = title(of: window), !title.isEmpty {
					return title
				}

				if let url = webAreaURL(in: window), !url.isEmpty {
					hostContextLogger.notice(
						"AX title empty; AXWebArea URL fallback succeeded for \(bundleID, privacy: .public)"
					)
					return url
				}

				hostContextLogger.notice(
					"No AX title and no AXWebArea URL for \(bundleID, privacy: .public)"
				)
				return ""
			}
		}
	)

	static let testValue = HostContextClient(focusedBrowserWindowTitle: { "" })

	static let previewValue = Self.testValue
}

extension DependencyValues {
	var hostContext: HostContextClient {
		get { self[HostContextClient.self] }
		set { self[HostContextClient.self] = newValue }
	}
}

private func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
	var ref: CFTypeRef?
	let result = AXUIElementCopyAttributeValue(
		appElement,
		kAXFocusedWindowAttribute as CFString,
		&ref
	)
	guard result == .success, let ref else { return nil }
	return (ref as! AXUIElement)
}

private func title(of element: AXUIElement) -> String? {
	var ref: CFTypeRef?
	let result = AXUIElementCopyAttributeValue(
		element,
		kAXTitleAttribute as CFString,
		&ref
	)
	guard result == .success else { return nil }
	return ref as? String
}

/// Walks the focused window's AX subtree to find the `AXWebArea` element and read its
/// `AXURL` attribute. Bounded depth and node count so a misbehaving browser can't stall us.
private func webAreaURL(in window: AXUIElement) -> String? {
	var scanned = 0
	return findWebAreaURL(in: window, depth: 0, scanned: &scanned)
}

private let webAreaSearchMaxDepth = 10
private let webAreaSearchMaxNodes = 400

private func findWebAreaURL(in element: AXUIElement, depth: Int, scanned: inout Int) -> String? {
	if scanned >= webAreaSearchMaxNodes || depth > webAreaSearchMaxDepth { return nil }
	scanned += 1

	var roleRef: CFTypeRef?
	if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
	   let role = roleRef as? String,
	   role == "AXWebArea"
	{
		var urlRef: CFTypeRef?
		if AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlRef) == .success,
		   let urlRef
		{
			if let url = urlRef as? URL { return url.absoluteString }
			if let urlString = urlRef as? String { return urlString }
		}
	}

	var childrenRef: CFTypeRef?
	guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
	      let children = childrenRef as? [AXUIElement]
	else {
		return nil
	}

	for child in children {
		if let url = findWebAreaURL(in: child, depth: depth + 1, scanned: &scanned) {
			return url
		}
	}
	return nil
}
