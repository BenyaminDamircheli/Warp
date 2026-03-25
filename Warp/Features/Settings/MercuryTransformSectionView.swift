import ComposableArchitecture
import WarpCore
import Inject
import SwiftUI

private let inceptionDocsURL = URL(string: "https://docs.inceptionlabs.ai/get-started/get-started")!

struct MercuryTransformSectionView: View {
  @ObserveInjection var inject
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var apiKeyDraft = ""

  var body: some View {
    Section {
      Label {
        Toggle(
          String(localized: "mercury.toggle", bundle: .main),
          isOn: $store.warpSettings.mercuryTransformEnabled
        )
        Text(String(localized: "mercury.toggle.caption", bundle: .main))
          .settingsCaption()
      } icon: {
        Image(systemName: "wand.and.stars")
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
      .padding(.vertical, 4)

      VStack(alignment: .leading, spacing: 8) {
        Text(String(localized: "mercury.apiKey.label", bundle: .main))
          .font(.subheadline.weight(.semibold))
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

          Button(String(localized: "mercury.apiKey.clear", bundle: .main), role: .destructive) {
            Task {
              await store.send(.clearInceptionAPIKey).finish()
              apiKeyDraft = ""
            }
          }
          .disabled(!store.hasInceptionAPIKey)

          Spacer()

          Button(String(localized: "mercury.apiKey.openDocs", bundle: .main)) {
            NSWorkspace.shared.open(inceptionDocsURL)
          }
        }

        if store.hasInceptionAPIKey {
          Text(String(localized: "mercury.apiKey.saved", bundle: .main))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(String(localized: "mercury.privacy", bundle: .main))
          .settingsCaption()
      }
      .padding(.vertical, 4)
    } header: {
      Text(String(localized: "mercury.section.title", bundle: .main))
    }
    .task {
      await store.send(.loadInceptionAPIKeyPresence).finish()
    }
    .enableInjection()
  }
}
