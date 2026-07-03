import XCTest

@testable import Omi_Computer

/// Verifies the pure cross-channel duplicate-text heuristic that catches rap (and anything else
/// that slips Apple's SoundAnalysis music/speech classifier, `MusicFilterGateTests`'s subject) —
/// when the mic channel re-hears the Mac's own system-audio playback within a few seconds, the mic
/// copy should be dropped as an echo, not kept as a "conversation".
final class CrossChannelEchoGateTests: XCTestCase {

  // MARK: - Exact / near-exact duplicate is suppressed

  func testExactDuplicateWithinWindowIsSuppressed() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(
      text: "This is the real lyrics playing through the speakers right now", start: 10, end: 15)
    XCTAssertTrue(
      gate.shouldSuppressMic(
        text: "This is the real lyrics playing through the speakers right now", start: 11, end: 16))
  }

  func testCaseAndPunctuationInsensitiveDuplicateIsSuppressed() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "yo we outside pulling up tonight", start: 0, end: 4)
    XCTAssertTrue(
      gate.shouldSuppressMic(text: "Yo, we outside — pulling up tonight!!", start: 1, end: 5))
  }

  func testHighOverlapWithMinorAsrDivergenceIsSuppressed() {
    // Mic decode drops one word ("really") vs the system decode — same underlying audio, two
    // independent transcriptions. Still well above the similarity threshold.
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "started from the bottom now we really here", start: 20, end: 26)
    XCTAssertTrue(
      gate.shouldSuppressMic(text: "started from the bottom now we here", start: 20, end: 26))
  }

  // MARK: - Paraphrase / low overlap is kept (real conversation, not an echo)

  func testParaphraseBelowThresholdIsNotSuppressed() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(
      text: "the quarterly numbers came in well above forecast this time", start: 0, end: 5)
    // Same topic, genuinely different sentence — a real reply, not an echo.
    XCTAssertFalse(
      gate.shouldSuppressMic(text: "yeah I saw the report earlier today too", start: 1, end: 5))
  }

  func testUnrelatedMicSpeechIsNotSuppressed() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "breaking news from the capital this morning", start: 0, end: 4)
    XCTAssertFalse(
      gate.shouldSuppressMic(text: "can you grab me a coffee please", start: 1, end: 5))
  }

  // MARK: - Short-utterance guard (real short replies never dropped)

  func testShortMicUtteranceIsNeverSuppressedEvenIfIdentical() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "yeah yeah", start: 0, end: 2)
    // "yeah yeah" is only 2 tokens — below minTokenCount — too likely to coincide by chance.
    XCTAssertFalse(gate.shouldSuppressMic(text: "yeah yeah", start: 0, end: 2))
  }

  func testShortSystemEntryNeverSuppressesALongerMicMatch() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "okay cool", start: 0, end: 2)
    XCTAssertFalse(
      gate.shouldSuppressMic(
        text: "okay cool sounds good to me let's do it", start: 0, end: 3))
  }

  func testMinTokenCountBoundary() {
    XCTAssertEqual(CrossChannelEchoGate.minTokenCount, 4)
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "one two three", start: 0, end: 2)  // 3 tokens, below floor
    XCTAssertFalse(gate.shouldSuppressMic(text: "one two three", start: 0, end: 2))
    gate.recordSystemSegment(text: "one two three four", start: 3, end: 5)  // exactly at floor
    XCTAssertTrue(gate.shouldSuppressMic(text: "one two three four", start: 3, end: 5))
  }

  // MARK: - Window expiry (too far apart in time → not an echo)

  func testMatchOutsideWindowIsNotSuppressed() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "started from the bottom now we here", start: 0, end: 4)
    // 20s later — far outside the few-second echo window — same words, but not an echo anymore.
    XCTAssertFalse(
      gate.shouldSuppressMic(text: "started from the bottom now we here", start: 24, end: 28))
  }

  func testMatchAtWindowBoundaryIsSuppressed() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "started from the bottom now we here", start: 0, end: 4)
    let boundary = CrossChannelEchoGate.windowSeconds
    // mic starts exactly `windowSeconds` after the system segment ends — inclusive boundary.
    XCTAssertTrue(
      gate.shouldSuppressMic(
        text: "started from the bottom now we here", start: 4 + boundary, end: 8 + boundary))
  }

  func testMatchJustPastWindowBoundaryIsNotSuppressed() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "started from the bottom now we here", start: 0, end: 4)
    let boundary = CrossChannelEchoGate.windowSeconds
    XCTAssertFalse(
      gate.shouldSuppressMic(
        text: "started from the bottom now we here", start: 4 + boundary + 0.01,
        end: 8 + boundary + 0.01))
  }

  func testStalePastSegmentIsPrunedAndNoLongerMatches() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "started from the bottom now we here", start: 0, end: 4)
    // Advance the gate well past the window with an unrelated system segment first (this also
    // exercises the pruning path inside recordSystemSegment).
    gate.recordSystemSegment(text: "completely different unrelated broadcast content", start: 40, end: 44)
    XCTAssertFalse(
      gate.shouldSuppressMic(text: "started from the bottom now we here", start: 41, end: 45))
  }

  // MARK: - Multiple system segments are all tracked, not just the latest

  func testEarlierOfTwoRecentSystemSegmentsStillMatches() {
    var gate = CrossChannelEchoGate()
    gate.recordSystemSegment(text: "started from the bottom now we here", start: 0, end: 4)
    gate.recordSystemSegment(text: "totally unrelated second line of the song here", start: 4, end: 8)
    // Mic echoes the FIRST system line, still within window of it.
    XCTAssertTrue(
      gate.shouldSuppressMic(text: "started from the bottom now we here", start: 1, end: 5))
  }

  // MARK: - Overlapping time ranges (gap == 0) always count as within window

  func testOverlappingRangesHaveZeroGap() {
    XCTAssertEqual(
      CrossChannelEchoGate.timeGap(micStart: 2, micEnd: 6, sysStart: 4, sysEnd: 9), 0)
    XCTAssertTrue(
      CrossChannelEchoGate.withinWindow(micStart: 2, micEnd: 6, sysStart: 4, sysEnd: 9))
  }

  func testDisjointRangesGapIsDirectional() {
    // mic strictly after sys
    XCTAssertEqual(
      CrossChannelEchoGate.timeGap(micStart: 10, micEnd: 12, sysStart: 0, sysEnd: 4), 6, accuracy: 0.001)
    // mic strictly before sys
    XCTAssertEqual(
      CrossChannelEchoGate.timeGap(micStart: 0, micEnd: 2, sysStart: 10, sysEnd: 14), 8, accuracy: 0.001)
  }

  // MARK: - normalize()

  func testNormalizeLowercasesStripsPunctuationAndCollapsesWhitespace() {
    XCTAssertEqual(
      CrossChannelEchoGate.normalize("Hey, what's   UP?!"), "hey what s up")
  }

  func testNormalizeEmptyStringStaysEmpty() {
    XCTAssertEqual(CrossChannelEchoGate.normalize(""), "")
    XCTAssertEqual(CrossChannelEchoGate.normalize("   !!!   "), "")
  }

  // MARK: - tokens()

  func testTokensSplitsOnWhitespace() {
    XCTAssertEqual(CrossChannelEchoGate.tokens("hey what s up"), ["hey", "what", "s", "up"])
  }

  func testTokensDedupesRepeatedWords() {
    XCTAssertEqual(CrossChannelEchoGate.tokens("go go go now"), ["go", "now"])
  }

  // MARK: - jaccardSimilarity()

  func testJaccardIdenticalSetsIsOne() {
    let a: Set<String> = ["a", "b", "c"]
    XCTAssertEqual(CrossChannelEchoGate.jaccardSimilarity(a, a), 1.0)
  }

  func testJaccardDisjointSetsIsZero() {
    XCTAssertEqual(
      CrossChannelEchoGate.jaccardSimilarity(["a", "b"], ["c", "d"]), 0.0)
  }

  func testJaccardPartialOverlap() {
    // intersection {b, c} = 2, union {a,b,c,d} = 4 → 0.5
    XCTAssertEqual(
      CrossChannelEchoGate.jaccardSimilarity(["a", "b", "c"], ["b", "c", "d"]), 0.5, accuracy: 0.001)
  }

  func testJaccardEitherEmptyIsZero() {
    XCTAssertEqual(CrossChannelEchoGate.jaccardSimilarity([], ["a"]), 0.0)
    XCTAssertEqual(CrossChannelEchoGate.jaccardSimilarity(["a"], []), 0.0)
    XCTAssertEqual(CrossChannelEchoGate.jaccardSimilarity([], []), 0.0)
  }

  // MARK: - Threshold constant sanity

  func testSimilarityThresholdConstant() {
    XCTAssertEqual(CrossChannelEchoGate.similarityThreshold, 0.6, accuracy: 0.001)
  }

  func testWindowSecondsConstant() {
    XCTAssertEqual(CrossChannelEchoGate.windowSeconds, 6.0, accuracy: 0.001)
  }
}
