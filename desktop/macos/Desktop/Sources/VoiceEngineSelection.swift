import Foundation

// MARK: - Voice Engine Selection (pure logic)
//
// Pass 1 (S) of DREAM_BACKLOG item 8 — see
// docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md for the full design and ground
// truth. This models the choice ONE LEVEL ABOVE `VoiceProviderSelection` /
// `RealtimeOmniProvider`: which BRAIN + AUTH powers voice at all, not which
// concrete native-realtime model is picked underneath option 1.
//
// Two engines:
//   - `.nativeRealtimeBYOK` — today's only shipped path. RealtimeHub native
//     speech-to-speech, funded by a bring-your-own Platform API key (OpenAI `sk-`
//     or a Google Gemini key) or an Omi-managed ephemeral token when no key is
//     set. See `VoiceProviderSelection` for the existing key-mapping logic this
//     wraps.
//   - `.chatGPTSubscriptionCascade` — NOT YET WIRED (queued for Pass 2). The
//     planned loop is on-device STT -> `ChatProvider(.userChatGPT)` -> TTS, so
//     the reasoning turn runs on a ChatGPT plan Alex already pays for, with no
//     new OpenAI Platform bill. Ground truth (design doc §2, `[WEB]`-sourced):
//     OpenAI's Realtime API and Advanced Voice Mode cannot be authorized by a
//     ChatGPT-subscription OAuth token — that is exactly why this is a SEPARATE
//     turn-based cascade engine, never a mode of `.nativeRealtimeBYOK`.
//
// Pure, no I/O, no UI, no runtime behavior change in Pass 1 — mirrors
// `VoiceProviderSelection`'s style so this can never silently drift from what
// Pass 2 actually wires up.
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

  /// Whether an engine can actually be selected today. Pass 1 keeps the cascade
  /// engine disabled UNCONDITIONALLY — connecting ChatGPT does not unlock it,
  /// because the coordinator that would run the loop (`SubscriptionCascade
  /// Coordinator`, Pass 2) does not exist yet. `chatGPTConnected` is accepted
  /// now (rather than added in Pass 2) so Pass 2 has a stable, already-tested
  /// seam to flip from `false` to `chatGPTConnected` — the rule that seam
  /// enforces (per the design doc's §4c auth flow) is documented on
  /// `chatGPTCascadeSubtitle` below.
  static func isAvailable(_ engine: Engine, chatGPTConnected: Bool) -> Bool {
    switch engine {
    case .nativeRealtimeBYOK: return true
    case .chatGPTSubscriptionCascade: return false
    }
  }

  /// Honest, connection-aware subtitle for the disabled ChatGPT-subscription
  /// cascade row. Reuses the already-shipped, already-audited ChatGPT connect
  /// state (`CodexAccountAuth.isConnected()` via `chatProvider.isChatGPTConnected`)
  /// purely to TELL the user what unblocks the row next — it never enables it in
  /// Pass 1 (see `isAvailable`).
  static func chatGPTCascadeSubtitle(chatGPTConnected: Bool) -> String {
    if chatGPTConnected {
      return
        "Coming soon — your ChatGPT account is already connected, so this will work with zero extra setup once shipped. No new OpenAI API bill."
    }
    return
      "Coming soon — will run voice on your ChatGPT plan (connect ChatGPT above first). No new OpenAI API bill."
  }

  /// Pure derivation of the engine actually in effect today, from a persisted
  /// selection. Pass 1 always resolves to `.nativeRealtimeBYOK` when the stored
  /// selection isn't available yet — this guards against a stale or
  /// experimentally-written selection silently routing real voice traffic
  /// through an engine with no coordinator behind it.
  static func effectiveEngine(storedSelection: Engine, chatGPTConnected: Bool) -> Engine {
    guard isAvailable(storedSelection, chatGPTConnected: chatGPTConnected) else {
      return .nativeRealtimeBYOK
    }
    return storedSelection
  }
}
