import Foundation

/// Pure routing of a `Workload` to the cheapest provider we can actually use
/// right now, given the user's live connection state. Used by the
/// voice/pill/Execute paths to decide which model to hit — and to surface a
/// plain-English reason so the UI can show *why* this pick was made (e.g. when
/// we quietly downgrade from a paid subscription to OpenRouter free because
/// the user is not signed in to Claude).
///
/// Deliberately pure logic — no `Date()`, no network, no side effects. The
/// caller hands us a snapshot of `Availability` and gets back a `Route`.
enum CostAwareModelRouter {

  /// Coarse work class — drives which model family we aim for.
  enum Workload: Equatable, Sendable {
    /// Trivial / cheap: a small free OpenRouter model is fine.
    case cheap
    /// Mixed tasks with some reasoning: prefer a connected subscription.
    case balanced
    /// Long-context, high-quality: prefer the strongest connected model.
    case heavy
  }

  /// Snapshot of what is connected *right now*. The caller is responsible
  /// for keeping this in sync with the real auth state — we do not probe.
  struct Availability: Equatable, Sendable {
    let claudeConnected: Bool
    let chatGPTConnected: Bool
    let openRouterKeyPresent: Bool
  }

  /// The chosen model + a human sentence explaining the pick.
  struct Route: Equatable, Sendable {
    let modelIdentifier: String
    let providerLabel: String
    let reason: String
  }

  /// Final fallback used when no provider is reachable. Runs locally — does
  /// not need any subscription or API key.
  static let onDeviceRoute = Route(
    modelIdentifier: "on-device",
    providerLabel: "On-device",
    reason: "No provider connected — using the local default"
  )

  /// Pick a `Route` for the given workload given the current `Availability`.
  ///
  /// Order of preference per workload:
  /// - `.cheap`    → OpenRouter free if a key is present, else on-device.
  /// - `.balanced` → Claude if connected, else ChatGPT if connected, else
  ///                 OpenRouter free if a key is present, else on-device.
  /// - `.heavy`    → Claude if connected, else ChatGPT if connected, else
  ///                 OpenRouter free if a key is present, else on-device.
  static func route(workload: Workload, availability: Availability) -> Route {
    switch workload {
    case .cheap:
      if availability.openRouterKeyPresent {
        return Route(
          modelIdentifier: "qwen/qwen3-coder:free",
          providerLabel: "OpenRouter (free)",
          reason: "Cheap workload — using the free OpenRouter model"
        )
      }
      return onDeviceRoute

    case .balanced:
      if availability.claudeConnected {
        return Route(
          modelIdentifier: "claude-sonnet",
          providerLabel: "Claude",
          reason: "Balanced workload — using your Claude subscription"
        )
      }
      if availability.chatGPTConnected {
        return Route(
          modelIdentifier: "gpt-5.5",
          providerLabel: "ChatGPT",
          reason: "Claude not connected — falling back to your ChatGPT subscription"
        )
      }
      if availability.openRouterKeyPresent {
        return Route(
          modelIdentifier: "qwen/qwen3-coder:free",
          providerLabel: "OpenRouter (free)",
          reason: "No subscription connected — using the free OpenRouter model"
        )
      }
      return onDeviceRoute

    case .heavy:
      if availability.claudeConnected {
        return Route(
          modelIdentifier: "claude-opus",
          providerLabel: "Claude",
          reason: "Heavy workload — using Claude Opus for the best quality"
        )
      }
      if availability.chatGPTConnected {
        return Route(
          modelIdentifier: "gpt-5.5",
          providerLabel: "ChatGPT",
          reason: "Claude not connected — falling back to ChatGPT for the heavy workload"
        )
      }
      if availability.openRouterKeyPresent {
        return Route(
          modelIdentifier: "qwen/qwen3-coder:free",
          providerLabel: "OpenRouter (free)",
          reason: "No subscription connected — using the free OpenRouter model for the heavy workload"
        )
      }
      return onDeviceRoute
    }
  }

  /// Map a `Route` to the `ChatProvider.BridgeMode` that can serve it.
  /// Used by the live cost-router to switch the active bridge to the cheapest
  /// capable provider before sending traffic.
  ///
  /// - Claude  → .userClaude  (acp harness — Claude subscription)
  /// - ChatGPT → .userChatGPT (codex harness — ChatGPT/Codex subscription)
  /// - OpenRouter (free) → .openRouter (pi/OpenRouter harness using Omi Keychain)
  /// - On-device / unknown → .piMono (Omi cloud default)
  static func bridgeMode(for route: Route) -> ChatProvider.BridgeMode {
    switch route.providerLabel {
    case "Claude":
      return .userClaude
    case "ChatGPT":
      return .userChatGPT
    case "OpenRouter (free)":
      return .openRouter
    default:
      return .piMono
    }
  }
}
