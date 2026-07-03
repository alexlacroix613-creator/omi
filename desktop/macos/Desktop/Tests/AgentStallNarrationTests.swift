import XCTest

@testable import Omi_Computer

final class AgentStallNarrationTests: XCTestCase {

  private let start = Date(timeIntervalSince1970: 1_000_000)

  func testFinishedPillReturnsNil() {
    let result = AgentStallNarration.narrate(
      isActive: false,
      startedAt: start,
      lastActivityAt: start,
      now: start.addingTimeInterval(300)
    )
    XCTAssertNil(result, "Finished pills keep their terminal label — no narration")
  }

  func testFreshActivityIsActiveLevelWithNoStallText() {
    let result = AgentStallNarration.narrate(
      isActive: true,
      startedAt: start,
      lastActivityAt: start.addingTimeInterval(20),
      now: start.addingTimeInterval(30)
    )
    XCTAssertEqual(result?.level, .active)
    XCTAssertEqual(result?.text, "")
    XCTAssertEqual(result?.elapsedLabel, "30s")
    XCTAssertEqual(result?.sinceUpdateLabel, "10s")
  }

  func testPromotesToSlowAfterThreshold() {
    // 50s since last update — past slowAfter (45s), before stalledAfter (120s).
    let result = AgentStallNarration.narrate(
      isActive: true,
      startedAt: start,
      lastActivityAt: start,
      now: start.addingTimeInterval(50)
    )
    XCTAssertEqual(result?.level, .slow)
    XCTAssertEqual(result?.sinceUpdateLabel, "50s")
    XCTAssertTrue(result?.text.contains("Still working") == true)
  }

  func testPromotesToStalledAfterThreshold() {
    // 130s since last update — past stalledAfter (120s).
    let result = AgentStallNarration.narrate(
      isActive: true,
      startedAt: start,
      lastActivityAt: start,
      now: start.addingTimeInterval(130)
    )
    XCTAssertEqual(result?.level, .stalled)
    XCTAssertTrue(result?.text.contains("may have stalled") == true)
  }

  func testSlowIsDrivenBySinceUpdateNotTotalElapsed() {
    // Pill ran 10 minutes total but updated 5s ago — still active, not slow.
    let result = AgentStallNarration.narrate(
      isActive: true,
      startedAt: start,
      lastActivityAt: start.addingTimeInterval(595),
      now: start.addingTimeInterval(600)
    )
    XCTAssertEqual(result?.level, .active)
    XCTAssertEqual(result?.elapsedLabel, "10m")
  }

  func testExactThresholdBoundariesPromote() {
    let slow = AgentStallNarration.narrate(
      isActive: true, startedAt: start, lastActivityAt: start,
      now: start.addingTimeInterval(AgentStallNarration.slowAfter))
    XCTAssertEqual(slow?.level, .slow, "slowAfter is inclusive")

    let stalled = AgentStallNarration.narrate(
      isActive: true, startedAt: start, lastActivityAt: start,
      now: start.addingTimeInterval(AgentStallNarration.stalledAfter))
    XCTAssertEqual(stalled?.level, .stalled, "stalledAfter is inclusive")
  }

  func testNegativeClockSkewClampsToZero() {
    // now earlier than timestamps (clock skew) must not crash or go negative.
    let result = AgentStallNarration.narrate(
      isActive: true,
      startedAt: start.addingTimeInterval(100),
      lastActivityAt: start.addingTimeInterval(100),
      now: start
    )
    XCTAssertEqual(result?.level, .active)
    XCTAssertEqual(result?.elapsedLabel, "0s")
    XCTAssertEqual(result?.sinceUpdateLabel, "0s")
  }

  func testShortDurationFormatting() {
    XCTAssertEqual(AgentStallNarration.shortDuration(0), "0s")
    XCTAssertEqual(AgentStallNarration.shortDuration(8), "8s")
    XCTAssertEqual(AgentStallNarration.shortDuration(59), "59s")
    XCTAssertEqual(AgentStallNarration.shortDuration(60), "1m")
    XCTAssertEqual(AgentStallNarration.shortDuration(125), "2m")
    XCTAssertEqual(AgentStallNarration.shortDuration(3600), "1h")
    XCTAssertEqual(AgentStallNarration.shortDuration(3660), "1h1m")
    XCTAssertEqual(AgentStallNarration.shortDuration(7380), "2h3m")
  }
}
