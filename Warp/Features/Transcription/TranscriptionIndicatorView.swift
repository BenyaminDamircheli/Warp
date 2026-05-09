import Inject
import Pow
import SwiftUI

struct TranscriptionIndicatorView: View {
  @ObserveInjection var inject

  enum Status: Equatable {
    case hidden
    case recording
    case transcribing
    case prewarming
  }

  var status: Status
  var meter: Meter
  var appName: String? = nil
  var appIcon: NSImage? = nil
  var presetLabel: String? = nil

  private let pillHeight: CGFloat = 24

  private var normalizedAvg: Double {
    min(1, meter.averagePower * 3)
  }

  private var normalizedPeak: Double {
    min(1, meter.peakPower * 3)
  }

  private var isRecording: Bool {
    status == .recording
  }

  private var isTranscribingOrPrewarming: Bool {
    status == .transcribing || status == .prewarming
  }

  var body: some View {
    indicator
      .overlay(alignment: .top) {
        if status == .prewarming {
          prewarmingTooltip
            .offset(y: -34)
        }
      }
      .animation(.interactiveSpring(duration: 0.15), value: meter)
      .opacity(status == .hidden ? 0 : 1)
      .scaleEffect(status == .hidden ? 0.6 : 1)
      .blur(radius: status == .hidden ? 4 : 0)
      .animation(.spring(duration: 0.4, bounce: 0.18), value: status)
      .changeEffect(.glow(color: .white.opacity(0.35), radius: 10), value: status)
      .compositingGroup()
      .enableInjection()
  }

  // MARK: - Pill

  private var indicator: some View {
    HStack(spacing: 7) {
      if let appIcon, isRecording {
        Image(nsImage: appIcon)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(width: 14, height: 14)
          .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
          .transition(.blurReplace)
      }

      if let appName, !appName.isEmpty, isRecording {
        Text(appName)
          .font(.system(size: 11.5, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
          .transition(.blurReplace)
      }

      if let presetLabel, !presetLabel.isEmpty, isRecording {
        separator

        Text(presetLabel)
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.55))
          .lineLimit(1)
          .transition(.blurReplace)
      }

      if isRecording {
        recordingAudioBars
          .padding(.leading, 2)
          .transition(.blurReplace)
      }

      if isTranscribingOrPrewarming {
        transcribingDots
          .transition(.blurReplace)
      }
    }
    .padding(.horizontal, horizontalPadding)
    .frame(minWidth: pillHeight, minHeight: pillHeight)
    .background(pillBackground)
    .overlay(pillStroke)
    .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
    .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
    .shadow(
      color: .white.opacity(isRecording ? normalizedAvg * 0.18 : 0),
      radius: 10 + normalizedPeak * 8
    )
    .fixedSize()
  }

  private var horizontalPadding: CGFloat {
    if isRecording { return 10 }
    if isTranscribingOrPrewarming { return 10 }
    return 0
  }

  // MARK: - Background & Stroke

  private var pillBackground: some View {
    Capsule(style: .continuous)
      .fill(Color(white: 0.04).opacity(0.92))
      .background {
        Capsule(style: .continuous)
          .fill(.ultraThinMaterial)
      }
      .overlay {
        Capsule(style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .blendMode(.plusLighter)
      }
  }

  private var pillStroke: some View {
    Capsule(style: .continuous)
      .strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(0.22),
            Color.white.opacity(0.06)
          ],
          startPoint: .top,
          endPoint: .bottom
        ),
        lineWidth: 0.6
      )
  }

  // MARK: - Separator

  private var separator: some View {
    Circle()
      .fill(Color.white.opacity(0.28))
      .frame(width: 2.5, height: 2.5)
      .transition(.opacity)
  }

  // MARK: - Audio Bars

  private var recordingAudioBars: some View {
    HStack(alignment: .center, spacing: 2.5) {
      ForEach(0 ..< 4, id: \.self) { index in
        recordingAudioBar(index: index)
      }
    }
    .frame(height: 12)
    .accessibilityLabel(String(localized: "Recording level"))
  }

  private func recordingAudioBar(index: Int) -> some View {
    let spread = Double(index) / 3.0
    let stagger = 0.4 + spread * 0.6
    let level = min(1, normalizedAvg * stagger * 1.2 + normalizedPeak * (0.2 + spread * 0.3))
    let minH: CGFloat = 2.5
    let maxH: CGFloat = 11
    let height = minH + CGFloat(level) * (maxH - minH)

    return RoundedRectangle(cornerRadius: 1, style: .continuous)
      .fill(Color.white)
      .frame(width: 2, height: height)
      .opacity(0.45 + level * 0.55)
  }

  // MARK: - Transcribing Dots

  private var transcribingDots: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let t = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: 3) {
        ForEach(0 ..< 3, id: \.self) { i in
          let phase = t * 2.6 + Double(i) * 0.55
          let wave = (sin(phase) + 1) / 2
          Circle()
            .fill(Color.white)
            .frame(width: 4, height: 4)
            .opacity(0.35 + wave * 0.6)
            .scaleEffect(0.85 + wave * 0.3)
        }
      }
      .frame(height: 12)
    }
    .accessibilityLabel(String(localized: "Transcribing"))
  }

  // MARK: - Prewarming Tooltip

  private var prewarmingTooltip: some View {
    Text("Model prewarming…")
      .font(.system(size: 10.5, weight: .medium, design: .rounded))
      .foregroundStyle(.white.opacity(0.85))
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background {
        Capsule(style: .continuous)
          .fill(Color(white: 0.04).opacity(0.92))
          .background {
            Capsule(style: .continuous)
              .fill(.ultraThinMaterial)
          }
      }
      .overlay {
        Capsule(style: .continuous)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
      }
      .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
      .transition(.blurReplace)
  }
}

#Preview("Indicator") {
  VStack(spacing: 24) {
    TranscriptionIndicatorView(
      status: .hidden,
      meter: .init(averagePower: 0, peakPower: 0)
    )
    TranscriptionIndicatorView(
      status: .recording,
      meter: .init(averagePower: 0.3, peakPower: 0.4),
      appName: "Slack",
      appIcon: NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app"),
      presetLabel: "Formal"
    )
    TranscriptionIndicatorView(
      status: .recording,
      meter: .init(averagePower: 0.8, peakPower: 0.9),
      appName: "Notes",
      appIcon: NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")
    )
    TranscriptionIndicatorView(
      status: .transcribing,
      meter: .init(averagePower: 0, peakPower: 0)
    )
    TranscriptionIndicatorView(
      status: .prewarming,
      meter: .init(averagePower: 0, peakPower: 0)
    )
  }
  .padding(60)
  .background(
    LinearGradient(
      colors: [Color(white: 0.95), Color(white: 0.6)],
      startPoint: .top,
      endPoint: .bottom
    )
  )
}
