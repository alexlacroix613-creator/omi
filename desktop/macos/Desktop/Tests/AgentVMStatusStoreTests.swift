import XCTest

@testable import Omi_Computer

/// Covers the pure `AgentVMState` / `AgentVMStallLogic` logic plus
/// `AgentVMStatusStore.transition(to:)`. Deliberately does not exercise
/// `markFailed` / `markTimedOut` — those call into `NotificationService`
/// (system notification permission APIs, floating-bar window manager), which
/// is out of scope for a fast unit test and would make this suite flaky /
/// dependent on macOS notification state.
final class AgentVMStatusStoreTests: XCTestCase {

  private let start = Date(timeIntervalSince1970: 2_000_000)

  // MARK: - AgentVMState

  func testRunningStatesAreExactlyProvisioningPollingUploading() {
    XCTAssertFalse(AgentVMState.idle.isRunning)
    XCTAssertTrue(AgentVMState.provisioning.isRunning)
    XCTAssertTrue(AgentVMState.polling.isRunning)
    XCTAssertTrue(AgentVMState.uploading.isRunning)
    XCTAssertFalse(AgentVMState.ready.isRunning)
    XCTAssertFalse(AgentVMState.failed("boom").isRunning)
    XCTAssertFalse(AgentVMState.timedOut.isRunning)
  }

  func testFailedStateCarriesItsReasonInTheLabel() {
    XCTAssertTrue(AgentVMState.failed("HTTP 500").label.contains("HTTP 500"))
  }

  func testFailedStatesWithDifferentReasonsAreNotEqual() {
    XCTAssertNotEqual(AgentVMState.failed("a"), AgentVMState.failed("b"))
    XCTAssertEqual(AgentVMState.failed("a"), AgentVMState.failed("a"))
  }

  // MARK: - AgentVMStallLogic (pure)

  func testTerminalStatesAreNeverStalledRegardlessOfElapsedTime() {
    for state: AgentVMState in [.idle, .ready, .failed("x"), .timedOut] {
      let stalled = AgentVMStallLogic.isStalled(
        state: state, since: start, now: start.addingTimeInterval(10_000))
      XCTAssertFalse(stalled, "\(state) is terminal and must never read as stalled")
    }
  }

  func testRunningStateBelowThresholdIsNotStalled() {
    let stalled = AgentVMStallLogic.isStalled(
      state: .polling, since: start,
      now: start.addingTimeInterval(AgentVMStallLogic.stalledAfter - 1))
    XCTAssertFalse(stalled)
  }

  func testRunningStateAtOrAboveThresholdIsStalled() {
    let atThreshold = AgentVMStallLogic.isStalled(
      state: .provisioning, since: start,
      now: start.addingTimeInterval(AgentVMStallLogic.stalledAfter))
    XCTAssertTrue(atThreshold, "stalledAfter is inclusive")

    let pastThreshold = AgentVMStallLogic.isStalled(
      state: .uploading, since: start,
      now: start.addingTimeInterval(AgentVMStallLogic.stalledAfter + 60))
    XCTAssertTrue(pastThreshold)
  }

  func testNegativeClockSkewDoesNotFalselyReportStalled() {
    // `now` earlier than `since` (clock skew) must not crash or go negative.
    let stalled = AgentVMStallLogic.isStalled(
      state: .polling, since: start.addingTimeInterval(100), now: start)
    XCTAssertFalse(stalled)
  }

  // MARK: - AgentVMStatusStore (MainActor)

  @MainActor
  func testTransitionUpdatesStateAndTimestamp() {
    let store = AgentVMStatusStore.shared
    let before = Date()

    store.transition(to: .provisioning, now: before)
    XCTAssertEqual(store.state, .provisioning)
    XCTAssertEqual(store.lastTransitionAt, before)

    let later = before.addingTimeInterval(30)
    store.transition(to: .polling, now: later)
    XCTAssertEqual(store.state, .polling)
    XCTAssertEqual(store.lastTransitionAt, later)
  }

  @MainActor
  func testTransitionToTheSameStateIsANoOpForTheTimestamp() {
    let store = AgentVMStatusStore.shared
    let t1 = Date()
    store.transition(to: .uploading, now: t1)

    let t2 = t1.addingTimeInterval(45)
    store.transition(to: .uploading, now: t2)

    XCTAssertEqual(store.lastTransitionAt, t1, "re-entering the same state must not reset the clock")
  }

  @MainActor
  func testTransitionToFailedWithADifferentReasonIsARealTransition() {
    let store = AgentVMStatusStore.shared
    let t1 = Date()
    store.transition(to: .failed("timeout"), now: t1)

    let t2 = t1.addingTimeInterval(10)
    store.transition(to: .failed("http 500"), now: t2)

    XCTAssertEqual(store.state, .failed("http 500"))
    XCTAssertEqual(store.lastTransitionAt, t2)
  }
}
