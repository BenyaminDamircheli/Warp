//
//  InceptionAPIKeyClient.swift
//  Hex
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import Security

enum InceptionAPIKeyStore {
  private static let service = "com.benyamindamircheli.warp.inception"
  private static let account = "apiKey"

  enum StoreError: Error, Equatable {
    case keychainFailure(OSStatus)
    case invalidUTF8
  }

  static func load() throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw StoreError.keychainFailure(status)
    }
    guard let data = result as? Data else {
      throw StoreError.keychainFailure(errSecInternalError)
    }
    guard let string = String(data: data, encoding: .utf8) else {
      throw StoreError.invalidUTF8
    }
    return string
  }

  static func save(_ key: String) throws {
    let data = Data(key.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status == errSecSuccess {
      let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      guard updateStatus == errSecSuccess else {
        throw StoreError.keychainFailure(updateStatus)
      }
    } else if status == errSecItemNotFound {
      var combined = query
      combined[kSecValueData as String] = data
      let addStatus = SecItemAdd(combined as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw StoreError.keychainFailure(addStatus)
      }
    } else {
      throw StoreError.keychainFailure(status)
    }
  }

  static func delete() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw StoreError.keychainFailure(status)
    }
  }
}

@DependencyClient
struct InceptionAPIKeyClient {
  var load: @Sendable () async throws -> String?
  var save: @Sendable (String) async throws -> Void
  var delete: @Sendable () async throws -> Void
}

extension InceptionAPIKeyClient: DependencyKey {
  static var liveValue: InceptionAPIKeyClient {
    InceptionAPIKeyClient(
      load: {
        try InceptionAPIKeyStore.load()
      },
      save: { key in
        try InceptionAPIKeyStore.save(key)
      },
      delete: {
        try InceptionAPIKeyStore.delete()
      }
    )
  }

  static var testValue: InceptionAPIKeyClient {
    InceptionAPIKeyClient(
      load: { nil },
      save: { _ in },
      delete: {}
    )
  }
}

extension DependencyValues {
  var inceptionAPIKey: InceptionAPIKeyClient {
    get { self[InceptionAPIKeyClient.self] }
    set { self[InceptionAPIKeyClient.self] = newValue }
  }
}
