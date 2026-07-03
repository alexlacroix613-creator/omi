import Foundation

/// Pure cross-channel duplicate-text heuristic for the on-device (Parakeet) transcription path.
///
/// The mic-channel music filter (`MusicFilterGate` / `LocalTranscriptionService.isMusicVerdict`,
/// commit 133e28c0b) still lets vocal genres Apple's SoundAnalysis classifier reads as "speech" —
/// rap being the documented case — slip through as real conversation. When that happens, the SAME
/// audio (played out loud through speakers) gets transcribed on BOTH channels: once by the
/// system-audio `LocalTranscriptionService` (the real source), and again by the mic
/// `LocalTranscriptionService` (the mic re-hearing the Mac's own playback). That's an echo, not a
/// conversation.
///
/// This gate keeps a short rolling window of recent SYSTEM-channel segments and, when a MIC segment's
/// text substantially matches one of them within a few seconds, flags the mic segment as an echo so
/// the caller can drop it. The system channel is always the source of truth — `recordSystemSegment`
/// never suppresses anything; only `shouldSuppressMic` can.
///
/// Deliberately pure and stateless-per-call: every method takes the segment's own `start`/`end` (the
/// `LocalTranscriptionService` audio-time offsets, comparable across channels because mic and system
/// start recording within milliseconds of each other and both use the same 10s window) — no wall
/// clock inside, so tests drive it with synthetic timestamps instead of real audio or real time.
struct CrossChannelEchoGate {

  /// One recent system-channel utterance kept around long enough to catch a delayed mic echo.
  private struct Entry {
    let normalizedText: String
    let start: Double
    let end: Double
  }

  private var recentSystemSegments: [Entry] = []

  // MARK: - Tunable constants

  /// How far apart (in audio-time seconds) a mic segment and a system segment can be and still count
  /// as "the same moment", and the pruning horizon for old system entries. Covers window-boundary
  /// drift (both channels flush independently on the same 10s `LocalTranscriptionService` window)
  /// plus the ~0-2s an echo takes to travel speaker → mic → decode. First-pass guess like
  /// `AgentStallNarration`'s thresholds — tune against real dual-channel logs once available.
  static let windowSeconds: Double = 6.0

  /// Token-overlap (Jaccard) similarity a mic segment must reach against a system segment to count as
  /// the same utterance. 0.6 tolerates minor ASR divergence between the two independent decodes of
  /// the same audio (mic picks up room reverb/noise the system tap doesn't) while still requiring most
  /// of the words to match — a real reply that merely echoes a couple of words from a video won't
  /// cross it.
  static let similarityThreshold: Double = 0.6

  /// Segments with fewer tokens than this are never part of a suppression decision, even at 100%
  /// similarity — two one-word utterances ("yeah" / "yeah") are far too likely to coincide by chance
  /// to justify dropping real speech. Applied to BOTH sides of the comparison.
  static let minTokenCount: Int = 4

  // MARK: - Recording (system channel — source of truth, never suppressed)

  /// Remember a system-channel segment so a later mic segment can be checked against it. Prunes
  /// entries already outside the window relative to this new segment's end time.
  mutating func recordSystemSegment(text: String, start: Double, end: Double) {
    recentSystemSegments.removeAll { end - $0.end > Self.windowSeconds }
    recentSystemSegments.append(Entry(normalizedText: Self.normalize(text), start: start, end: end))
  }

  // MARK: - Checking (mic channel — the only side that can be suppressed)

  /// True when `text` (a mic-channel segment spanning `start`...`end`) substantially duplicates a
  /// recent system-channel segment — i.e. it's the mic re-hearing the Mac's own playback, not a real
  /// utterance. Also prunes system entries that have aged out relative to this mic segment.
  mutating func shouldSuppressMic(text: String, start: Double, end: Double) -> Bool {
    recentSystemSegments.removeAll { start - $0.end > Self.windowSeconds }

    let micTokens = Self.tokens(Self.normalize(text))
    guard micTokens.count >= Self.minTokenCount else { return false }

    for entry in recentSystemSegments {
      guard Self.withinWindow(micStart: start, micEnd: end, sysStart: entry.start, sysEnd: entry.end)
      else { continue }
      let sysTokens = Self.tokens(entry.normalizedText)
      guard sysTokens.count >= Self.minTokenCount else { continue }
      if Self.jaccardSimilarity(micTokens, sysTokens) >= Self.similarityThreshold {
        return true
      }
    }
    return false
  }

  // MARK: - Pure helpers (unit-tested directly, no instance state needed)

  /// Time-range gap between a mic and a system segment, in seconds. 0 when the ranges overlap.
  static func timeGap(micStart: Double, micEnd: Double, sysStart: Double, sysEnd: Double) -> Double {
    if micStart <= sysEnd && sysStart <= micEnd { return 0 }
    return micStart > sysEnd ? micStart - sysEnd : sysStart - micEnd
  }

  static func withinWindow(micStart: Double, micEnd: Double, sysStart: Double, sysEnd: Double) -> Bool {
    timeGap(micStart: micStart, micEnd: micEnd, sysStart: sysStart, sysEnd: sysEnd) <= windowSeconds
  }

  /// Lowercase, strip punctuation, collapse whitespace — so "Hey, what's UP?" and "hey whats up"
  /// compare equal. Keeps only letters/numbers as token characters.
  static func normalize(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    var lastWasSpace = true  // also trims a leading separator
    for ch in text.lowercased() {
      if ch.isLetter || ch.isNumber {
        result.append(ch)
        lastWasSpace = false
      } else if !lastWasSpace {
        result.append(" ")
        lastWasSpace = true
      }
    }
    while result.hasSuffix(" ") { result.removeLast() }
    return result
  }

  static func tokens(_ normalizedText: String) -> Set<String> {
    Set(normalizedText.split(separator: " ").map(String.init))
  }

  /// Jaccard similarity: |intersection| / |union| of the two token sets. 0 when either is empty.
  static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    let union = a.union(b).count
    guard union > 0 else { return 0 }
    return Double(a.intersection(b).count) / Double(union)
  }
}
