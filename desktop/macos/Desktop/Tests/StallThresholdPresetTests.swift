import XCTest

@testable import Omi_Computer

final class StallThresholdPresetTests: XCTestCase {

  func testSnappyThresholds() {
    XCTAssertEqual(
      StallThresholdPreset.snappy.thresholds,
      StallThresholdPreset.Thresholds(slowAfter: 20, stalledAfter: 60)
    )
  }

  func testBalancedThresholds() {
    XCTAssertEqual(
      StallThresholdPreset.balanced.thresholds,
      StallThresholdPreset.Thresholds(slowAfter: 45, stalledAfter: 120)
    )
  }

  func testPatientThresholds() {
    XCTAssertEqual(
      StallThresholdPreset.patient.thresholds,
      StallThresholdPreset.Thresholds(slowAfter: 90, stalledAfter: 240)
    )
  }

  func testSlowAfterIsAlwaysLessThanStalledAfter() {
    for preset in StallThresholdPreset.allCases {
      let t = preset.thresholds
      XCTAssertLessThan(
        t.slowAfter, t.stalledAfter,
        "\(preset.rawValue) must have slowAfter < stalledAfter"
      )
    }
  }

  func testThresholdsAreMonotonicallyLooser() {
    let snappy = StallThresholdPreset.snappy.thresholds
    let balanced = StallThresholdPreset.balanced.thresholds
    let patient = StallThresholdPreset.patient.thresholds

    XCTAssertLessThan(snappy.slowAfter, balanced.slowAfter)
    XCTAssertLessThan(balanced.slowAfter, patient.slowAfter)

    XCTAssertLessThan(snappy.stalledAfter, balanced.stalledAfter)
    XCTAssertLessThan(balanced.stalledAfter, patient.stalledAfter)
  }

  func testCaseIterableHasExactlyThreePresets() {
    XCTAssertEqual(StallThresholdPreset.allCases.count, 3)
    XCTAssertEqual(
      StallThresholdPreset.allCases,
      [.snappy, .balanced, .patient]
    )
  }

  func testDisplayNameMapping() {
    XCTAssertEqual(StallThresholdPreset.snappy.displayName, "Snappy")
    XCTAssertEqual(StallThresholdPreset.balanced.displayName, "Balanced")
    XCTAssertEqual(StallThresholdPreset.patient.displayName, "Patient")
  }
}
