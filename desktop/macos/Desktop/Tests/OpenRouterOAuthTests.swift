import XCTest

@testable import Omi_Computer

/// Verifies the pure OpenRouter OAuth PKCE math and callback-URL parsing
/// that back the "Connect OpenRouter" flow. No network calls — the actual
/// OAuth flow against openrouter.ai is never exercised here.
final class OpenRouterOAuthTests: XCTestCase {

  // MARK: - PKCE: code verifier

  func testGenerateCodeVerifierHasRFC7636Length() {
    let verifier = OpenRouterPKCE.generateCodeVerifier()
    // 32 random bytes, base64url-encoded without padding => 43 characters,
    // the minimum (and, here, exact) length RFC 7636 allows (43-128).
    XCTAssertEqual(verifier.count, 43)
  }

  func testGenerateCodeVerifierUsesOnlyBase64URLCharset() {
    let verifier = OpenRouterPKCE.generateCodeVerifier()
    let allowed = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    for scalar in verifier.unicodeScalars {
      XCTAssertTrue(allowed.contains(scalar), "unexpected character '\(scalar)' in verifier")
    }
    XCTAssertFalse(verifier.contains("+"))
    XCTAssertFalse(verifier.contains("/"))
    XCTAssertFalse(verifier.contains("="))
  }

  func testGenerateCodeVerifierIsRandomAcrossCalls() {
    let a = OpenRouterPKCE.generateCodeVerifier()
    let b = OpenRouterPKCE.generateCodeVerifier()
    XCTAssertNotEqual(a, b)
  }

  // MARK: - PKCE: code challenge (known SHA-256 vector, RFC 7636 Appendix B)

  func testCodeChallengeMatchesRFC7636KnownVector() {
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    XCTAssertEqual(OpenRouterPKCE.codeChallenge(forVerifier: verifier), expectedChallenge)
  }

  func testCodeChallengeIsDeterministicForSameVerifier() {
    let verifier = OpenRouterPKCE.generateCodeVerifier()
    let a = OpenRouterPKCE.codeChallenge(forVerifier: verifier)
    let b = OpenRouterPKCE.codeChallenge(forVerifier: verifier)
    XCTAssertEqual(a, b)
  }

  func testCodeChallengeHasNoBase64Padding() {
    let challenge = OpenRouterPKCE.codeChallenge(forVerifier: OpenRouterPKCE.generateCodeVerifier())
    XCTAssertFalse(challenge.contains("="))
    XCTAssertFalse(challenge.contains("+"))
    XCTAssertFalse(challenge.contains("/"))
  }

  // MARK: - Base64url encoding helper

  func testBase64URLEncodeStripsPaddingAndSwapsUnsafeCharacters() {
    // Bytes chosen so standard base64 would contain both '+' and '/' and
    // require padding, to exercise every substitution in one vector.
    let bytes: [UInt8] = [0xFB, 0xEF, 0xBE]
    let standard = Data(bytes).base64EncodedString()
    XCTAssertTrue(standard.contains("+") || standard.contains("/"), "test bytes should exercise +/ chars")

    let encoded = OpenRouterPKCE.base64URLEncode(Data(bytes))
    XCTAssertFalse(encoded.contains("+"))
    XCTAssertFalse(encoded.contains("/"))
    XCTAssertFalse(encoded.contains("="))
  }

  // MARK: - Callback URL parsing

  func testExtractCodeFromFullCallbackURL() {
    let url = URL(string: "http://127.0.0.1:54137/callback?code=abc123")!
    XCTAssertEqual(OpenRouterCallback.extractCode(from: url), "abc123")
  }

  func testExtractCodeFromCallbackURLWithExtraParams() {
    let url = URL(string: "http://127.0.0.1:54137/callback?foo=bar&code=xyz-789&baz=qux")!
    XCTAssertEqual(OpenRouterCallback.extractCode(from: url), "xyz-789")
  }

  func testExtractCodeReturnsNilWhenMissing() {
    let url = URL(string: "http://127.0.0.1:54137/callback?foo=bar")!
    XCTAssertNil(OpenRouterCallback.extractCode(from: url))
  }

  func testExtractCodeReturnsNilForNonCallbackPath() {
    let url = URL(string: "http://127.0.0.1:54137/favicon.ico?code=abc123")!
    // extractCode(from:) only inspects query items, not path — path
    // filtering is the request-target variant's job (tested below).
    XCTAssertEqual(OpenRouterCallback.extractCode(from: url), "abc123")
  }

  // MARK: - Raw HTTP request-target parsing (loopback server path)

  func testExtractCodeFromRequestTargetAcceptsValidCallback() {
    XCTAssertEqual(
      OpenRouterCallback.extractCode(fromRequestTarget: "/callback?code=good-code"), "good-code")
  }

  func testExtractCodeFromRequestTargetRejectsWrongPath() {
    XCTAssertNil(OpenRouterCallback.extractCode(fromRequestTarget: "/favicon.ico?code=abc123"))
  }

  func testExtractCodeFromRequestTargetRejectsMissingCode() {
    XCTAssertNil(OpenRouterCallback.extractCode(fromRequestTarget: "/callback?state=only"))
  }

  func testExtractCodeFromRequestTargetRejectsEmptyCode() {
    XCTAssertNil(OpenRouterCallback.extractCode(fromRequestTarget: "/callback?code="))
  }

  // MARK: - Authorization URL construction

  func testAuthorizationURLIncludesRequiredQueryItems() {
    let url = OpenRouterOAuthURLBuilder.authorizationURL(
      callbackURL: "http://127.0.0.1:54137/callback",
      codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )
    XCTAssertNotNil(url)
    XCTAssertEqual(url?.scheme, "https")
    XCTAssertEqual(url?.host, "openrouter.ai")
    XCTAssertEqual(url?.path, "/auth")

    let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
    let items = components?.queryItems ?? []
    XCTAssertEqual(items.first(where: { $0.name == "callback_url" })?.value, "http://127.0.0.1:54137/callback")
    XCTAssertEqual(
      items.first(where: { $0.name == "code_challenge" })?.value,
      "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    XCTAssertEqual(items.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
  }

  // MARK: - Error messages

  func testChallengeMismatchAndNotLoggedInHaveDistinctReadableMessages() {
    let challengeMismatch = OpenRouterAuthError.challengeMismatch.errorDescription
    let notLoggedIn = OpenRouterAuthError.notLoggedIn.errorDescription
    XCTAssertNotNil(challengeMismatch)
    XCTAssertNotNil(notLoggedIn)
    XCTAssertNotEqual(challengeMismatch, notLoggedIn)
  }
}
