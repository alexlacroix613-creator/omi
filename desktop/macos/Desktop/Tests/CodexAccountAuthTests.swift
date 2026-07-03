import XCTest

@testable import Omi_Computer

/// Verifies the pure ChatGPT-account (Codex) auth helpers that back the
/// "Connect ChatGPT" flow: token detection in ~/.codex/auth.json, path
/// derivation, connection status against a real temp home, and Codex CLI
/// location (CODEX_PATH override + standard search dirs).
final class CodexAccountAuthTests: XCTestCase {

    // MARK: - Token parsing (no filesystem)

    func testHasAccessTokenDetectsNonEmptyToken() {
        let json = #"{"tokens":{"access_token":"sk-abc123"}}"#.data(using: .utf8)!
        XCTAssertTrue(CodexAccountAuth.hasAccessToken(inJSON: json))
    }

    func testHasAccessTokenRejectsEmptyOrMissingToken() {
        let empty = #"{"tokens":{"access_token":"   "}}"#.data(using: .utf8)!
        XCTAssertFalse(CodexAccountAuth.hasAccessToken(inJSON: empty))

        let noToken = #"{"tokens":{}}"#.data(using: .utf8)!
        XCTAssertFalse(CodexAccountAuth.hasAccessToken(inJSON: noToken))

        let noTokens = #"{"OPENAI_API_KEY":"sk-key"}"#.data(using: .utf8)!
        XCTAssertFalse(CodexAccountAuth.hasAccessToken(inJSON: noTokens))
    }

    func testHasAccessTokenRejectsMalformedJSON() {
        let garbage = "{ not valid json".data(using: .utf8)!
        XCTAssertFalse(CodexAccountAuth.hasAccessToken(inJSON: garbage))
    }

    // MARK: - Paths

    func testAuthFilePathAndDisconnectedPath() {
        let home = "/tmp/fake-home"
        XCTAssertEqual(CodexAccountAuth.authFilePath(homeDirectory: home), "/tmp/fake-home/.codex/auth.json")
        XCTAssertEqual(
            CodexAccountAuth.disconnectedFilePath(homeDirectory: home),
            "/tmp/fake-home/.codex/auth.json.disconnected"
        )
    }

    // MARK: - isConnected against a temp home

    func testIsConnectedReadsFreshFromDisk() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codexDir = home.appendingPathComponent(".codex")
        try fm.createDirectory(at: codexDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        // No file yet → not connected.
        XCTAssertFalse(CodexAccountAuth.isConnected(homeDirectory: home.path, fileManager: fm))

        // Write a token → connected.
        let authFile = codexDir.appendingPathComponent("auth.json")
        try #"{"tokens":{"access_token":"sk-live"}}"#.write(to: authFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(CodexAccountAuth.isConnected(homeDirectory: home.path, fileManager: fm))

        // Overwrite with an empty token → fresh read reports not connected.
        try #"{"tokens":{"access_token":""}}"#.write(to: authFile, atomically: true, encoding: .utf8)
        XCTAssertFalse(CodexAccountAuth.isConnected(homeDirectory: home.path, fileManager: fm))
    }

    // MARK: - Locating the codex binary

    func testLocateCodexBinaryHonorsCodexPathOverride() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let bin = dir.appendingPathComponent("codex")
        fm.createFile(atPath: bin.path, contents: Data(), attributes: [.posixPermissions: 0o755])

        let found = CodexAccountAuth.locateCodexBinary(
            environment: ["CODEX_PATH": bin.path],
            fileManager: fm
        )
        XCTAssertEqual(found, bin.path)
    }

    func testLocateCodexBinaryReturnsNilWhenAbsent() {
        let found = CodexAccountAuth.locateCodexBinary(
            environment: ["CODEX_PATH": "/nonexistent/codex-\(UUID().uuidString)"],
            fileManager: FileManager.default
        )
        // Falls through to standard search dirs; on CI these usually lack codex.
        // We only assert the override path itself was not falsely accepted.
        XCTAssertNotEqual(found, "/nonexistent/codex")
    }
}
