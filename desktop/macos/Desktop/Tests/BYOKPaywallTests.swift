import XCTest

@testable import Omi_Computer

/// Verifies the BYOK-vs-paywall precedence fix: a user with all four BYOK
/// keys configured locally is never paywalled, regardless of the persisted
/// `desktop_isPaywalled` flag.
@MainActor
final class BYOKPaywallTests: XCTestCase {
    private let paywallKey = "desktop_isPaywalled"

    private func setAllBYOKKeys() {
        for p in BYOKProvider.allCases {
            UserDefaults.standard.set("sk-test-\(p.rawValue)", forKey: p.storageKey)
        }
    }

    private func clearAllBYOKKeys() {
        for p in BYOKProvider.allCases {
            UserDefaults.standard.removeObject(forKey: p.storageKey)
        }
        UserDefaults.standard.removeObject(forKey: APIKeyService.openRouterStorageKey)
    }

    override func tearDown() {
        CredentialHealthManager.shared.reset()
        clearAllBYOKKeys()
        UserDefaults.standard.removeObject(forKey: paywallKey)
        super.tearDown()
    }

    /// The standalone OpenRouter key must stay outside the four-provider BYOK
    /// gate: configuring it alone must not flip the user onto the free plan,
    /// and removing it must not disturb an otherwise-complete BYOK set.
    func testOpenRouterKeyDoesNotParticipateInByokGate() {
        clearAllBYOKKeys()

        UserDefaults.standard.set("sk-or-v1-test", forKey: APIKeyService.openRouterStorageKey)

        XCTAssertEqual(APIKeyService.currentOpenRouterKey, "sk-or-v1-test")
        XCTAssertFalse(APIKeyService.isByokActive, "OpenRouter alone must not activate four-provider BYOK")

        setAllBYOKKeys()
        UserDefaults.standard.removeObject(forKey: APIKeyService.openRouterStorageKey)

        XCTAssertNil(APIKeyService.currentOpenRouterKey)
        XCTAssertTrue(APIKeyService.isByokActive, "OpenRouter must stay independent from four-provider BYOK")
    }

    func testByokActiveRequiresAllFourKeys() {
        clearAllBYOKKeys()
        XCTAssertFalse(APIKeyService.isByokActive)

        // Three of four → still not active
        for p in BYOKProvider.allCases.dropLast() {
            UserDefaults.standard.set("k", forKey: p.storageKey)
        }
        XCTAssertFalse(APIKeyService.isByokActive, "3/4 keys must not count as BYOK")

        // All four → active
        setAllBYOKKeys()
        XCTAssertTrue(APIKeyService.isByokActive)
    }

    func testBuildHeadersDoesNotAttachPartialByokKeys() async throws {
        clearAllBYOKKeys()
        UserDefaults.standard.set("sk-test-openai", forKey: BYOKProvider.openai.storageKey)

        let client = APIClient()
        await client.setTestAuthHeader("Bearer test-token")
        let headers = try await client.buildHeaders()

        XCTAssertNil(headers[BYOKProvider.openai.headerName])
    }

    func testBuildHeadersCanExplicitlyExcludeByokKeys() async throws {
        setAllBYOKKeys()

        let client = APIClient()
        await client.setTestAuthHeader("Bearer test-token")
        let headers = try await client.buildHeaders(includeBYOK: false)

        for provider in BYOKProvider.allCases {
            XCTAssertNil(headers[provider.headerName])
        }
    }

    func testBuildHeadersSuppressesOnlyInvalidByokHeader() async throws {
        setAllBYOKKeys()
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

    func testPaywallFlagSuppressedWhenByokActive() {
        // The exact bug: trial-expired flag set, then user adds all 4 BYOK keys.
        UserDefaults.standard.set(true, forKey: paywallKey)
        setAllBYOKKeys()
        XCTAssertFalse(
            AppState.isPaywalledEffective,
            "BYOK-active user must NOT be paywalled even with the flag set")
    }

    func testPaywallFlagAppliesWhenNotByok() {
        UserDefaults.standard.set(true, forKey: paywallKey)
        clearAllBYOKKeys()
        XCTAssertTrue(
            AppState.isPaywalledEffective,
            "Non-BYOK trial-expired user stays paywalled")
    }

    func testNotPaywalledWhenFlagUnset() {
        UserDefaults.standard.set(false, forKey: paywallKey)
        clearAllBYOKKeys()
        XCTAssertFalse(AppState.isPaywalledEffective)
    }

    func testRemovingOneByokKeyReappliesPaywall() {
        UserDefaults.standard.set(true, forKey: paywallKey)
        setAllBYOKKeys()
        XCTAssertFalse(AppState.isPaywalledEffective)

        // User clears their Deepgram key → no longer fully BYOK → paywall returns.
        UserDefaults.standard.removeObject(forKey: BYOKProvider.deepgram.storageKey)
        XCTAssertTrue(AppState.isPaywalledEffective)
    }
}
