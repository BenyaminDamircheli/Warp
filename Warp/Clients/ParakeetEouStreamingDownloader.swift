import Foundation
import WarpCore

#if canImport(FluidAudio)
import FluidAudio

/// Downloads Parakeet EOU assets for `StreamingEouAsrManager`.
///
/// FluidAudio's `ModelNames.ParakeetEOU` lists `tokenizer.model` and `parakeet_eou_preprocessor.mlmodelc`,
/// which are not present for the current Hugging Face `160ms` layout and cause
/// `DownloadUtils.downloadRepo` to fail verification after a successful download.
/// This helper mirrors `DownloadUtils.downloadRepo` but only requires bundles that
/// `StreamingEouAsrManager.loadModels(modelDir:)` actually loads.
enum ParakeetEouStreamingDownloader {
  private static let eouLogger = WarpLog.models

  /// Top-level names inside the cache folder (`parakeet-eou-streaming/160ms/`).
  private static let requiredModelsForStreamingLoad: Set<String> = [
    "streaming_encoder.mlmodelc",
    "decoder.mlmodelc",
    "joint_decision.mlmodelc",
    "vocab.json",
  ]

  private static func authorizedHFRequest(url: URL) -> URLRequest {
    var request = URLRequest(url: url, timeoutInterval: 1800)
    if let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
      ?? ProcessInfo.processInfo.environment["HUGGING_FACE_HUB_TOKEN"]
      ?? ProcessInfo.processInfo.environment["HUGGINGFACEHUB_API_TOKEN"]
    {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  /// Same destination layout as `DownloadUtils.downloadRepo(.parakeetEou160, to: fluidAudioModelsDirectory)`.
  static func download160msIfMissing(fluidAudioModelsDirectory: URL) async throws {
    let repo = Repo.parakeetEou160
    eouLogger.notice("Parakeet EOU 160ms: downloading if missing under \(repo.folderName)…")

    let repoPath = fluidAudioModelsDirectory.appendingPathComponent(repo.folderName)
    try FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)

    let present = requiredModelsForStreamingLoad.allSatisfy { name in
      FileManager.default.fileExists(atPath: repoPath.appendingPathComponent(name).path)
    }
    if present {
      eouLogger.debug("Parakeet EOU 160ms already present at \(repoPath.path)")
      return
    }

    let requiredModels = requiredModelsForStreamingLoad
    guard let subPath = repo.subPath else {
      throw DownloadUtils.HuggingFaceDownloadError.invalidResponse
    }

    var patterns: [String] = []
    for model in requiredModels {
      patterns.append("\(subPath)/\(model)/")
    }

    var filesToDownload: [String] = []

    func listDirectory(path: String) async throws {
      let apiPath = path.isEmpty ? "tree/main" : "tree/main/\(path)"
      let dirURL = try ModelRegistry.apiModels(repo.remotePath, apiPath)
      let (dirData, response) = try await DownloadUtils.sharedSession.data(for: authorizedHFRequest(url: dirURL))

      if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
          throw DownloadUtils.HuggingFaceDownloadError.rateLimited(
            statusCode: httpResponse.statusCode,
            message: "Rate limited while listing files"
          )
        }
      }

      guard let items = try JSONSerialization.jsonObject(with: dirData) as? [[String: Any]] else {
        return
      }

      for item in items {
        guard let itemPath = item["path"] as? String,
              let itemType = item["type"] as? String
        else { continue }

        if itemType == "directory" {
          let shouldProcess: Bool
          shouldProcess =
            itemPath == subPath || itemPath.hasPrefix("\(subPath)/")
            || patterns.contains { itemPath.hasPrefix($0) || $0.hasPrefix(itemPath + "/") }
          if shouldProcess {
            try await listDirectory(path: itemPath)
          }
        } else if itemType == "file" {
          let isInSubPath = itemPath.hasPrefix("\(subPath)/")
          let matchesPattern = patterns.contains { itemPath.hasPrefix($0) }
          let isMetadata = itemPath.hasSuffix(".json") || itemPath.hasSuffix(".model")
          let shouldInclude = isInSubPath && (matchesPattern || isMetadata)
          if shouldInclude {
            filesToDownload.append(itemPath)
          }
        }
      }
    }

    try await listDirectory(path: subPath)
    eouLogger.info("Parakeet EOU 160ms: \(filesToDownload.count) files to fetch")

    for (index, filePath) in filesToDownload.enumerated() {
      var localPath = filePath
      if filePath.hasPrefix("\(subPath)/") {
        localPath = String(filePath.dropFirst(subPath.count + 1))
      }
      let destPath = repoPath.appendingPathComponent(localPath)

      if FileManager.default.fileExists(atPath: destPath.path) {
        continue
      }

      try FileManager.default.createDirectory(
        at: destPath.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )

      let encodedFilePath = filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath
      let fileURL = try ModelRegistry.resolveModel(repo.remotePath, encodedFilePath)
      let (tempFileURL, response) = try await DownloadUtils.sharedSession.download(for: authorizedHFRequest(url: fileURL))

      guard let httpResponse = response as? HTTPURLResponse else {
        throw DownloadUtils.HuggingFaceDownloadError.invalidResponse
      }

      if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
        throw DownloadUtils.HuggingFaceDownloadError.rateLimited(
          statusCode: httpResponse.statusCode,
          message: "Rate limited while downloading \(filePath)"
        )
      }

      guard (200 ..< 300).contains(httpResponse.statusCode) else {
        throw DownloadUtils.HuggingFaceDownloadError.downloadFailed(
          path: filePath,
          underlying: NSError(domain: "HTTP", code: httpResponse.statusCode)
        )
      }

      try FileManager.default.moveItem(at: tempFileURL, to: destPath)

      if (index + 1) % 10 == 0 || index == filesToDownload.count - 1 {
        eouLogger.info("Parakeet EOU 160ms: downloaded \(index + 1)/\(filesToDownload.count) files")
      }
    }

    for model in requiredModels {
      let modelPath = repoPath.appendingPathComponent(model)
      guard FileManager.default.fileExists(atPath: modelPath.path) else {
        throw DownloadUtils.HuggingFaceDownloadError.modelNotFound(path: model)
      }
    }

    eouLogger.notice("Parakeet EOU 160ms download complete at \(repoPath.path)")
  }
}

#endif
