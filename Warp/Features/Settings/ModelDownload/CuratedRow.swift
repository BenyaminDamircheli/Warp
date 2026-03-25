import ComposableArchitecture
import Darwin
import Inject
import SwiftUI

/// Clickable info control that presents streaming-model copy in a material popover (system tooltip-style chrome).
private struct StreamingModelInfoControl: View {
	let helpText: String
	@State private var isPresented = false

	var body: some View {
		Button {
			isPresented.toggle()
		} label: {
			Image(systemName: "info.circle")
				.font(.body)
				.imageScale(.small)
				.foregroundStyle(.secondary)
				.contentShape(.rect)
				.padding(2)
		}
		.buttonStyle(.plain)
		.accessibilityLabel("About streaming transcription")
		.help("Click for details about this streaming model")
		.popover(isPresented: $isPresented, arrowEdge: .top) {
			Text(helpText)
				.font(.callout)
				.foregroundStyle(.primary)
				.multilineTextAlignment(.leading)
				.fixedSize(horizontal: false, vertical: true)
				.frame(minWidth: 240, maxWidth: 300)
				.padding(12)
				.presentationBackground(.regularMaterial)
		}
	}
}

struct CuratedRow: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<ModelDownloadFeature>
	let model: CuratedModelInfo

	var isSelected: Bool {
		let selected = store.warpSettings.selectedModel
		if model.internalName.contains("*") || model.internalName.contains("?") {
			return fnmatch(model.internalName, selected, 0) == 0
		}
		// Also consider the inverse: selected may be a concrete name while the curated item is a prefix-like value
		if selected.contains("*") || selected.contains("?") {
			return fnmatch(selected, model.internalName, 0) == 0
		}
		return model.internalName == selected
	}

	var body: some View {
		Button(action: { store.send(.selectModel(model.internalName)) }) {
			HStack(alignment: .center, spacing: 12) {
				// Radio selector
				Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
					.foregroundStyle(isSelected ? .blue : .secondary)

				// Title and ratings
				VStack(alignment: .leading, spacing: 6) {
					HStack(alignment: .firstTextBaseline, spacing: 6) {
						Text(model.displayName)
							.font(.headline)
							.lineLimit(1)
							.truncationMode(.tail)
							.layoutPriority(-1)
						if let badge = model.badge {
							Text(badge)
								.font(.caption2)
								.fontWeight(.semibold)
								.foregroundStyle(.white)
								.padding(.horizontal, 6)
								.padding(.vertical, 2)
								.background(Color.accentColor)
								.clipShape(RoundedRectangle(cornerRadius: 4))
								.fixedSize(horizontal: true, vertical: false)
						}
						if let streamingHelp = model.streamingModelHelpText {
							StreamingModelInfoControl(helpText: streamingHelp)
								.fixedSize()
						}
					}
					HStack(spacing: 16) {
						HStack(spacing: 6) {
							StarRatingView(model.accuracyStars)
							Text("Accuracy").font(.caption2).foregroundStyle(.secondary)
						}
						HStack(spacing: 6) {
							StarRatingView(model.speedStars)
							Text("Speed").font(.caption2).foregroundStyle(.secondary)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)

				Spacer(minLength: 12)

				// Trailing size and action/progress icons, aligned to the right
				HStack(spacing: 12) {
					Text(model.storageSize)
						.foregroundStyle(.secondary)
						.font(.subheadline)
						.frame(width: 72, alignment: .trailing)

					// Download/Progress/Downloaded at far right
					ZStack {
						if store.isDownloading, store.downloadingModelName == model.internalName {
							ProgressView(value: store.downloadProgress)
								.progressViewStyle(.circular)
								.controlSize(.small)
								.tint(.blue)
								.frame(width: 24, height: 24)
								.help("Downloading… \(Int(store.downloadProgress * 100))%")
						} else if model.isDownloaded {
							Image(systemName: "checkmark.circle.fill")
								.foregroundStyle(.green)
								.frame(width: 24, height: 24)
								.help("Downloaded")
						} else {
							Button {
								store.send(.selectModel(model.internalName))
								store.send(.downloadSelectedModel)
							} label: {
								Image(systemName: "arrow.down.circle")
							}
							.buttonStyle(.borderless)
							.help("Download")
							.frame(width: 24, height: 24)
						}
					}
				}
			}
			.padding(10)
			.background(
				RoundedRectangle(cornerRadius: 10)
					.fill(isSelected ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 10)
					.stroke(isSelected ? Color.blue.opacity(0.35) : Color.gray.opacity(0.18))
			)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		// Keep context menu as an alternative path
		.contextMenu {
			if store.isDownloading, store.downloadingModelName == model.internalName {
				Button("Cancel Download", role: .destructive) { store.send(.cancelDownload) }
			}
			if model.isDownloaded || (store.isDownloading && store.downloadingModelName == model.internalName) {
				Button("Show in Finder") { store.send(.openModelLocation) }
			}
			if model.isDownloaded {
				Divider()
				Button("Delete", role: .destructive) {
					store.send(.selectModel(model.internalName))
					store.send(.deleteSelectedModel)
				}
			}
		}
		.enableInjection()
	}
}
