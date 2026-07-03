import Foundation

// MARK: - Voice Engine Selection (pure logic)
//
// See docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md for the full design and
// ground truth. This models the choice ONE LEVEL ABOVE `VoiceProviderSelection`
// / `RealtimeOmniProvider`: which BRAIN + AUTH powers voice at all, not which
// concrete native-realtime model is picked underneath option 1.
//
// Two engines:
//   - `.nativeRealtimeBYOK` — RealtimeHub native speech-to-speech, funded by a
//     bring-your-own Platform API key (OpenAI `sk-` or a Google Gemini key) or
//     an Omi-managed ephemeral token when no key is set. See
//     `VoiceProviderSelection` for the existing key-mapping logic this wraps.
//   - `.chatGPTSubscriptionCascade` — Pass 2 (M): WIRED. Turn-based loop —
//     STT (whichever already ran this PTT turn; see `PushToTalkManager`) ->
//     `SubscriptionCascadeCoordinator` running `ChatProvider(.userChatGPT)` ->
//     TTS — so the reasoning turn runs on a ChatGPT plan Alex already pays
//     for, with no new OpenAI Platform bill. Ground truth (design doc §2,
//     `[WEB]`-sourced): OpenAI's Realtime API and Advanced Voice Mode cannot
//     be authorized by a ChatGPT-subscription OAuth token — that is exactly
//     why this is a SEPARATE turn-based cascade engine, never a mode of
//     `.nativeRealtimeBYOK`.
//
// Pure, no I/O, no UI — mirrors `VoiceProviderSelection`'s style so this can
// never silently drift from what `SubscriptionCascadeCoordinator` actually
// runs.
enum VoiceEngineSelection {

  /// The two voice engines a user can eventually choose between. Pass 1 ships
  /// both as visible rows, but only `.nativeRealtimeBYOK` is selectable.
  enum Engine: String, CaseIterable, Identifiable {
    case nativeRealtimeBYOK
    case chatGPTSubscriptionCascade

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .nativeRealtimeBYOK: return "GPT Realtime (bring your own OpenAI key)"
      case .chatGPTSubscriptionCascade: return "Voice via ChatGPT plan"
      }
    }
  }

  /// Whether an engine can actually be selected today. `.chatGPTSubscriptionCascade`
  /// unlocks the moment `CodexAccountAuth.isConnected()` is true — Pass 2 built
  /// `SubscriptionCascadeCoordinator` to actually run that loop, so this seam
  /// (deliberately hard-coded `false` in Pass 1 pending the coordinator) now
  /// tells the truth about what will run. The rule this enforces (per the
  /// design doc's §4c auth flow) is documented on `chatGPTCascadeSubtitle` below.
  static func isAvailable(_ engine: Engine, chatGPTConnected: Bool) -> Bool {
    switch engine {
    case .nativeRealtimeBYOK: return true
    case .chatGPTSubscriptionCascade: return chatGPTConnected
    }
  }

  /// Honest, connection-aware subtitle for the ChatGPT-subscription cascade
  /// row. Reuses the already-shipped, already-audited ChatGPT connect state
  /// (`CodexAccountAuth.isConnected()` via `chatProvider.isChatGPTConnected`)
  /// to tell the user exactly what unblocks the row, or that it is live.
  static func chatGPTCascadeSubtitle(chatGPTConnected: Bool) -> String {
    if chatGPTConnected {
      return
        "Runs voice turns on your connected ChatGPT plan — thinking, not full realtime (a beat slower, no barge-in). No new OpenAI API bill."
    }
    return
      "Connect ChatGPT above to run voice on your ChatGPT plan (no new OpenAI API bill)."
  }

  /// Pure derivation of the engine actually in effect today, from a persisted
  /// selection. Resolves to `.nativeRealtimeBYOK` whenever the stored
  /// selection isn't currently available (e.g. cascade selected but ChatGPT
  /// got disconnected) — this guards against a stale selection silently
  /// routing real voice traffic through an engine that can't run right now.
  static func effectiveEngine(storedSelection: Engine, chatGPTConnected: Bool) -> Engine {
    guard isAvailable(storedSelection, chatGPTConnected: chatGPTConnected) else {
      return .nativeRealtimeBYOK
    }
    return storedSelection
  }
}
