import XCTest

@testable import Omi_Computer

/// Verifies the pure Pass 1 logic for `VoiceEngineSelection` — the seam Pass 2's
/// `SubscriptionCascadeCoordinator` and the Voice settings UI will both depend on.
/// See docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md §4b/§6.
final class VoiceEngineSelectionTests: XCTestCase {

  // MARK: Engine enum shape

  func testEngine_hasExactlyTheTwoDesignedCases() {
    XCTAssertEqual(
      Set(VoiceEngineSelection.Engine.allCases),
      [.nativeRealtimeBYOK, .chatGPTSubscriptionCascade])
  }

  func testEngine_displayNamesAreDistinctAndNonEmpty() {
    let names = VoiceEngineSelection.Engine.allCases.map(\.displayName)
    XCTAssertEqual(Set(names).count, names.count, "display names must be distinct")
    XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
  }

  func testEngine_idMirrorsRawValue() {
    for engine in VoiceEngineSelection.Engine.allCases {
      XCTAssertEqual(engine.id, engine.rawValue)
    }
  }

  // MARK: isAvailable

  func testIsAvailable_nativeRealtimeBYOK_alwaysTrue() {
    XCTAssertTrue(
      VoiceEngineSelection.isAvailable(.nativeRealtimeBYOK, chatGPTConnected: true))
    XCTAssertTrue(
      VoiceEngineSelection.isAvailable(.nativeRealtimeBYOK, chatGPTConnected: false))
  }

  /// Pass 1's central guardrail: connecting ChatGPT must NOT flip the cascade
  /// engine to available — no coordinator exists yet to actually run it.
  func testIsAvailable_chatGPTSubscriptionCascade_alwaysFalseInPass1() {
    XCTAssertFalse(
      VoiceEngineSelection.isAvailable(.chatGPTSubscriptionCascade, chatGPTConnected: true))
    XCTAssertFalse(
      VoiceEngineSelection.isAvailable(.chatGPTSubscriptionCascade, chatGPTConnected: false))
  }

  // MARK: chatGPTCascadeSubtitle

  func testChatGPTCascadeSubtitle_mentionsComingSoonRegardlessOfConnection() {
    XCTAssertTrue(
      VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: true)
        .localizedCaseInsensitiveContains("coming soon"))
    XCTAssertTrue(
      VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: false)
        .localizedCaseInsensitiveContains("coming soon"))
  }

  func testChatGPTCascadeSubtitle_differsByConnectionState() {
    let connected = VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: true)
    let disconnected = VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: false)
    XCTAssertNotEqual(connected, disconnected)
    XCTAssertTrue(disconnected.localizedCaseInsensitiveContains("connect"))
  }

  func testChatGPTCascadeSubtitle_neverImpliesAnExtraOpenAIBill() {
    for connected in [true, false] {
      let subtitle = VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: connected)
      XCTAssertTrue(subtitle.localizedCaseInsensitiveContains("no new"))
    }
  }

  // MARK: effectiveEngine

  func testEffectiveEngine_nativeSelectionStaysNative() {
    for chatGPTConnected in [true, false] {
      XCTAssertEqual(
        VoiceEngineSelection.effectiveEngine(
          storedSelection: .nativeRealtimeBYOK, chatGPTConnected: chatGPTConnected),
        .nativeRealtimeBYOK)
    }
  }

  /// Even a stored cascade selection (e.g. a stale UserDefaults value from a
  /// future build, or manual tampering) must fall back to native — Pass 1 has
  /// no coordinator to honor that selection with.
  func testEffectiveEngine_cascadeSelectionFallsBackToNativeEvenWhenConnected() {
    XCTAssertEqual(
      VoiceEngineSelection.effectiveEngine(
        storedSelection: .chatGPTSubscriptionCascade, chatGPTConnected: true),
      .nativeRealtimeBYOK)
    XCTAssertEqual(
      VoiceEngineSelection.effectiveEngine(
        storedSelection: .chatGPTSubscriptionCascade, chatGPTConnected: false),
      .nativeRealtimeBYOK)
  }
}
