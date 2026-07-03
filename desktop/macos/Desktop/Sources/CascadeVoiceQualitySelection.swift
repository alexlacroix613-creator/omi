import Foundation

// MARK: - Cascade Voice Quality Selection (pure logic)
//
// Pass 3 (S) of DREAM_BACKLOG item 8 — see
// docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md §4b/§6. The design doc's Pass 3
// framing ("swap system AVSpeech for the chunked neural-TTS backend the playback
// service already supports") turned out to already be true by accident: Pass 2's
// `speak` leg calls `FloatingBarVoicePlaybackService.speakOneShot`, which resolves
// `ShortcutSettings.selectedVoiceID` — and the app's shipped default voice
// (`defaultVoiceID = openAIShimmerVoiceID`) is ALREADY an OpenAI neural voice, not
// system AVSpeech. So there was no literal swap left to make.
//
// What reading the actual wiring surfaced instead is a real, narrower gap: that
// same neural path goes through `APIClient.synthesizeSpeech`, whose request
// carries whatever BYOK keys `APIKeyService.isByokActive` has forwarded
// (`APIClient.buildHeaders`, "BYOK: attach user-provided keys ... for LLM/STT
// calls this request triggers"). `isByokActive` is all-or-nothing across the four
// BYOK providers, so a user who's configured full BYOK (e.g. for the native
// realtime engine or general chat) gets their OWN OpenAI key silently billed for
// cascade TTS too — quietly contradicting `VoiceEngineSelection
// .chatGPTCascadeSubtitle`'s "no new OpenAI API bill" promise, which
// `VoiceEngineSelectionTests.testChatGPTCascadeSubtitle_neverImpliesAnExtraOpenAIBill`
// treats as an invariant.
//
// This type is the honest fix: a per-cascade "Voice quality" choice, independent
// of the shared `ShortcutSettings.selectedVoiceID` used everywhere else in the
// app, so a user who wants the "no new bill, guaranteed" story literal can pick
// `.system` and get a hard guarantee — zero network TTS call, zero chance of
// touching a BYOK key — while `.neural` (the default, nicer-sounding) keeps
// today's Pass 2 behavior and is honest in the UI about the one case where it
// can cost the user something. Pure, no I/O — mirrors `VoiceEngineSelection`'s
// style so this can never silently drift from what `SubscriptionCascadeCoordinator`
// actually speaks.
enum CascadeVoiceQualitySelection {

  /// The two voice-quality choices for the ChatGPT-subscription cascade engine
  /// specifically. Does not affect the native realtime engine or any other
  /// floating-bar voice reply, which keep using `ShortcutSettings.selectedVoiceID`
  /// as before.
  enum Quality: String, CaseIterable, Identifiable {
    /// Forces `AVSpeechSynthesizer` (system voice) for every cascade reply.
    /// Zero network calls, zero chance of touching any BYOK key — a hard
    /// guarantee, not just the common case.
    case system
    /// Uses the app's normal neural-TTS path (today: OpenAI voices synthesized
    /// through the desktop backend's TTS proxy) — nicer-sounding, and free to
    /// the user UNLESS they have full BYOK active, in which case this leg is
    /// billed the same as their other BYOK usage.
    case neural

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .system: return "System voice"
      case .neural: return "Neural (when available)"
      }
    }
  }

  /// Cascade defaults to `.neural` — nicer audio, and free for the vast
  /// majority of users (anyone not running full four-provider BYOK).
  static let defaultQuality: Quality = .neural

  /// Pure mapping from the user's choice to whether the cascade's speak leg
  /// must bypass the normal neural path entirely. `.system` is an unconditional
  /// `true` — this is the one guarantee this type exists to provide.
  static func forcesSystemVoice(_ quality: Quality) -> Bool {
    quality == .system
  }

  /// Honest, cost-aware subtitle for the quality row. `isByokActive` mirrors
  /// `APIKeyService.isByokActive` — true only when all four BYOK providers are
  /// configured, the same all-or-nothing gate `APIClient.buildHeaders` uses to
  /// decide whether to forward the user's own keys on every backend request
  /// (TTS synthesis included).
  static func costSubtitle(quality: Quality, isByokActive: Bool) -> String {
    switch quality {
    case .system:
      return "Always free — no network call, never touches any key you've configured."
    case .neural:
      return isByokActive
        ? "Nicer-sounding, but your BYOK OpenAI key is active — this may bill your own key, same as your other BYOK usage."
        : "Nicer-sounding, synthesized by Omi's voice backend. No bill to you."
    }
  }
}
