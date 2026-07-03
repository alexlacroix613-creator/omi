import Foundation

/// Pure, testable helpers for the ChatGPT-account (Codex) connection.
///
/// The Codex agent authenticates the user's ChatGPT subscription by reading
/// `~/.codex/auth.json`, which the `codex login` CLI writes after its browser
/// OAuth handshake (its own localhost callback). Connection status is defined
/// purely by the presence of a non-empty `tokens.access_token` in that file.
///
/// Tokens rotate, so every check reads the file fresh — nothing here caches
/// parsed contents.
enum CodexAccountAuth {
    /// Directories searched for the `codex` executable, in priority order,
    /// after honoring an explicit `CODEX_PATH` override.
    static let searchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    /// Absolute path to `~/.codex/auth.json` for the given home directory.
    static func authFilePath(homeDirectory: String = NSHomeDirectory()) -> String {
        (homeDirectory as NSString)
            .appendingPathComponent(".codex")
            .appending("/auth.json")
    }

    /// Path used when a user disconnects — the token file is renamed here
    /// (reversible) rather than deleted.
    static func disconnectedFilePath(homeDirectory: String = NSHomeDirectory()) -> String {
        authFilePath(homeDirectory: homeDirectory) + ".disconnected"
    }

    /// Whether the raw auth.json bytes carry a non-empty `tokens.access_token`.
    /// Exposed for unit tests — no filesystem access.
    static func hasAccessToken(inJSON data: Data) -> Bool {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String
        else {
            return false
        }
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether `~/.codex/auth.json` currently exists and holds a usable token.
    /// Reads fresh on every call.
    static func isConnected(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> Bool {
        let path = authFilePath(homeDirectory: homeDirectory)
        guard let data = fileManager.contents(atPath: path) else { return false }
        return hasAccessToken(inJSON: data)
    }

    /// Locate the `codex` CLI. Honors `CODEX_PATH`, then falls back to the
    /// standard Homebrew/local bin locations. Returns nil when Codex is not
    /// installed, so callers can prompt the user to install it.
    static func locateCodexBinary(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let override = environment["CODEX_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           fileManager.isExecutableFile(atPath: override) {
            return override
        }
        for dir in searchDirectories {
            let candidate = (dir as NSString).appendingPathComponent("codex")
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
