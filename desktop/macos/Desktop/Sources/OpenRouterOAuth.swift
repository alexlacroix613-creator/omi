import AppKit
import CryptoKit
import Darwin
import Foundation
import SwiftUI

/// One-click "Connect OpenRouter" — mints an API key via OpenRouter's
/// official OAuth PKCE flow (https://openrouter.ai/docs/api-reference/authentication)
/// instead of asking the user to copy/paste a raw `sk-or-v1-...` key.
///
/// Design choices (see AGENTS/CLAUDE task notes for the ask):
/// - **Browser-open mechanism**: `NSWorkspace.shared.open(_:)` + a loopback
///   HTTP listener, exactly like the app's existing generic OAuth flow in
///   `AuthService.signIn(provider:)`. `ASWebAuthenticationSession` was
///   deliberately NOT used: its completion handler only fires for an
///   `https` or app-registered custom-scheme redirect, and OpenRouter's flow
///   redirects to a bare `http://localhost:<port>/callback` — a loopback
///   HTTP server needs no completion handler at all, so it is strictly
///   simpler here, not just "an option."
/// - **Where the listener lives**: `OpenRouterCallbackServer` below is a
///   dedicated loopback server, not a reuse of `AuthService`'s
///   `OAuthLoopbackCallbackServer`. That existing type hard-requires a
///   matching `state` query parameter (CSRF protection for Firebase/Google
///   sign-in); OpenRouter's redirect carries only `?code=...` with no
///   `state` at all, so reusing it would make every real callback fail
///   parsing. Rather than loosen a security check shared by the
///   Google/Firebase sign-in path (out of scope — this task must not touch
///   the Codex/Claude/Google auth paths), this file has its own minimal
///   listener using the same proven raw-BSD-socket idiom (see
///   `OAuthLoopbackCallbackServerTests.swift` for the pattern being
///   mirrored). Network.framework's `NWListener` was considered and
///   rejected: it would add async delegate/callback plumbing for no benefit
///   over the already-tested blocking-accept-loop-on-a-background-queue
///   approach already proven correct elsewhere in this app.

// MARK: - PKCE

enum OpenRouterPKCE {
  /// RFC 7636 code verifier: base64url(32 random bytes), unpadded — 43
  /// characters, within the 43–128 char range the spec requires.
  static func generateCodeVerifier() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return base64URLEncode(Data(bytes))
  }

  /// code_challenge = base64url(SHA256(code_verifier)), method "S256".
  static func codeChallenge(forVerifier verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return base64URLEncode(Data(digest))
  }

  /// Base64url per RFC 4648 §5: `+`→`-`, `/`→`_`, padding stripped.
  static func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

// MARK: - Callback URL parsing

enum OpenRouterCallback {
  /// Extracts `code` from a full callback URL (e.g. as captured by a
  /// browser-side redirect handler). Pure — no filesystem/network access.
  static func extractCode(from url: URL) -> String? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    return components.queryItems?.first(where: { $0.name == "code" })?.value
  }

  /// Extracts `code` from a raw HTTP request target (e.g. `/callback?code=...`),
  /// as received by the loopback listener below. Returns nil for anything
  /// that isn't a `/callback` request carrying a non-empty `code`.
  static func extractCode(fromRequestTarget target: String, expectedState: String? = nil) -> String? {
    guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
      components.path == "/callback"
    else {
      return nil
    }
    if let expectedState {
      guard components.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
        return nil
      }
    }
    guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty
    else {
      return nil
    }
    return code
  }
}

// MARK: - Loopback listener

/// Minimal single-shot loopback HTTP server for the OpenRouter OAuth
/// callback. Binds 127.0.0.1 on an OS-assigned port (port 0), accepts one
/// `/callback?code=...` request, replies with a short "you can close this
/// tab" page, and shuts itself down. Mirrors the raw-socket idiom already
/// used and tested for `AuthService.OAuthLoopbackCallbackServer`.
final class OpenRouterCallbackServer: @unchecked Sendable {
  enum ServerError: Error {
    case socketCreationFailed
    case bindFailed
    case listenFailed
    case portLookupFailed
  }

  private var socketFD: Int32?
  private var activeClientFD: Int32?
  private let queue = DispatchQueue(label: "com.omi.desktop.openrouter-oauth-loopback")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<String, Error>?
  private var pendingResult: Result<String, Error>?
  private var completed = false

  let port: UInt16
  let expectedState: String
  var callbackURLString: String {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = Int(port)
    components.path = "/callback"
    components.queryItems = [URLQueryItem(name: "state", value: expectedState)]
    return components.url!.absoluteString
  }

  private init(socketFD: Int32, port: UInt16, expectedState: String) {
    self.socketFD = socketFD
    self.port = port
    self.expectedState = expectedState
  }

  static func start(expectedState: String = OpenRouterPKCE.generateCodeVerifier()) throws -> OpenRouterCallbackServer {
    let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    guard fd >= 0 else { throw ServerError.socketCreationFailed }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

    let bindResult = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      close(fd)
      throw ServerError.bindFailed
    }

    guard listen(fd, 1) == 0 else {
      close(fd)
      throw ServerError.listenFailed
    }

    var boundAddr = sockaddr_in()
    var boundAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    let portResult = withUnsafeMutablePointer(to: &boundAddr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(fd, $0, &boundAddrLen)
      }
    }
    guard portResult == 0 else {
      close(fd)
      throw ServerError.portLookupFailed
    }

    let server = OpenRouterCallbackServer(
      socketFD: fd,
      port: UInt16(bigEndian: boundAddr.sin_port),
      expectedState: expectedState
    )
    server.acceptRequests()
    return server
  }

  /// Suspends until a valid `/callback?code=...` request arrives, or throws
  /// if the server is cancelled/failed/stopped first.
  func waitForCode() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if let pendingResult {
        lock.unlock()
        continuation.resume(with: pendingResult)
        return
      }
      self.continuation = continuation
      lock.unlock()
    }
  }

  func cancel() {
    finish(.failure(OpenRouterAuthError.cancelled))
  }

  func fail(with error: Error) {
    finish(.failure(error))
  }

  func stop() {
    lock.lock()
    let alreadyCompleted = completed
    completed = true
    closeSocketsLocked()
    lock.unlock()
    if !alreadyCompleted {
      resumeIfNeeded(.failure(OpenRouterAuthError.cancelled))
    }
  }

  deinit {
    stop()
  }

  private func acceptRequests() {
    queue.async { [weak self] in
      guard let self else { return }

      while !self.isCompleted {
        guard let listenFD = self.currentListenSocket() else { return }

        var remoteAddr = sockaddr()
        var remoteLen = socklen_t(MemoryLayout<sockaddr>.size)
        let clientFD = accept(listenFD, &remoteAddr, &remoteLen)
        guard clientFD >= 0 else { continue }

        self.setActiveClient(clientFD)
        defer {
          self.closeActiveClientIfMatching(clientFD)
        }

        var noSigPipe: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = recv(clientFD, &buffer, buffer.count - 1, 0)
        guard bytesRead > 0,
          let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8)
        else {
          self.sendResponse(clientFD, status: "400 Bad Request", message: "Invalid callback request.")
          continue
        }

        guard let requestTarget = Self.requestTarget(fromRequestLine: request),
          Self.hasExpectedHost(request, port: self.port),
          Self.hasSafeOrigin(request)
        else {
          self.sendResponse(clientFD, status: "400 Bad Request", message: "Invalid callback request.")
          continue
        }

        if let code = OpenRouterCallback.extractCode(
          fromRequestTarget: requestTarget,
          expectedState: self.expectedState
        ) {
          self.sendResponse(
            clientFD, status: "200 OK", message: "Connected — you can close this tab.")
          self.finish(.success(code))
          return
        } else {
          self.sendResponse(clientFD, status: "400 Bad Request", message: "Invalid callback request.")
          continue
        }
      }
    }
  }

  private static func requestTarget(fromRequestLine request: String) -> String? {
    guard let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else {
      return nil
    }
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2, parts[0] == "GET" else { return nil }
    return String(parts[1])
  }

  private static func hasExpectedHost(_ request: String, port: UInt16) -> Bool {
    let expected = "host: 127.0.0.1:\(port)"
    return request.lowercased().split(separator: "\n").contains {
      $0.trimmingCharacters(in: .whitespacesAndNewlines) == expected
    }
  }

  private static func hasSafeOrigin(_ request: String) -> Bool {
    let lines = request.split(separator: "\n").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let origin = lines.first(where: { $0.lowercased().hasPrefix("origin:") }) else {
      return true
    }
    guard let value = origin.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces),
      let url = URL(string: value)
    else { return false }
    return url.scheme == "https" && url.host == "openrouter.ai"
  }

  private func sendResponse(_ clientFD: Int32, status: String, message: String) {
    let body = """
      <!doctype html><html><head><meta charset="utf-8"><title>OpenRouter</title></head><body><p>\(message)</p></body></html>
      """
    let response = """
      HTTP/1.1 \(status)\r
      Content-Type: text/html; charset=utf-8\r
      Content-Length: \(body.utf8.count)\r
      Connection: close\r
      \r
      \(body)
      """
    response.withCString { pointer in
      _ = send(clientFD, pointer, strlen(pointer), 0)
    }
  }

  private func finish(_ result: Result<String, Error>) {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    closeSocketsLocked()
    lock.unlock()
    resumeIfNeeded(result)
  }

  private func resumeIfNeeded(_ result: Result<String, Error>) {
    lock.lock()
    if let continuation {
      self.continuation = nil
      lock.unlock()
      continuation.resume(with: result)
    } else {
      pendingResult = result
      lock.unlock()
    }
  }

  private var isCompleted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return completed
  }

  private func currentListenSocket() -> Int32? {
    lock.lock()
    defer { lock.unlock() }
    return socketFD
  }

  private func setActiveClient(_ fd: Int32) {
    lock.lock()
    activeClientFD = fd
    lock.unlock()
  }

  private func closeActiveClientIfMatching(_ fd: Int32) {
    lock.lock()
    if activeClientFD == fd {
      activeClientFD = nil
      close(fd)
    }
    lock.unlock()
  }

  private func closeSocketsLocked() {
    if let activeClientFD {
      close(activeClientFD)
      self.activeClientFD = nil
    }
    if let socketFD {
      close(socketFD)
      self.socketFD = nil
    }
  }
}

// MARK: - Errors

enum OpenRouterAuthError: LocalizedError, Equatable {
  case cancelled
  case timedOut
  case invalidAuthorizationURL
  case listenerFailed(String)
  /// OpenRouter's key-exchange endpoint returned 400 — challenge mismatch.
  case challengeMismatch
  /// OpenRouter's key-exchange endpoint returned 403 — not logged in, or a
  /// bad/expired code_verifier.
  case notLoggedIn
  case server(status: Int)
  case network(String)
  case malformedResponse

  var errorDescription: String? {
    switch self {
    case .cancelled:
      return "Connection cancelled."
    case .timedOut:
      return "Timed out waiting for OpenRouter. Try again."
    case .invalidAuthorizationURL:
      return "Couldn't build the OpenRouter sign-in link."
    case .listenerFailed(let reason):
      return "Couldn't start a local listener for sign-in: \(reason)"
    case .challengeMismatch:
      return "OpenRouter rejected the sign-in request (challenge mismatch). Try again."
    case .notLoggedIn:
      return "Not signed in to OpenRouter, or the sign-in link expired. Try again."
    case .server(let status):
      return "OpenRouter returned an unexpected error (\(status)). Try again."
    case .network(let message):
      return "Network error reaching OpenRouter: \(message)"
    case .malformedResponse:
      return "OpenRouter returned an unexpected response. Try again."
    }
  }
}

// MARK: - Authorization URL

enum OpenRouterOAuthURLBuilder {
  /// `https://openrouter.ai/auth?callback_url=...&code_challenge=...&code_challenge_method=S256`
  static func authorizationURL(callbackURL: String, codeChallenge: String) -> URL? {
    var components = URLComponents(string: "https://openrouter.ai/auth")
    components?.queryItems = [
      URLQueryItem(name: "callback_url", value: callbackURL),
      URLQueryItem(name: "code_challenge", value: codeChallenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    return components?.url
  }
}

// MARK: - Key exchange

private struct OpenRouterKeyExchangeResponse: Decodable {
  let key: String
  let userId: String?

  enum CodingKeys: String, CodingKey {
    case key
    case userId = "user_id"
  }
}

enum OpenRouterKeyExchange {
  /// POST https://openrouter.ai/api/v1/auth/keys — Content-Type: application/json,
  /// NO auth header. Body: {"code","code_verifier","code_challenge_method":"S256"}.
  static func exchange(code: String, codeVerifier: String) async throws -> String {
    guard let url = URL(string: "https://openrouter.ai/api/v1/auth/keys") else {
      throw OpenRouterAuthError.invalidAuthorizationURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = [
      "code": code,
      "code_verifier": codeVerifier,
      "code_challenge_method": "S256",
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw OpenRouterAuthError.network(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw OpenRouterAuthError.malformedResponse
    }

    switch http.statusCode {
    case 200..<300:
      guard let decoded = try? JSONDecoder().decode(OpenRouterKeyExchangeResponse.self, from: data),
        !decoded.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw OpenRouterAuthError.malformedResponse
      }
      return decoded.key
    case 400:
      throw OpenRouterAuthError.challengeMismatch
    case 403:
      throw OpenRouterAuthError.notLoggedIn
    default:
      throw OpenRouterAuthError.server(status: http.statusCode)
    }
  }
}

// MARK: - Controller (drives the UI)

@MainActor
final class OpenRouterOAuthController: ObservableObject {
  static let shared = OpenRouterOAuthController()

  enum ConnectionState: Equatable {
    case idle
    case waitingForBrowser
    case exchanging
    case connected
    case failed(String)
  }

  @Published private(set) var state: ConnectionState = .idle

  private var activeServer: OpenRouterCallbackServer?
  private var activeTask: Task<Void, Never>?

  private init() {}

  /// Cancels an in-flight connect attempt, if any.
  func cancel() {
    activeServer?.cancel()
    activeServer = nil
    activeTask?.cancel()
    activeTask = nil
    state = .idle
  }

  /// Kicks off the browser-based OAuth PKCE flow. `applyKey` is called on
  /// the main actor with the minted `sk-or-v1-...` key on success.
  func connect(applyKey: @escaping (String) -> Void) {
    guard state != .waitingForBrowser, state != .exchanging else { return }
    state = .waitingForBrowser
    activeTask = Task { [weak self] in
      await self?.runFlow(applyKey: applyKey)
    }
  }

  private func runFlow(applyKey: @escaping (String) -> Void) async {
    let verifier = OpenRouterPKCE.generateCodeVerifier()
    let challenge = OpenRouterPKCE.codeChallenge(forVerifier: verifier)
    let stateNonce = OpenRouterPKCE.generateCodeVerifier()

    let server: OpenRouterCallbackServer
    do {
      server = try OpenRouterCallbackServer.start(expectedState: stateNonce)
    } catch {
      state = .failed(OpenRouterAuthError.listenerFailed("\(error)").localizedDescription)
      return
    }
    activeServer = server

    guard
      let authURL = OpenRouterOAuthURLBuilder.authorizationURL(
        callbackURL: server.callbackURLString, codeChallenge: challenge)
    else {
      server.stop()
      activeServer = nil
      state = .failed(OpenRouterAuthError.invalidAuthorizationURL.localizedDescription)
      return
    }

    NSWorkspace.shared.open(authURL)

    // Auto-shutdown after a 5-minute timeout if nothing ever calls back.
    let timeoutTask = Task {
      try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
      guard !Task.isCancelled else { return }
      server.fail(with: OpenRouterAuthError.timedOut)
    }

    do {
      let code = try await withTaskCancellationHandler {
        try await server.waitForCode()
      } onCancel: {
        server.cancel()
      }
      timeoutTask.cancel()
      activeServer = nil

      state = .exchanging
      let key = try await OpenRouterKeyExchange.exchange(code: code, codeVerifier: verifier)
      applyKey(key)
      state = .connected
    } catch {
      timeoutTask.cancel()
      activeServer = nil
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      state = .failed(message)
    }
  }
}

// MARK: - UI

/// "Connect OpenRouter" button with idle → waiting-for-browser (cancellable)
/// → exchanging → connected/error states. Embedded above the manual
/// SecureField fallback in `openRouterKeyCard`.
struct OpenRouterConnectButton: View {
  @ObservedObject private var controller = OpenRouterOAuthController.shared
  let onConnected: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Button(buttonTitle, action: handleTap)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)

        if controller.state == .waitingForBrowser || controller.state == .exchanging {
          ProgressView()
            .controlSize(.small)
        }

        if controller.state == .connected {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(OmiColors.success)
        }
      }

      if case .failed(let message) = controller.state {
        Text(message)
          .scaledFont(size: 11)
          .foregroundColor(.red)
      }
    }
  }

  private func handleTap() {
    switch controller.state {
    case .waitingForBrowser, .exchanging:
      controller.cancel()
    default:
      controller.connect(applyKey: onConnected)
    }
  }

  private var buttonTitle: String {
    switch controller.state {
    case .idle, .connected, .failed:
      return "Connect OpenRouter"
    case .waitingForBrowser:
      return "Waiting for browser… (cancel)"
    case .exchanging:
      return "Finishing sign-in…"
    }
  }
}
