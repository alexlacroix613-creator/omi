import Foundation
import Security

enum ProviderSecretID: String, CaseIterable, Sendable {
  case byokOpenAI = "byok.openai"
  case byokAnthropic = "byok.anthropic"
  case byokGemini = "byok.gemini"
  case byokDeepgram = "byok.deepgram"
  case openRouter = "openrouter"

  var legacyDefaultsKey: String {
    switch self {
    case .byokOpenAI: return "dev_openai_api_key"
    case .byokAnthropic: return "dev_anthropic_api_key"
    case .byokGemini: return "dev_gemini_api_key"
    case .byokDeepgram: return "dev_deepgram_api_key"
    case .openRouter: return "dev_openrouter_api_key"
    }
  }
}

enum ProviderSecretStoreError: LocalizedError {
  case invalidValue
  case keychain(OSStatus)
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .invalidValue: return "The credential is empty."
    case .keychain(let status): return "Keychain operation failed (\(status))."
    case .verificationFailed: return "Keychain write verification failed."
    }
  }
}

/// Omi-owned provider credentials. Raw values never enter UserDefaults, logs,
/// or process arguments. The service is bundle-scoped so Companion and official
/// Omi cannot accidentally share provider credentials.
final class ProviderSecretStore: @unchecked Sendable {
  static let shared = ProviderSecretStore()

  private let service: String
  private let defaults: UserDefaults
  private let migrationFlag = "providerSecretMigration.v1.complete"

  init(
    service: String = "\(Bundle.main.bundleIdentifier ?? "com.omi.desktop").provider-secrets.v1",
    defaults: UserDefaults = .standard
  ) {
    self.service = service
    self.defaults = defaults
  }

  func read(_ id: ProviderSecretID) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    else { return nil }
    return normalized(value)
  }

  func save(_ value: String, for id: ProviderSecretID) throws {
    guard let normalized = normalized(value) else { throw ProviderSecretStoreError.invalidValue }
    let key: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.rawValue,
    ]
    let data = Data(normalized.utf8)
    let updateStatus = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var add = key
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(add as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw ProviderSecretStoreError.keychain(addStatus) }
    } else if updateStatus != errSecSuccess {
      throw ProviderSecretStoreError.keychain(updateStatus)
    }
    guard read(id) == normalized else { throw ProviderSecretStoreError.verificationFailed }
  }

  func delete(_ id: ProviderSecretID) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.rawValue,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ProviderSecretStoreError.keychain(status)
    }
  }

  /// Migrates legacy AppStorage only after a verified Keychain write. Failed
  /// entries remain in place so migration cannot destroy the user's key.
  func migrateLegacySecretsIfNeeded() {
    guard !defaults.bool(forKey: migrationFlag) else { return }
    var allMigrated = true
    for id in ProviderSecretID.allCases {
      guard let legacy = normalized(defaults.string(forKey: id.legacyDefaultsKey)) else { continue }
      do {
        try save(legacy, for: id)
        defaults.removeObject(forKey: id.legacyDefaultsKey)
      } catch {
        allMigrated = false
      }
    }
    if allMigrated { defaults.set(true, forKey: migrationFlag) }
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension ProviderSecretID {
  init(byok provider: BYOKProvider) {
    switch provider {
    case .openai: self = .byokOpenAI
    case .anthropic: self = .byokAnthropic
    case .gemini: self = .byokGemini
    case .deepgram: self = .byokDeepgram
    }
  }
}
