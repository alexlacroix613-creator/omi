import XCTest

@testable import Omi_Computer

/// Verifies the pure logic for `VoiceEngineSelection` — the seam
/// `SubscriptionCascadeCoordinator` and the Voice settings UI both depend on.
/// Updated for Pass 2: the cascade engine now tracks real ChatGPT connection
/// state instead of being hard-coded unavailable. See
/// docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md §4b/§6.
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

  /// Pass 2's central guardrail: the cascade engine is available if and only
  /// if ChatGPT is connected — `SubscriptionCascadeCoordinator` exists now, so
  /// this seam must actually gate on the real signal instead of hard-coding
  /// unavailable.
  func testIsAvailable_chatGPTSubscriptionCascade_tracksChatGPTConnection() {
    XCTAssertTrue(
      VoiceEngineSelection.isAvailable(.chatGPTSubscriptionCascade, chatGPTConnected: true))
    XCTAssertFalse(
      VoiceEngineSelection.isAvailable(.chatGPTSubscriptionCascade, chatGPTConnected: false))
  }

  // MARK: chatGPTCascadeSubtitle

  func testChatGPTCascadeSubtitle_neverEmpty() {
    XCTAssertFalse(VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: true).isEmpty)
    XCTAssertFalse(VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: false).isEmpty)
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

  /// A stored cascade selection is honored once ChatGPT is connected — that's
  /// the whole point of Pass 2 shipping `SubscriptionCascadeCoordinator`.
  func testEffectiveEngine_cascadeSelectionHonoredWhenConnected() {
    XCTAssertEqual(
      VoiceEngineSelection.effectiveEngine(
        storedSelection: .chatGPTSubscriptionCascade, chatGPTConnected: true),
      .chatGPTSubscriptionCascade)
  }

  /// A stored cascade selection with NO ChatGPT connection (disconnected
  /// after selecting, or a stale/tampered UserDefaults value) must fall back
  /// to native — there is nothing to run the loop with.
  func testEffectiveEngine_cascadeSelectionFallsBackToNativeWhenDisconnected() {
    XCTAssertEqual(
      VoiceEngineSelection.effectiveEngine(
        storedSelection: .chatGPTSubscriptionCascade, chatGPTConnected: false),
      .nativeRealtimeBYOK)
  }
}
