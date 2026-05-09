//
//  MercuryTransformClient.swift
//  Hex
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import WarpCore

private let mercuryLogger = WarpLog.mercuryTransform

enum MercuryTransformError: Error, Equatable {
  case emptyAPIKey
  case httpError(statusCode: Int)
  case emptyChoices
  case emptyAssistantContent
  case decodingFailed
  case invalidResponseEncoding
}

enum MercuryTransformConstants {
  static let baseURL = URL(string: "https://api.inceptionlabs.ai/v1/chat/completions")!
  static let modelId = "mercury-2"
  static let defaultMaxTokens = 4096
  static let defaultTemperature = 0.3
  /// Mercury 2 supports `instant`, `low`, `medium`, `high` (see Inception API parameters). `instant` minimizes latency for voice/transcript cleanup.
  static let reasoningEffort = "instant"
}

private struct ChatCompletionRequest: Encodable {
  let model: String
  let messages: [ChatMessage]
  let maxTokens: Int
  let temperature: Double
  /// Maps to JSON `reasoning_effort` (Inception Instant mode for low-latency Mercury responses).
  let reasoningEffort: String

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case maxTokens = "max_tokens"
    case temperature
    case reasoningEffort = "reasoning_effort"
  }
}

private struct ChatMessage: Encodable {
  let role: String
  let content: String
}

private struct ChatCompletionResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      let content: String?
    }

    let message: Message
  }

  let choices: [Choice]
}

@DependencyClient
struct MercuryTransformClient {
  /// Sends the transcript to Inception Mercury 2. `additionalInstructions` is appended to the built-in base prompt when non-empty.
  var transform: @Sendable (
    _ transcript: String,
    _ additionalInstructions: String,
    _ apiKey: String
  ) async throws -> String
}

extension MercuryTransformClient {
  /// Base cleanup rules from `WarpSettings.defaultMercuryTransformInstructions`, plus optional user preferences.
  fileprivate static func systemPrompt(additionalInstructions: String) -> String {
    let base = WarpSettings.defaultMercuryTransformInstructions
    let extra = additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !extra.isEmpty else {
      return base
    }
    return base
      + "\n\n---\nStyle routing, preset rules, and optional user supplement (apply on top of the rules above):\n\n"
      + extra
  }
}

extension MercuryTransformClient: DependencyKey {
  static var liveValue: MercuryTransformClient {
    MercuryTransformClient { transcript, additionalInstructions, apiKey in
      guard !apiKey.isEmpty else {
        throw MercuryTransformError.emptyAPIKey
      }

      let systemContent = Self.systemPrompt(additionalInstructions: additionalInstructions)

      let messages = [
        ChatMessage(role: "system", content: systemContent),
        ChatMessage(
          role: "user",
          content: "Transcript to transform:\n\n\(transcript)"
        ),
      ]

      let body = ChatCompletionRequest(
        model: MercuryTransformConstants.modelId,
        messages: messages,
        maxTokens: MercuryTransformConstants.defaultMaxTokens,
        temperature: MercuryTransformConstants.defaultTemperature,
        reasoningEffort: MercuryTransformConstants.reasoningEffort
      )

      var request = URLRequest(url: MercuryTransformConstants.baseURL)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      request.httpBody = try JSONEncoder().encode(body)

      let (data, response) = try await URLSession.shared.data(for: request)

      guard let http = response as? HTTPURLResponse else {
        throw MercuryTransformError.httpError(statusCode: -1)
      }

      guard (200 ... 299).contains(http.statusCode) else {
        mercuryLogger.error("Mercury API HTTP status=\(http.statusCode)")
        throw MercuryTransformError.httpError(statusCode: http.statusCode)
      }

      let decoded: ChatCompletionResponse
      do {
        decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
      } catch {
        mercuryLogger.error("Mercury API decode failed: \(error.localizedDescription)")
        throw MercuryTransformError.decodingFailed
      }

      guard let first = decoded.choices.first else {
        throw MercuryTransformError.emptyChoices
      }

      guard let text = first.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
      else {
        throw MercuryTransformError.emptyAssistantContent
      }

      return text
    }
  }

  static var testValue: MercuryTransformClient {
    MercuryTransformClient { transcript, _, _ in
      transcript
    }
  }
}

extension DependencyValues {
  var mercuryTransform: MercuryTransformClient {
    get { self[MercuryTransformClient.self] }
    set { self[MercuryTransformClient.self] = newValue }
  }
}
