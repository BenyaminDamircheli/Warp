import AppKit
import ComposableArchitecture
import Inject
import SwiftUI
import WarpCore

struct StyleView: View {
  @ObserveInjection var inject
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var selectedContext: StyleMessageContext = .personal

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        MercuryTransformSectionView(store: store)

        GroupBox {
          VStack(alignment: .leading, spacing: 18) {
            contextPicker

            VStack(alignment: .leading, spacing: 10) {
              Text(String(localized: "style.linkedApps.title", bundle: .main))
                .font(.subheadline.weight(.semibold))

              let rawBundleIDs = store.warpSettings.styleBucket(for: selectedContext).linkedBundleIDs
              let visibleBundleIDs = Self.installedBundleIDs(from: rawBundleIDs)

              FlowLayout(spacing: 8) {
                ForEach(visibleBundleIDs, id: \.self) { bundleID in
                  AppChip(bundleID: bundleID) {
                    store.send(.removeStyleLinkedBundle(selectedContext, bundleID))
                  }
                }

                AddLinkedAppChip(title: String(localized: "style.addApp.button", bundle: .main)) {
                  store.send(.pickStyleLinkedApplications(selectedContext))
                }
                .help(String(localized: "style.addApp.help", bundle: .main))
              }

              Text(String(localized: "style.linkedApps.caption", bundle: .main))
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            presetCards
          }
          .padding(.vertical, 4)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "style.formatting.sectionTitle", bundle: .main))
              .font(.headline)
            Text(String(localized: "style.formatting.sectionSubtitle", bundle: .main))
              .settingsCaption()
          }
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task {
      await store.send(.loadInceptionAPIKeyPresence).finish()
    }
    .enableInjection()
  }

  // MARK: - Context picker (segmented)

  private var contextPicker: some View {
    Picker("Context", selection: $selectedContext) {
      ForEach(StyleMessageContext.allCases, id: \.self) { context in
        Text(tabLabel(for: context)).tag(context)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }

  // MARK: - Preset cards

  private var presetCards: some View {
    let selectedSlot = store.warpSettings.styleBucket(for: selectedContext).selectedPresetSlot

    return HStack(alignment: .top, spacing: 12) {
      ForEach(StylePresetSlot.allCases, id: \.self) { slot in
        PresetCard(
          slot: slot,
          title: presetTitle(slot),
          subtitle: presetSubtitle(slot),
          diffCaption: presetDiff(slot),
          preview: previewLines(for: selectedContext, slot: slot),
          isSelected: selectedSlot == slot,
          showEmailLayout: selectedContext == .email
        ) {
          store.send(.setStylePreset(selectedContext, slot))
        }
      }
    }
  }

  // MARK: - Helpers

  private func tabLabel(for context: StyleMessageContext) -> String {
    switch context {
    case .personal: String(localized: "style.tab.personal", bundle: .main)
    case .work: String(localized: "style.tab.work", bundle: .main)
    case .email: String(localized: "style.tab.email", bundle: .main)
    case .other: String(localized: "style.tab.other", bundle: .main)
    }
  }

  private func presetTitle(_ slot: StylePresetSlot) -> String {
    switch slot {
    case .formal: String(localized: "style.preset.formal.title", bundle: .main)
    case .casual: String(localized: "style.preset.casual.title", bundle: .main)
    case .expressive:
      selectedContext == .personal
        ? String(localized: "style.preset.expressive.personal.title", bundle: .main)
        : String(localized: "style.preset.expressive.default.title", bundle: .main)
    }
  }

  private func presetSubtitle(_ slot: StylePresetSlot) -> String {
    switch slot {
    case .formal: String(localized: "style.preset.subtitle.formal", bundle: .main)
    case .casual: String(localized: "style.preset.subtitle.casual", bundle: .main)
    case .expressive:
      selectedContext == .personal
        ? String(localized: "style.preset.subtitle.expressive.personal", bundle: .main)
        : String(localized: "style.preset.subtitle.expressive.default", bundle: .main)
    }
  }

  private func presetDiff(_ slot: StylePresetSlot) -> String {
    switch slot {
    case .formal: String(localized: "style.preset.diff.formal", bundle: .main)
    case .casual: String(localized: "style.preset.diff.casual", bundle: .main)
    case .expressive:
      selectedContext == .personal
        ? String(localized: "style.preset.diff.expressive.personal", bundle: .main)
        : String(localized: "style.preset.diff.expressive.standard", bundle: .main)
    }
  }

  private func previewLocalizationKey(_ context: StyleMessageContext, slot: StylePresetSlot) -> String {
    switch (context, slot) {
    case (.personal, .formal): "style.preview.personal.formal"
    case (.personal, .casual): "style.preview.personal.casual"
    case (.personal, .expressive): "style.preview.personal.expressive"
    case (.work, .formal): "style.preview.work.formal"
    case (.work, .casual): "style.preview.work.casual"
    case (.work, .expressive): "style.preview.work.expressive"
    case (.email, .formal): "style.preview.email.formal"
    case (.email, .casual): "style.preview.email.casual"
    case (.email, .expressive): "style.preview.email.expressive"
    case (.other, .formal): "style.preview.other.formal"
    case (.other, .casual): "style.preview.other.casual"
    case (.other, .expressive): "style.preview.other.expressive"
    }
  }

  private func previewLines(for context: StyleMessageContext, slot: StylePresetSlot) -> [String] {
    let key = previewLocalizationKey(context, slot: slot)
    return String(localized: String.LocalizationValue(key), bundle: .main)
      .components(separatedBy: "\n")
  }

  /// Preset defaults include many bundle IDs; only surface chips for apps that are actually installed.
  /// Routing still uses the full list so linking resumes when an app is installed later.
  private static func installedBundleIDs(from ids: [String]) -> [String] {
    ids.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
  }
}

// MARK: - Add app chip (matches `AppChip` sizing)

private struct AddLinkedAppChip: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 18, height: 18)

        Text(title)
          .font(.caption)
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - App chip

private struct AppChip: View {
  let bundleID: String
  var onRemove: () -> Void

  var body: some View {
    Button(action: onRemove) {
      HStack(spacing: 6) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
          Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 18)
        } else {
          Image(systemName: "app.dashed")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
          Text(url.deletingPathExtension().lastPathComponent)
            .font(.caption)
            .lineLimit(1)
        }

        Image(systemName: "xmark")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .help(bundleID)
  }
}

// MARK: - Preset card

private struct PresetCard: View {
  let slot: StylePresetSlot
  let title: String
  let subtitle: String
  let diffCaption: String
  let preview: [String]
  let isSelected: Bool
  let showEmailLayout: Bool
  let onSelect: () -> Void

  private var slotIconName: String {
    switch slot {
    case .formal: "text.alignleft"
    case .casual: "text.quote"
    case .expressive: "bubble.left.fill"
    }
  }

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Image(systemName: slotIconName)
            .font(.body.weight(.semibold))
            .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : .secondary)
            .frame(width: 24, alignment: .center)
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.headline)
            Text(subtitle)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }

        Text(diffCaption)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)

        Divider()
          .opacity(0.45)

        inlinePreview
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            isSelected
              ? Color(nsColor: .controlAccentColor).opacity(0.1)
              : Color(nsColor: .controlBackgroundColor)
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            isSelected ? Color(nsColor: .controlAccentColor).opacity(0.85) : Color.secondary.opacity(0.22),
            lineWidth: isSelected ? 2 : 1
          )
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  /// Plain preview lines—no nested “bubble” or letter chrome so it reads as part of the card.
  @ViewBuilder
  private var inlinePreview: some View {
    VStack(alignment: .leading, spacing: 6) {
      if showEmailLayout {
        Text(String(localized: "style.email.toLine", bundle: .main))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
      }

      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(preview.enumerated()), id: \.offset) { _, line in
          if line.isEmpty {
            Spacer().frame(height: 6)
          } else {
            Text(line)
              .font(.callout)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }
}

// MARK: - Simple flow layout for chips

private struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = arrange(proposal: proposal, subviews: subviews)
    return result.size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = arrange(proposal: proposal, subviews: subviews)
    for (index, subview) in subviews.enumerated() {
      guard index < result.origins.count else { break }
      let origin = CGPoint(
        x: bounds.minX + result.origins[index].x,
        y: bounds.minY + result.origins[index].y
      )
      subview.place(at: origin, proposal: .unspecified)
    }
  }

  private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
    let maxWidth = proposal.width ?? .infinity
    var origins: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      origins.append(CGPoint(x: x, y: y))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      maxX = max(maxX, x - spacing)
    }

    return (origins, CGSize(width: maxX, height: y + rowHeight))
  }
}
