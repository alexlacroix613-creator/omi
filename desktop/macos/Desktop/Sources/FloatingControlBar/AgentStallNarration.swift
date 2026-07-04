import Foundation

/// Pure, wall-clock-free narration of what a running agent pill is doing right
/// now, so a background agent never renders as a frozen "Working…" with no
/// sense of time. Given when the pill started and when it last emitted any
/// activity, `narrate` returns a short live status ("Running · 2m") and, once
/// forward progress stalls, escalates to a "still working" / "may have stalled"
/// hint instead of silence.
///
/// This is the pill-level companion to `StallDetector` (which drives the
/// in-chat per-tool `.slow` / `.stalled` annotations). It is deliberately
/// pure logic — `now` is passed in on every call — so tests drive it instantly
/// and the UI wraps it in a `TimelineView(.periodic(...))` that re-evaluates
/// every few seconds while a pill is active.
enum AgentStallNarration {

  /// How stale the pill's last activity update is, relative to `now`.
  enum Level: Equatable, Sendable {
    /// Actively streaming or recently updated — normal running.
    case active
    /// No update for a while; likely still working but quiet.
    case slow
    /// No update for a long while; surface a "may have stalled" warning.
    case stalled
  }

  struct Result: Equatable, Sendable {
    /// Escalation level driving the tint/icon in the UI.
    let level: Level
    /// Total wall-clock since the pill started, e.g. "2m", "45s", "1h3m".
    let elapsedLabel: String
    /// Time since the last activity update, e.g. "1m".
    let sinceUpdateLabel: String
    /// The status subtitle to render, already composed for the given level.
    let text: String
  }

  /// The user's chosen escalation pace. Defaults to `.balanced`, whose
  /// thresholds are exactly the historical constants (45 / 120), so an
  /// un-set preset reproduces the old behavior byte-for-byte.
  ///
  /// ponytail: reads UserDefaults directly (the @AppStorage("stallThresholdPreset")
  /// backing store) so the pill's `TimelineView` re-eval picks up a changed
  /// preset live, with no signature change to `narrate` or its call sites.
  static var currentPreset: StallThresholdPreset {
    let raw = UserDefaults.standard.string(forKey: "stallThresholdPreset") ?? ""
    return StallThresholdPreset(rawValue: raw) ?? .balanced
  }

  /// A gap this long since the last activity update promotes to `.slow`.
  static var slowAfter: TimeInterval { currentPreset.thresholds.slowAfter }
  /// A gap this long since the last activity update promotes to `.stalled`.
  static var stalledAfter: TimeInterval { currentPreset.thresholds.stalledAfter }

  /// Narrate an active pill. Returns `nil` for finished pills (`isActive ==
  /// false`) so callers keep their normal terminal label.
  ///
  /// - Parameters:
  ///   - isActive: true iff the pill is queued / starting / running.
  ///   - startedAt: when the pill was created.
  ///   - lastActivityAt: when the pill last changed its activity text.
  ///   - now: the current time (injected for testability).
  static func narrate(
    isActive: Bool,
    startedAt: Date,
    lastActivityAt: Date,
    now: Date
  ) -> Result? {
    guard isActive else { return nil }

    let elapsed = max(0, now.timeIntervalSince(startedAt))
    let sinceUpdate = max(0, now.timeIntervalSince(lastActivityAt))
    let elapsedLabel = shortDuration(elapsed)
    let sinceUpdateLabel = shortDuration(sinceUpdate)

    let level: Level
    let text: String
    if sinceUpdate >= stalledAfter {
      level = .stalled
      text = "No update for \(sinceUpdateLabel) — may have stalled"
    } else if sinceUpdate >= slowAfter {
      level = .slow
      text = "Still working — quiet for \(sinceUpdateLabel)"
    } else {
      level = .active
      text = ""
    }

    return Result(
      level: level,
      elapsedLabel: elapsedLabel,
      sinceUpdateLabel: sinceUpdateLabel,
      text: text
    )
  }

  /// Compact human duration: "8s", "2m", "1h3m". Rounds down; sub-second reads
  /// as "0s".
  static func shortDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    if total < 60 { return "\(total)s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remMinutes = minutes % 60
    return remMinutes == 0 ? "\(hours)h" : "\(hours)h\(remMinutes)m"
  }
}
