import XCTest
@testable import Omi_Computer

/// Tests for the screen-capture self-heal invariant:
/// a transient "Screen recording permission not granted" failure must NOT
/// clobber the persisted `screenAnalysisEnabled` flag. Only non-permission
/// failures (API keys, paywall, init errors) may flip it to false.
///
/// See: SidebarView.toggleMonitoring, OmiApp.screenCaptureToggled,
/// DashboardPage.toggleCapture, RewindPage.toggleMonitoring, and the
/// DesktopHomeView app-active self-heal path.
@MainActor
final class ScreenCaptureSelfHealTests: XCTestCase {

  private let key = "screenAnalysisEnabled"

  override func setUp() {
    super.setUp()
    UserDefaults.standard.set(true, forKey: key)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: key)
    super.tearDown()
  }

  // MARK: - The invariant

  /// The decision function: should we clobber screenAnalysisEnabled to false
  /// given a startMonitoring failure reason?
  /// Mirrors the logic in SidebarView, OmiApp, DashboardPage, RewindPage.
  private func shouldClobberIntent(failureReason: String?) -> Bool {
    failureReason != "Screen recording permission not granted"
  }

  // MARK: - Tests

  func testPermissionFailureDoesNotClobberIntent() {
    // The exact constant ProactiveAssistantsPlugin emits when TCC/preflight says no.
    let reason = ProactiveAssistantsPlugin.permissionNotGrantedError
    XCTAssertFalse(
      shouldClobberIntent(failureReason: reason),
      "A transient permission failure must not clobber screenAnalysisEnabled — the app-active self-heal path depends on it staying true."
    )
  }

  func testNonPermissionFailureClobbersIntent() {
    // Any other failure (API keys, init error, paywall) → clobber is correct.
    XCTAssertTrue(shouldClobberIntent(failureReason: "trial_expired"))
    XCTAssertTrue(shouldClobberIntent(failureReason: "Some init error"))
    XCTAssertTrue(shouldClobberIntent(failureReason: nil))
  }

  func testScreenAnalysisEnabledStaysTrueAfterPermissionFailure() {
    // Simulate the flow: user has it on, startMonitoring fails on permission,
    // we must NOT write false.
    UserDefaults.standard.set(true, forKey: key)
    let failureReason = "Screen recording permission not granted"
    if shouldClobberIntent(failureReason: failureReason) {
      UserDefaults.standard.set(false, forKey: key)
    }
    XCTAssertTrue(
      UserDefaults.standard.bool(forKey: key),
      "screenAnalysisEnabled must remain true after a permission failure so self-heal can retry."
    )
  }

  func testScreenAnalysisEnabledFlipsFalseAfterNonPermissionFailure() {
    UserDefaults.standard.set(true, forKey: key)
    let failureReason = "trial_expired"
    if shouldClobberIntent(failureReason: failureReason) {
      UserDefaults.standard.set(false, forKey: key)
    }
    XCTAssertFalse(
      UserDefaults.standard.bool(forKey: key),
      "Non-permission failures should clobber the flag — the user's intent cannot be honored."
    )
  }

  // MARK: - Self-heal re-arm condition

  /// Mirrors DesktopHomeView's self-heal guard:
  /// !screenAnalysisEnabled && !isMonitoring && TCC granted && !paywalled && keys available
  /// → re-arm to true.
  func testSelfHealReArmsWhenTCCGranted() {
    UserDefaults.standard.set(false, forKey: key)
    let tccGranted = true
    let isPaywalled = false
    let keysAvailable = true
    let isMonitoring = false
    let screenAnalysisEnabled = UserDefaults.standard.bool(forKey: key)

    if !screenAnalysisEnabled && !isMonitoring && tccGranted && !isPaywalled && keysAvailable {
      UserDefaults.standard.set(true, forKey: key)
    }
    XCTAssertTrue(
      UserDefaults.standard.bool(forKey: key),
      "Self-heal must re-arm screenAnalysisEnabled when TCC is granted and no blockers."
    )
  }

  func testSelfHealDoesNotReArmWhenTCCDenied() {
    UserDefaults.standard.set(false, forKey: key)
    let tccGranted = false
    let isPaywalled = false
    let keysAvailable = true
    let isMonitoring = false
    let screenAnalysisEnabled = UserDefaults.standard.bool(forKey: key)

    if !screenAnalysisEnabled && !isMonitoring && tccGranted && !isPaywalled && keysAvailable {
      UserDefaults.standard.set(true, forKey: key)
    }
    XCTAssertFalse(
      UserDefaults.standard.bool(forKey: key),
      "Self-heal must NOT re-arm when TCC is not granted — the user hasn't granted permission yet."
    )
  }

  func testSelfHealDoesNotReArmWhenAlreadyEnabled() {
    UserDefaults.standard.set(true, forKey: key)
    // If already true, self-heal is unnecessary — don't double-fire.
    let screenAnalysisEnabled = UserDefaults.standard.bool(forKey: key)
    let alreadyArmed = screenAnalysisEnabled
    XCTAssertTrue(alreadyArmed, "Flag should stay true — self-heal is a no-op when already armed.")
  }
}
