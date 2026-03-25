import AppKit
import ComposableArchitecture
import Inject
import SwiftUI

private let inceptionDocsURL = URL(string: "https://docs.inceptionlabs.ai/get-started/get-started")!

/// Inception Mercury post-processing UI on the Transforms screen.
struct MercuryTransformSectionView: View {
  @ObserveInjection var inject
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var apiKeyDraft = ""

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Toggle(
            String(localized: "mercury.toggle", bundle: .main),
            isOn: $store.warpSettings.mercuryTransformEnabled
          )
          .toggleStyle(.checkbox)

          Text(String(localized: "mercury.toggle.caption", bundle: .main))
            .settingsCaption()
        }

        VStack(alignment: .leading, spacing: 8) {
          Text(String(localized: "mercury.instructions.label", bundle: .main))
            .font(.subheadline.weight(.semibold))
          TextEditor(text: $store.warpSettings.mercuryTransformInstructions)
            .font(.body)
            .frame(minHeight: 88, maxHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
          Text(String(localized: "mercury.instructions.caption", bundle: .main))
            .settingsCaption()
        }
        .padding(.vertical, 2)

        VStack(alignment: .leading, spacing: 10) {
          Text(String(localized: "mercury.apiKey.label", bundle: .main))
            .font(.subheadline.weight(.semibold))

          if store.hasInceptionAPIKey {
            savedKeyStatusCard
          }

          SecureField(
            String(localized: "mercury.apiKey.placeholder", bundle: .main),
            text: $apiKeyDraft
          )
          .textFieldStyle(.roundedBorder)

          HStack(spacing: 12) {
            Button(String(localized: "mercury.apiKey.save", bundle: .main)) {
              Task {
                await store.send(.saveInceptionAPIKey(apiKeyDraft)).finish()
                apiKeyDraft = ""
              }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(String(localized: "mercury.apiKey.openDocs", bundle: .main)) {
              NSWorkspace.shared.open(inceptionDocsURL)
            }

            Spacer()
          }

          Text(String(localized: "mercury.privacy", bundle: .main))
            .settingsCaption()
        }
        .padding(.vertical, 2)
      }
      .padding(.vertical, 4)
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(String(localized: "mercury.section.title", bundle: .main))
          .font(.headline)
        Text(String(localized: "mercury.section.subtitle", bundle: .main))
          .settingsCaption()
      }
    }
    .task {
      await store.send(.loadInceptionAPIKeyPresence).finish()
    }
    .enableInjection()
  }

  private var savedKeyStatusCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "checkmark.circle.fill")
          .font(.title2)
          .foregroundStyle(.green)
          .symbolRenderingMode(.hierarchical)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 4) {
          Text(String(localized: "mercury.apiKey.status.title", bundle: .main))
            .font(.subheadline.weight(.semibold))
          Text(String(localized: "mercury.apiKey.status.detail", bundle: .main))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      RemoveSavedAPIKeyButton(title: String(localized: "mercury.apiKey.removeFromMac", bundle: .main)) {
        Task {
          await store.send(.clearInceptionAPIKey).finish()
          apiKeyDraft = ""
        }
      }
      .padding(.leading, 34)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
    )
  }
}

// MARK: - Remove key button

private struct RemoveSavedAPIKeyButton: View {
  let title: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: "key.slash")
        .font(.system(.caption, design: .default, weight: .medium))
        .labelStyle(.titleAndIcon)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fillColor)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(RemoveKeyButtonPressStyle())
    .onHover { isHovered = $0 }
  }

  private var foregroundColor: Color {
    if isHovered {
      return Color(nsColor: .labelColor)
    }
    return Color(nsColor: .secondaryLabelColor)
  }

  private var fillColor: Color {
    if isHovered {
      return Color(nsColor: .quaternarySystemFill)
    }
    return Color(nsColor: .tertiarySystemFill)
  }

  private var borderColor: Color {
    if isHovered {
      return Color(nsColor: .separatorColor)
    }
    return Color(nsColor: .separatorColor).opacity(0.55)
  }
}

private struct RemoveKeyButtonPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.88 : 1)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
