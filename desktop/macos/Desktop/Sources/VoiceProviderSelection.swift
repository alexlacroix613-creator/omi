import Foundation

// MARK: - Voice Provider Selection (pure logic)
//
// Two independent, user-facing voice controls live in Advanced → AI Setup. This
// enum holds the pure mapping between persisted state and the choice shown in the
// UI so the Settings view and the runtime never drift. It has NO UI and NO I/O —
// it only translates stored flags/keys to/from a picker selection.
//
//   1. Voice Model (multimodal realtime) — the RealtimeHub voice brain. It needs a
//      model that does audio AND vision natively (OMI streams screen + mic into it),
//      so the only bring-your-own options are multimodal realtime models: the user's
//      own Google Gemini key (geminiFlashLive) or OpenAI's realtime model via their
//      own OpenAI key (gptRealtime2). When a key is present the hub connects
//      client-direct with it (RealtimeHubController.ensureWarm → .byokKey); when
//      absent, managed users connect with an Omi-minted ephemeral token. Deepgram is
//      audio→text only (no vision) and therefore can never occupy this slot.
//
//   2. Transcription (STT) — the conversation-capture speech-to-text path. Three real,
//      distinct runtime states exist in-tree: on-device Parakeet (default on Apple
//      Silicon, no cloud), Omi-managed Deepgram cloud, or the user's own Deepgram key
//      (attached as the X-BYOK-Deepgram header on the cloud path). The cloud path is
//      selected by the existing `forceCloudSTT` flag read in AppState+Transcription.
//
enum VoiceProviderSelection {

  // MARK: Transcription (STT)

  /// The three distinct transcription runtime states a user can pick.
  enum TranscriptionChoice: String, CaseIterable, Identifiable {
    /// On-device Parakeet (Apple Silicon). The factory default — no audio leaves the Mac.
    case onDevice
    /// Omi-managed Deepgram in the cloud (Omi's key, billed by Omi).
    case omiCloud
    /// The user's own Deepgram key, used for cloud transcription (`dev_deepgram_api_key`).
    case deepgramBYO

    var id: String { rawValue }
  }

  /// Derive the current transcription choice from persisted state.
  /// - Parameters:
  ///   - forceCloud: the persisted `forceCloudSTT` flag (true = cloud/Deepgram path).
  ///   - hasDeepgramKey: whether `dev_deepgram_api_key` is set (non-empty).
  static func transcriptionChoice(forceCloud: Bool, hasDeepgramKey: Bool) -> TranscriptionChoice {
    guard forceCloud else { return .onDevice }
    return hasDeepgramKey ? .deepgramBYO : .omiCloud
  }

  /// The persisted state a chosen transcription option implies, so the derived
  /// choice above round-trips exactly.
  /// - Returns: `forceCloud` = the flag to write; `clearDeepgramKey` = whether to
  ///   wipe any stored BYO key (so "Omi cloud" isn't silently read back as BYO).
  static func transcriptionState(
    for choice: TranscriptionChoice
  ) -> (forceCloud: Bool, clearDeepgramKey: Bool) {
    switch choice {
    case .onDevice: return (false, false)  // key may stay stored; it is unused off the cloud path
    case .omiCloud: return (true, true)  // managed key — clear any BYO key so state stays exact
    case .deepgramBYO: return (true, false)  // user fills the key field
    }
  }

  // MARK: Voice Model (realtime, multimodal)

  /// Whether the realtime hub will connect client-direct with the user's own key
  /// (true) or fall back to an Omi-managed ephemeral token (false). Mirrors
  /// RealtimeHubController.ensureWarm's `if let key = byokKey(...)` branch.
  static func realtimeUsesOwnKey(hasProviderKey: Bool) -> Bool { hasProviderKey }

  /// The BYOK UserDefaults storage key the realtime hub reads for a given voice
  /// model. Mirrors RealtimeHubProvider.byokProvider: the Gemini live model reads
  /// the Gemini key; the OpenAI realtime model reads the OpenAI key. Callers pass a
  /// CONCRETE model raw value (resolve `.auto` to its effective provider first).
  static func realtimeKeyStorageKey(forModel modelRaw: String) -> String {
    switch modelRaw {
    case "gptRealtime2": return BYOKProvider.openai.storageKey
    default: return BYOKProvider.gemini.storageKey  // geminiFlashLive (and any Gemini default)
    }
  }

  /// Human-readable provider name for the BYO-key copy, for a concrete model raw value.
  static func realtimeProviderDisplayName(forModel modelRaw: String) -> String {
    switch modelRaw {
    case "gptRealtime2": return "OpenAI"
    default: return "Google Gemini"
    }
  }
}
