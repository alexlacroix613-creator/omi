import Foundation

/// Lifecycle state of the cloud memory-replica pipeline (provision → poll →
/// upload DB) that `AgentVMService` walks through. This is a background
/// database backup, not a task-execution agent — see `AgentVMService`'s header
/// comment and `docs-fork/EXECUTE_REROUTE_DESIGN.md`. Exists so a failure or a
/// stuck poll has somewhere to render in SwiftUI instead of only ever reaching
/// `log(...)`.
enum AgentVMState: Equatable, Sendable {
  case idle
  case provisioning
  case polling
  case uploading
  case ready
  case failed(String)
  case timedOut

  /// True for the states where the pipeline is actively doing something —
  /// the states `AgentVMStallLogic` watches for "sitting too long."
  var isRunning: Bool {
    switch self {
    case .provisioning, .polling, .uploading: return true
    case .idle, .ready, .failed, .timedOut: return false
    }
  }

  /// Short status-row label.
  var label: String {
    switch self {
    case .idle: return "Idle — tasks run on this Mac"
    case .provisioning: return "Provisioning cloud VM…"
    case .polling: return "Waiting for cloud VM…"
    case .uploading: return "Uploading database…"
    case .ready: return "Ready"
    case .failed(let reason): return "Failed — \(reason)"
    case .timedOut: return "Timed out waiting for cloud VM"
    }
  }
}

/// Pure stall-detection for the cloud VM pipeline: a run sitting in a running
/// (non-terminal) state for longer than `stalledAfter` reads as stalled. This
/// is the `AgentVMState` analogue of `AgentStallNarration` — same "quiet too
/// long is suspicious" idea, but driven off discrete pipeline stage
/// transitions instead of a continuous per-tool activity stream, so it
/// compares `now` against `since` (the last transition time) rather than a
/// last-activity stamp.
enum AgentVMStallLogic {
  /// `AgentVMService.pollUntilReady` itself gives up after 30 attempts * 5s =
  /// 150s, so anything still "running" past that is already overdue — pick a
  /// threshold at that boundary rather than inventing a second number.
  static let stalledAfter: TimeInterval = 150

  static func isStalled(state: AgentVMState, since: Date, now: Date) -> Bool {
    guard state.isRunning else { return false }
    return now.timeIntervalSince(since) >= stalledAfter
  }
}

/// Observable status for the cloud memory-replica pipeline, fed by
/// `AgentVMService` at each stage transition. Consumed by a small status row
/// in Settings → Advanced → Troubleshooting so the "ghosting cloud VM" failure
/// mode (DREAM_BACKLOG item 4) has a visible signal instead of being
/// fire-and-forget. This pipeline backs up your memory database for
/// cloud/mobile access — it never runs your tasks (those run locally; see
/// `AgentPillsManager`).
@MainActor
final class AgentVMStatusStore: ObservableObject {
  static let shared = AgentVMStatusStore()

  @Published private(set) var state: AgentVMState = .idle
  @Published private(set) var lastTransitionAt: Date = Date()

  private init() {}

  func transition(to newState: AgentVMState, now: Date = Date()) {
    guard newState != state else { return }
    state = newState
    lastTransitionAt = now
  }

  /// Transition to `.failed` and post a one-shot system notification. The
  /// cloud VM pipeline runs entirely in the background with no floating-bar
  /// equivalent, so without this a failure here would only ever reach
  /// `log(...)` — the exact "silently dies" complaint this item exists to fix.
  func markFailed(_ reason: String) {
    transition(to: .failed(reason))
    NotificationService.shared.sendNotification(
      title: "Cloud sync couldn't start",
      message: "Background database sync failed: \(reason). Local features are unaffected.",
      deliverSystemBanner: true,
      respectFrequency: false
    )
  }

  /// Transition to `.timedOut` and post the same one-shot notification —
  /// covers `pollUntilReady` giving up without ever reaching an explicit
  /// `.failed` (e.g. the VM never got an IP within 30 attempts).
  func markTimedOut() {
    transition(to: .timedOut)
    NotificationService.shared.sendNotification(
      title: "Cloud sync couldn't start",
      message: "The cloud sync VM didn't become ready in time. Local features are unaffected.",
      deliverSystemBanner: true,
      respectFrequency: false
    )
  }
}
