import XCTest

@testable import Omi_Computer

/// Verifies the pure selection logic behind the two voice controls (Voice Model
/// bring-your-own-key, and the Transcription/STT picker). This is the seam the
/// Settings UI drives, so it must round-trip state exactly and mirror the runtime
/// key hooks (RealtimeHubProvider.byokProvider / the forceCloudSTT flag).
final class VoiceProviderSelectionTests: XCTestCase {

  // MARK: Transcription choice derivation

  func testTranscriptionChoice_onDeviceWhenNotForcingCloud() {
    XCTAssertEqual(
      VoiceProviderSelection.transcriptionChoice(forceCloud: false, hasDeepgramKey: false),
      .onDevice)
    // A stored key is irrelevant while on-device (it is unused off the cloud path).
    XCTAssertEqual(
      VoiceProviderSelection.transcriptionChoice(forceCloud: false, hasDeepgramKey: true),
      .onDevice)
  }

  func testTranscriptionChoice_omiCloudWhenForcedWithoutKey() {
    XCTAssertEqual(
      VoiceProviderSelection.transcriptionChoice(forceCloud: true, hasDeepgramKey: false),
      .omiCloud)
  }

  func testTranscriptionChoice_deepgramBYOWhenForcedWithKey() {
    XCTAssertEqual(
      VoiceProviderSelection.transcriptionChoice(forceCloud: true, hasDeepgramKey: true),
      .deepgramBYO)
  }

  // MARK: Transcription state round-trips

  func testTranscriptionState_roundTripsForEveryChoice() {
    for choice in VoiceProviderSelection.TranscriptionChoice.allCases {
      let state = VoiceProviderSelection.transcriptionState(for: choice)
      // After applying the state, deriving the choice again must return the same choice.
      // For non-BYO choices the key is cleared, so hasDeepgramKey becomes false.
      let hasKeyAfter = choice == .deepgramBYO
      let derived = VoiceProviderSelection.transcriptionChoice(
        forceCloud: state.forceCloud, hasDeepgramKey: hasKeyAfter && !state.clearDeepgramKey)
      XCTAssertEqual(derived, choice, "choice \(choice.rawValue) did not round-trip")
    }
  }

  func testTranscriptionState_onlyOmiCloudClearsKey() {
    XCTAssertFalse(VoiceProviderSelection.transcriptionState(for: .onDevice).clearDeepgramKey)
    XCTAssertTrue(VoiceProviderSelection.transcriptionState(for: .omiCloud).clearDeepgramKey)
    XCTAssertFalse(VoiceProviderSelection.transcriptionState(for: .deepgramBYO).clearDeepgramKey)
    // On-device is the only non-cloud state.
    XCTAssertFalse(VoiceProviderSelection.transcriptionState(for: .onDevice).forceCloud)
    XCTAssertTrue(VoiceProviderSelection.transcriptionState(for: .omiCloud).forceCloud)
    XCTAssertTrue(VoiceProviderSelection.transcriptionState(for: .deepgramBYO).forceCloud)
  }

  // MARK: Realtime voice key hooks

  func testRealtimeUsesOwnKey_reflectsKeyPresence() {
    XCTAssertTrue(VoiceProviderSelection.realtimeUsesOwnKey(hasProviderKey: true))
    XCTAssertFalse(VoiceProviderSelection.realtimeUsesOwnKey(hasProviderKey: false))
  }

  /// The realtime key hook must match RealtimeHubProvider.byokProvider: the GPT
  /// realtime model reads the OpenAI key; the Gemini live model reads the Gemini key.
  func testRealtimeKeyStorageKey_mapsModelToProviderKey() {
    XCTAssertEqual(
      VoiceProviderSelection.realtimeKeyStorageKey(forModel: "gptRealtime2"),
      BYOKProvider.openai.storageKey)
    XCTAssertEqual(
      VoiceProviderSelection.realtimeKeyStorageKey(forModel: "geminiFlashLive"),
      BYOKProvider.gemini.storageKey)
    // Any Gemini-family default (including an unresolved value) falls to the Gemini key.
    XCTAssertEqual(
      VoiceProviderSelection.realtimeKeyStorageKey(forModel: "somethingElse"),
      BYOKProvider.gemini.storageKey)
  }

  func testRealtimeProviderDisplayName_matchesModel() {
    XCTAssertEqual(
      VoiceProviderSelection.realtimeProviderDisplayName(forModel: "gptRealtime2"), "OpenAI")
    XCTAssertEqual(
      VoiceProviderSelection.realtimeProviderDisplayName(forModel: "geminiFlashLive"),
      "Google Gemini")
  }
}
