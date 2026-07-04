import XCTest

@testable import Omi_Computer

final class PrivacyRedactionPolicyTests: XCTestCase {

  // MARK: - .off

  func testOffReturnsTextUnchanged() {
    let input = "Email me at alex@example.com or call 555-123-4567."
    XCTAssertEqual(
      PrivacyRedactionPolicy.redact(input, level: .off),
      input
    )
  }

  func testOffOnEmptyStringReturnsEmptyString() {
    XCTAssertEqual(
      PrivacyRedactionPolicy.redact("", level: .off),
      ""
    )
  }

  // MARK: - .emails

  func testEmailsReplacesSingleAddress() {
    let out = PrivacyRedactionPolicy.redact(
      "ping alex@example.com please",
      level: .emails
    )
    XCTAssertEqual(out, "ping [email] please")
  }

  func testEmailsReplacesMultipleAddresses() {
    let out = PrivacyRedactionPolicy.redact(
      "From a@b.io to c.d+tag@sub.example.co and also root@localhost.dev.",
      level: .emails
    )
    XCTAssertEqual(
      out,
      "From [email] to [email] and also [email]."
    )
  }

  func testEmailsLeavesPhonesAndDigitsAlone() {
    let input = "Call 555-123-4567, ref 1234567."
    XCTAssertEqual(
      PrivacyRedactionPolicy.redact(input, level: .emails),
      input
    )
  }

  // MARK: - .aggressive

  func testAggressiveRedactsPhoneNumber() {
    let out = PrivacyRedactionPolicy.redact(
      "Call 555-123-4567 today.",
      level: .aggressive
    )
    XCTAssertEqual(out, "Call [redacted] today.")
  }

  func testAggressiveRedactsLongDigitRun() {
    let out = PrivacyRedactionPolicy.redact(
      "Order ref 1234567890 shipped.",
      level: .aggressive
    )
    XCTAssertEqual(out, "Order ref [redacted] shipped.")
  }

  func testAggressiveRedactsEmailsAsEmailToken() {
    let out = PrivacyRedactionPolicy.redact(
      "Send to alex@example.com.",
      level: .aggressive
    )
    // Email replacement uses its own token, even in aggressive mode.
    XCTAssertEqual(out, "Send to [email].")
  }

  func testAggressiveHandlesPhoneEmailAndDigitsInOnePass() {
    let out = PrivacyRedactionPolicy.redact(
      "Email alex@example.com or call (555) 123-4567, ref 1234567.",
      level: .aggressive
    )
    XCTAssertEqual(
      out,
      "Email [email] or call [redacted], ref [redacted]."
    )
  }

  // MARK: - Clean input at every level

  func testCleanSentenceUnchangedAtEveryLevel() {
    let input = "The quick brown fox jumps over the lazy dog."
    XCTAssertEqual(
      PrivacyRedactionPolicy.redact(input, level: .off),
      input
    )
    XCTAssertEqual(
      PrivacyRedactionPolicy.redact(input, level: .emails),
      input
    )
    XCTAssertEqual(
      PrivacyRedactionPolicy.redact(input, level: .aggressive),
      input
    )
  }

  func testShortDigitRunIsNotRedactedAtAggressive() {
    // 6 digits — under the 7-digit threshold — should be left alone even
    // at .aggressive, so things like "Item 123456 in stock" survive.
    let input = "Item 123456 is in stock."
    XCTAssertEqual(
      PrivacyRedactionPolicy.redact(input, level: .aggressive),
      input
    )
  }
}
