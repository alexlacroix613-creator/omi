import Foundation

/// User-selectable presets for how quickly the agent pill escalates a quiet
/// activity stream into "slow" / "stalled" copy. The actual narration lives in
/// `AgentStallNarration`; this type is just a typed, testable, UI-friendly
/// bundle of the two threshold values that drive it.
///
/// Keeping it pure (no `Date()` calls, no singletons) means the same preset
/// can be sourced from user settings, A/B tests, or future "diagnostic mode"
/// toggles without any of them having to know how the pill actually uses
/// the values.
enum StallThresholdPreset: String, CaseIterable, Equatable, Sendable {

  /// Tight thresholds — escalate fast, for users who hate waiting on silence.
  case snappy
  /// Defaults that match `AgentStallNarration`'s current constants.
  case balanced
  /// Loose thresholds — tolerate long quiet stretches (long-running tools,
  /// model "thinking" phases, large tool outputs).
  case patient

  /// The two threshold values a preset exposes. Kept as a small named struct
  /// (rather than a tuple) so call sites can be `Equatable` and the field
  /// order survives any future reorderings of the cases.
  struct Thresholds: Equatable, Sendable {
    /// Gap since last activity that promotes the pill to "still working".
    let slowAfter: TimeInterval
    /// Gap since last activity that promotes the pill to "may have stalled".
    let stalledAfter: TimeInterval
  }

  /// The threshold values for this preset.
  var thresholds: Thresholds {
    switch self {
    case .snappy:
      return Thresholds(slowAfter: 20, stalledAfter: 60)
    case .balanced:
      return Thresholds(slowAfter: 45, stalledAfter: 120)
    case .patient:
      return Thresholds(slowAfter: 90, stalledAfter: 240)
    }
  }

  /// Human-facing label, suitable for a settings picker.
  var displayName: String {
    switch self {
    case .snappy: return "Snappy"
    case .balanced: return "Balanced"
    case .patient: return "Patient"
    }
  }
}
