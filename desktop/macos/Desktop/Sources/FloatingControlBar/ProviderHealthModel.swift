import Foundation

/// Pure, deterministic snapshot of which LLM providers are wired up and ready
/// to serve requests, so a settings/health surface can render an honest
/// "N of M connected" without ever poking the network. Each provider's
/// readiness is reported as a `.connected` or `.needsSetup` flag, and a
/// convenience `summary` string is pre-composed for direct display.
///
/// Deliberately pure logic: no clock, no I/O, no live network — the four
/// booleans are the ground truth, passed in by the caller (which knows
/// whether each provider's API key is present and valid).
enum ProviderHealthModel {

  enum Status: Equatable, Sendable {
    /// Provider is wired up and ready to handle requests.
    case connected
    /// Provider is missing credentials, model selection, or other setup.
    case needsSetup
  }

  struct ProviderHealth: Equatable, Sendable {
    let name: String
    let status: Status
  }

  struct ProviderHealthModel: Equatable, Sendable {
    /// Per-provider health in a stable, UI-friendly order.
    let providers: [ProviderHealth]
    /// Number of providers currently `.connected`.
    let connectedCount: Int
    /// Total number of providers tracked (always 4 today).
    let total: Int
    /// Pre-composed human summary, e.g. "2 of 4 connected".
    var summary: String {
      "\(connectedCount) of \(total) connected"
    }
    /// True only when every tracked provider is `.connected`.
    var allConnected: Bool {
      connectedCount == total
    }
  }

  /// Build a deterministic health snapshot from four booleans. Order is
  /// always Claude, ChatGPT, OpenRouter, Gemini — the same order callers
  /// see in the UI — so tests and rendered output stay stable.
  ///
  /// - Parameters:
  ///   - claude: true iff Claude is wired up.
  ///   - chatGPT: true iff ChatGPT is wired up.
  ///   - openRouter: true iff OpenRouter is wired up.
  ///   - gemini: true iff Gemini is wired up.
  static func build(
    claude: Bool,
    chatGPT: Bool,
    openRouter: Bool,
    gemini: Bool
  ) -> ProviderHealthModel {
    let providers: [ProviderHealth] = [
      ProviderHealth(name: "Claude", status: claude ? .connected : .needsSetup),
      ProviderHealth(name: "ChatGPT", status: chatGPT ? .connected : .needsSetup),
      ProviderHealth(name: "OpenRouter", status: openRouter ? .connected : .needsSetup),
      ProviderHealth(name: "Gemini", status: gemini ? .connected : .needsSetup),
    ]
    let connected = providers.filter { $0.status == .connected }.count
    return ProviderHealthModel(
      providers: providers,
      connectedCount: connected,
      total: providers.count
    )
  }
}
