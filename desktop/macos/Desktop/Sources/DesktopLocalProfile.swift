import Foundation

/// Runtime switches for the harness-owned Omi Dev local profile.
///
/// Production keeps its existing storage root. The permanent Companion bundle
/// has an explicit, stable root so it can never open or migrate the official
/// app's database. The local harness can still override its root with
/// ``OMI_LOCAL_PROFILE_STORAGE_NAME``.
enum DesktopLocalProfile {
  static var isEnabled: Bool {
    value("OMI_DESKTOP_LOCAL_PROFILE") == "1"
  }

  static var storageDirectoryName: String {
    if isEnabled {
      return nonEmpty(value("OMI_LOCAL_PROFILE_STORAGE_NAME")) ?? "Omi"
    }
    return storageDirectoryName(bundleIdentifier: Bundle.main.bundleIdentifier)
  }

  static func storageDirectoryName(bundleIdentifier: String?) -> String {
    bundleIdentifier == "com.omi.omi-companion" ? "Omi Companion" : "Omi"
  }

  static var authEmulatorHost: String? {
    guard isEnabled else { return nil }
    return nonEmpty(value("FIREBASE_AUTH_EMULATOR_HOST"))
  }

  static var selectedUser: String? { nonEmpty(value("OMI_LOCAL_AUTH_USER")) }
  static var selectedEmail: String? { nonEmpty(value("OMI_LOCAL_AUTH_EMAIL")) }
  static var selectedPassword: String? { nonEmpty(value("OMI_LOCAL_AUTH_PASSWORD")) }
  static var selectedDisplayName: String? { nonEmpty(value("OMI_LOCAL_AUTH_DISPLAY_NAME")) }

  static func applicationSupportURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent(storageDirectoryName, isDirectory: true)
  }

  static func cachesURL() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent(storageDirectoryName, isDirectory: true)
  }

  private static func value(_ key: String) -> String? {
    guard let raw = getenv(key), let value = String(validatingUTF8: raw) else { return nil }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}
