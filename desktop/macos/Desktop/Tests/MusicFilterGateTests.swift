import XCTest

@testable import Omi_Computer

/// Verifies the pure decision rule behind the "Filter music from conversations" feature — the
/// SoundAnalysis music/speech tally verdict that decides whether an on-device Parakeet window is
/// music (skipped) or speech (transcribed). This is the seam that keeps songs played out loud, TV,
/// and videos from becoming conversations while never dropping a spoken window. Kept as a pure
/// function so the threshold is testable without running SoundAnalysis on real audio.
final class MusicFilterGateTests: XCTestCase {

  // MARK: Music is dropped

  func testMusicDominantWindowIsMusic() {
    // Music strictly outnumbers speech and is well over a third of the window → music.
    XCTAssertTrue(
      LocalTranscriptionService.isMusicVerdict(frames: 10, musicFrames: 8, speechFrames: 1))
  }

  func testPureMusicWindowIsMusic() {
    XCTAssertTrue(
      LocalTranscriptionService.isMusicVerdict(frames: 6, musicFrames: 6, speechFrames: 0))
  }

  // MARK: Speech / calls are kept

  func testSpeechDominantWindowIsNotMusic() {
    // A spoken call: speech frames dominate → never gated (the other party is kept).
    XCTAssertFalse(
      LocalTranscriptionService.isMusicVerdict(frames: 10, musicFrames: 2, speechFrames: 7))
  }

  func testTiedFramesAreNotMusic() {
    // Ties do not count as music — must STRICTLY outnumber speech, so ambiguous windows are kept.
    XCTAssertFalse(
      LocalTranscriptionService.isMusicVerdict(frames: 8, musicFrames: 4, speechFrames: 4))
  }

  func testSparseMusicBelowShareThresholdIsNotMusic() {
    // Music leads speech but is a small share of the (mostly-unknown) window → not confident
    // enough to drop. musicFrames*3 (6) < frames (10).
    XCTAssertFalse(
      LocalTranscriptionService.isMusicVerdict(frames: 10, musicFrames: 2, speechFrames: 1))
  }

  func testExactlyOneThirdShareIsMusic() {
    // Boundary: musicFrames*3 == frames (share is exactly one third) and music leads speech → music.
    XCTAssertTrue(
      LocalTranscriptionService.isMusicVerdict(frames: 9, musicFrames: 3, speechFrames: 2))
  }

  // MARK: Degenerate input

  func testNoFramesIsNotMusic() {
    // No classified frames (e.g. a sub-second tail) fails open — never dropped.
    XCTAssertFalse(
      LocalTranscriptionService.isMusicVerdict(frames: 0, musicFrames: 0, speechFrames: 0))
  }
}
