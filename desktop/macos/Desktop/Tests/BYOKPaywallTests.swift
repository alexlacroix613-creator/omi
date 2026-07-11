import XCTest

@testable import Omi_Computer

/// Verifies the BYOK-vs-paywall precedence fix: a user with all four BYOK
/// keys configured locally is never paywalled, regardless of the persisted
/// `desktop_isPaywalled` flag.
@MainActor
final class BYOKPaywallTests: XCTestCase {
    private let paywallKey = "desktop_isPaywalled"

    private func setAllBYOKKeys() throws {
        for p in BYOKProvider.allCases {
            try APIKeyService.saveByokKey("sk-test-\(p.rawValue)", provider: p)
        }
    }

    private func clearAllBYOKKeys() throws {
        for p in BYOKProvider.allCases {
            try APIKeyService.saveByokKey("", provider: p)
        }
        try APIKeyService.saveOpenRouterKey("")
    }

    override func tearDown() {
        CredentialHealthManager.shared.reset()
        try? clearAllBYOKKeys()
        UserDefaults.standard.removeObject(forKey: paywallKey)
        super.tearDown()
    }

    /// The standalone OpenRouter key must stay outside the four-provider BYOK
    /// gate: configuring it alone must not flip the user onto the free plan,
    /// and removing it must not disturb an otherwise-complete BYOK set.
    func testOpenRouterKeyDoesNotParticipateInByokGate() throws {
        try clearAllBYOKKeys()

        try APIKeyService.saveOpenRouterKey("sk-or-v1-test")

        XCTAssertEqual(APIKeyService.currentOpenRouterKey, "sk-or-v1-test")
        XCTAssertFalse(APIKeyService.isByokActive, "OpenRouter alone must not activate four-provider BYOK")

        try setAllBYOKKeys()
        try APIKeyService.saveOpenRouterKey("")

        XCTAssertNil(APIKeyService.currentOpenRouterKey)
        XCTAssertTrue(APIKeyService.isByokActive, "OpenRouter must stay independent from four-provider BYOK")
    }

    func testByokActiveRequiresAllFourKeys() throws {
        try clearAllBYOKKeys()
        XCTAssertFalse(APIKeyService.isByokActive)

        // Three of four → still not active
        for p in BYOKProvider.allCases.dropLast() {
            try APIKeyService.saveByokKey("k", provider: p)
        }
        XCTAssertFalse(APIKeyService.isByokActive, "3/4 keys must not count as BYOK")

        // All four → active
        try setAllBYOKKeys()
        XCTAssertTrue(APIKeyService.isByokActive)
    }

    func testBuildHeadersDoesNotAttachPartialByokKeys() async throws {
        try clearAllBYOKKeys()
        try APIKeyService.saveByokKey("sk-test-openai", provider: .openai)

        let client = APIClient()
        await client.setTestAuthHeader("Bearer test-token")
        let headers = try await client.buildHeaders()

        XCTAssertNil(headers[BYOKProvider.openai.headerName])
    }

    func testBuildHeadersCanExplicitlyExcludeByokKeys() async throws {
        try setAllBYOKKeys()

        let client = APIClient()
        await client.setTestAuthHeader("Bearer test-token")
        let headers = try await client.buildHeaders(includeBYOK: false)

        for provider in BYOKProvider.allCases {
            XCTAssertNil(headers[provider.headerName])
        }
    }

    func testBuildHeadersSuppressesOnlyInvalidByokHeader() async throws {
        try setAllBYOKKeys()
        let openAIKey = try XCTUnwrap(APIKeyService.byokKey(.openai))
        CredentialHealthManager.shared.recordProviderFailure(
            .providerAuthFailed(provider: .openai, mode: .byok),
            provider: .openai,
            authMode: .byok,
            fingerprint: APIKeyService.byokFingerprint(openAIKey),
            context: "test")

        let client = APIClient()
        await client.setTestAuthHeader("Bearer test-token")
        let headers = try await client.buildHeaders()

        XCTAssertNil(headers[BYOKProvider.openai.headerName])
        for provider in BYOKProvider.allCases where provider != .openai {
            XCTAssertEqual(headers[provider.headerName], "sk-test-\(provider.rawValue)")
        }
    }

    func testPaywallFlagSuppressedWhenByokActive() throws {
        // The exact bug: trial-expired flag set, then user adds all 4 BYOK keys.
        UserDefaults.standard.set(true, forKey: paywallKey)
        try setAllBYOKKeys()
        XCTAssertFalse(
            AppState.isPaywalledEffective,
            "BYOK-active user must NOT be paywalled even with the flag set")
    }

    func testPaywallFlagAppliesWhenNotByok() throws {
        UserDefaults.standard.set(true, forKey: paywallKey)
        try clearAllBYOKKeys()
        XCTAssertTrue(
            AppState.isPaywalledEffective,
            "Non-BYOK trial-expired user stays paywalled")
    }

    func testNotPaywalledWhenFlagUnset() throws {
        UserDefaults.standard.set(false, forKey: paywallKey)
        try clearAllBYOKKeys()
        XCTAssertFalse(AppState.isPaywalledEffective)
    }

    func testRemovingOneByokKeyReappliesPaywall() throws {
        UserDefaults.standard.set(true, forKey: paywallKey)
        try setAllBYOKKeys()
        XCTAssertFalse(AppState.isPaywalledEffective)

        // User clears their Deepgram key → no longer fully BYOK → paywall returns.
        try APIKeyService.saveByokKey("", provider: .deepgram)
        XCTAssertTrue(AppState.isPaywalledEffective)
    }
}
