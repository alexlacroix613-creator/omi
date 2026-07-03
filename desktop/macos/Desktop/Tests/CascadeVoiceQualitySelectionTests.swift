import XCTest

@testable import Omi_Computer

/// Verifies the pure logic for `CascadeVoiceQualitySelection` — DREAM_BACKLOG item 8
/// Pass 3. See docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md §4b/§6. Unlike Pass 1/2's
/// `VoiceEngineSelection` (which engine runs voice at all), this is one level below:
/// once the ChatGPT-subscription cascade engine is running, which TTS backend speaks
/// the reply, and whether that choice can ever cost the user money it didn't expect.
final class CascadeVoiceQualitySelectionTests: XCTestCase {

  // MARK: Quality enum shape

  func testQuality_hasExactlyTheTwoDesignedCases() {
    XCTAssertEqual(
      Set(CascadeVoiceQualitySelection.Quality.allCases),
      [.system, .neural])
  }

  func testQuality_displayNamesAreDistinctAndNonEmpty() {
    let names = CascadeVoiceQualitySelection.Quality.allCases.map(\.displayName)
    XCTAssertEqual(Set(names).count, names.count, "display names must be distinct")
    XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
  }

  func testQuality_idMirrorsRawValue() {
    for quality in CascadeVoiceQualitySelection.Quality.allCases {
      XCTAssertEqual(quality.id, quality.rawValue)
    }
  }

  // MARK: defaultQuality

  /// Cascade defaults to nicer-sounding neural audio — matching the fact that
  /// Pass 2's `speakOneShot` already defaults to an OpenAI voice
  /// (`ShortcutSettings.defaultVoiceID`) for every other floating-bar reply, so
  /// picking `.neural` as the cascade default keeps this engine's out-of-the-box
  /// sound consistent with the rest of the app rather than downgrading it.
  func testDefaultQuality_isNeural() {
    XCTAssertEqual(CascadeVoiceQualitySelection.defaultQuality, .neural)
  }

  // MARK: forcesSystemVoice

  func testForcesSystemVoice_system_isTrue() {
    XCTAssertTrue(CascadeVoiceQualitySelection.forcesSystemVoice(.system))
  }

  func testForcesSystemVoice_neural_isFalse() {
    XCTAssertFalse(CascadeVoiceQualitySelection.forcesSystemVoice(.neural))
  }

  // MARK: costSubtitle — never empty, always distinct per state

  func testCostSubtitle_neverEmpty() {
    for quality in CascadeVoiceQualitySelection.Quality.allCases {
      for isByokActive in [true, false] {
        XCTAssertFalse(
          CascadeVoiceQualitySelection.costSubtitle(
            quality: quality, isByokActive: isByokActive
          ).isEmpty)
      }
    }
  }

  /// `.system` is an unconditional guarantee — the BYOK state must never leak
  /// into its copy, because the whole point of this case is that it's true
  /// regardless of any key configuration.
  func testCostSubtitle_system_sameCopyRegardlessOfByokState() {
    let withByok = CascadeVoiceQualitySelection.costSubtitle(
      quality: .system, isByokActive: true)
    let withoutByok = CascadeVoiceQualitySelection.costSubtitle(
      quality: .system, isByokActive: false)
    XCTAssertEqual(withByok, withoutByok)
    XCTAssertTrue(withByok.localizedCaseInsensitiveContains("free"))
  }

  /// The invariant this whole file exists to protect: `.neural` must say
  /// something DIFFERENT and HONEST when the user's own OpenAI key is actually
  /// on the line, instead of repeating `VoiceEngineSelection
  /// .chatGPTCascadeSubtitle`'s "no new bill" promise unconditionally.
  func testCostSubtitle_neural_differsByByokState() {
    let active = CascadeVoiceQualitySelection.costSubtitle(quality: .neural, isByokActive: true)
    let inactive = CascadeVoiceQualitySelection.costSubtitle(quality: .neural, isByokActive: false)
    XCTAssertNotEqual(active, inactive)
  }

  func testCostSubtitle_neural_byokActive_mentionsTheUsersOwnKey() {
    let subtitle = CascadeVoiceQualitySelection.costSubtitle(quality: .neural, isByokActive: true)
    XCTAssertTrue(subtitle.localizedCaseInsensitiveContains("your"))
    XCTAssertTrue(subtitle.localizedCaseInsensitiveContains("key"))
  }

  func testCostSubtitle_neural_byokInactive_promisesNoBill() {
    let subtitle = CascadeVoiceQualitySelection.costSubtitle(quality: .neural, isByokActive: false)
    XCTAssertTrue(subtitle.localizedCaseInsensitiveContains("no bill"))
  }
}
