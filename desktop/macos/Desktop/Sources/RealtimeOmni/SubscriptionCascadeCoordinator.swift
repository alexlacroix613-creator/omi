import Foundation

// MARK: - Subscription Cascade Coordinator
//
// Pass 2 (M) of DREAM_BACKLOG item 8 — see
// docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md §4b/§4c/§4d. Flips the seam
// `VoiceEngineSelection` built in Pass 1 from a hard-coded-unavailable
// placeholder to a real, working turn: a final transcript (already produced
// by whichever STT ran this PTT turn — omni STT or Deepgram; see the wiring
// note in `PushToTalkManager`) goes to `ChatProvider` pinned to the
// `.userChatGPT` / Codex bridge, and the reply is spoken through the existing
// playback service. No new transport, no new credential surface — this file
// is glue over three already-shipped legs.
//
// Deliberately owns NO I/O of its own. The three legs are injected as narrow
// closures so the whole turn lifecycle (state machine, precondition checks,
// error classification) is unit-testable with fakes, per the design doc's
// §5 test plan, without a real `codex login`, mic, or TTS engine. The
// `convenience init()` wires the real defaults; `SubscriptionCascadeCoordinator
// .shared` is what runtime call sites use.
@MainActor
final class SubscriptionCascadeCoordinator: ObservableObject {

    static let shared = SubscriptionCascadeCoordinator()

    // MARK: - Turn state

    /// Mirrors the shape of `AgentStallNarration`'s pure, wall-clock-injected
    /// style: `.thinking` carries `startedAt` so a UI can layer stall
    /// narration ("still thinking…") on top without this type owning a timer.
    enum State: Equatable {
        case idle
        case thinking(startedAt: Date)
        case speaking
        case failed(CascadeTurnError)
    }

    /// The failure modes named in the design doc §4d, each with copy honest
    /// enough to render directly — "visible-but-graceful," never a silent drop.
    enum CascadeTurnError: Equatable {
        /// `CodexAccountAuth.isConnected()` was false when the turn started,
        /// OR the reasoning leg failed and the connection flag has since
        /// flipped false — the same recoverable story covers a cold-start
        /// disconnect and a token expiring mid-turn (§4d, failure mode 1).
        case chatGPTNotConnected
        /// `CodexAccountAuth.locateCodexBinary()` found no `codex` executable
        /// (§4d, failure mode 2).
        case codexNotInstalled
        /// The transcript handed to `runTurn` was empty or whitespace-only
        /// (§4d, failure mode 4 — "STT empty/garbled").
        case emptyTranscript
        /// The reasoning leg returned no reply while still connected — a
        /// bridge/tool error surfaced through the existing `errorMessage`
        /// channel rather than a connection problem.
        case providerError(String)

        /// Copy safe to render directly in a disabled-row subtitle or a
        /// toast — short, no jargon, always has a next step (or explicitly
        /// none, for "try again").
        var userMessage: String {
            switch self {
            case .chatGPTNotConnected:
                return "Connect your ChatGPT account to use voice on your ChatGPT plan."
            case .codexNotInstalled:
                return "Codex CLI isn't installed — install it to use voice on your ChatGPT plan."
            case .emptyTranscript:
                return "Didn't catch that — try again."
            case .providerError(let message):
                return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "ChatGPT couldn't answer that turn — try again."
                    : message
            }
        }
    }

    @Published private(set) var state: State = .idle

    // MARK: - Injected legs

    private let isChatGPTConnected: () -> Bool
    private let isCodexInstalled: () -> Bool
    private let reason: (String) async -> CascadeReasoningResult
    private let speak: (String) -> Void

    /// Full injection point — used directly by tests with fakes for every leg.
    init(
        isChatGPTConnected: @escaping () -> Bool,
        isCodexInstalled: @escaping () -> Bool,
        reason: @escaping (String) async -> CascadeReasoningResult,
        speak: @escaping (String) -> Void
    ) {
        self.isChatGPTConnected = isChatGPTConnected
        self.isCodexInstalled = isCodexInstalled
        self.reason = reason
        self.speak = speak
    }

    /// Real wiring: a DEDICATED `ChatProvider(bridgeHarnessOverride: .codex)`
    /// instance, separate from the app's main chat `ChatProvider` — a cascade
    /// voice turn must never touch the visible chat's bridge mode, message
    /// list, or session state (design doc §4c). Reads the already-audited
    /// `CodexAccountAuth` directly rather than through the main chat's
    /// `isChatGPTConnected` publisher, so this coordinator has no dependency
    /// on any particular `ChatProvider` instance being alive.
    convenience init() {
        let bridge = ChatProvider(bridgeHarnessOverride: .codex)
        self.init(
            isChatGPTConnected: { CodexAccountAuth.isConnected() },
            isCodexInstalled: { CodexAccountAuth.locateCodexBinary() != nil },
            reason: { text in
                let reply = await bridge.sendMessage(text)
                return CascadeReasoningResult(replyText: reply, errorMessage: bridge.errorMessage)
            },
            // Pass 3: read the user's cascade-specific voice-quality choice fresh
            // on every turn (no caching, mirrors `PushToTalkManager
            // .effectiveVoiceEngine()`'s pattern) rather than once at init time,
            // so flipping the Settings row between turns takes effect immediately.
            // `.system` gets the hard `speakOneShotSystemVoice` guarantee; `.neural`
            // (the default) keeps Pass 2's `speakOneShot` behavior unchanged.
            speak: { text in
                let quality =
                    CascadeVoiceQualitySelection.Quality(
                        rawValue: UserDefaults.standard.string(forKey: "cascadeVoiceQuality") ?? "")
                    ?? CascadeVoiceQualitySelection.defaultQuality
                if CascadeVoiceQualitySelection.forcesSystemVoice(quality) {
                    FloatingBarVoicePlaybackService.shared.speakOneShotSystemVoice(text)
                } else {
                    FloatingBarVoicePlaybackService.shared.speakOneShot(text)
                }
            }
        )
    }

    // MARK: - Pure precondition (design doc §4d, checked before any I/O)

    /// Pure gate run before the reasoning leg is touched — no async, no
    /// closures, fully unit-testable in isolation. Mirrors
    /// `VoiceEngineSelection`'s no-I/O style so the two seams can never
    /// silently disagree about what "available" means.
    static func precondition(
        transcript: String,
        chatGPTConnected: Bool,
        codexInstalled: Bool
    ) -> CascadeTurnError? {
        guard chatGPTConnected else { return .chatGPTNotConnected }
        guard codexInstalled else { return .codexNotInstalled }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyTranscript
        }
        return nil
    }

    // MARK: - Turn lifecycle

    /// Run one voice turn: `transcript` is the ALREADY-FINALIZED text for this
    /// PTT turn (produced upstream by whichever STT ran it — see the call
    /// site in `PushToTalkManager`). No-ops (does not stack a second turn) if
    /// a turn is already `.thinking` or `.speaking`.
    func runTurn(transcript: String) async {
        switch state {
        case .thinking, .speaking:
            return
        case .idle, .failed:
            break
        }

        if let failure = Self.precondition(
            transcript: transcript,
            chatGPTConnected: isChatGPTConnected(),
            codexInstalled: isCodexInstalled()
        ) {
            state = .failed(failure)
            return
        }

        let startedAt = Date()
        state = .thinking(startedAt: startedAt)
        let result = await reason(transcript)

        // `reset()` may have fired while the reasoning leg was in flight
        // (e.g. the user disconnected ChatGPT mid-turn from Settings). Don't
        // resurrect a stale turn on top of whatever superseded it.
        guard state == .thinking(startedAt: startedAt) else { return }

        let reply = result.replyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reply.isEmpty else {
            // No reply text. If the connection flag has flipped false since
            // the precondition check above, this is a mid-turn auth expiry
            // (§4d) — classify it the same as a cold-start disconnect so the
            // UI tells ONE consistent "reconnect ChatGPT" story rather than
            // two different error shapes for the same underlying cause.
            state = .failed(
                isChatGPTConnected() ? .providerError(result.errorMessage ?? "") : .chatGPTNotConnected)
            return
        }

        state = .speaking
        speak(reply)
        state = .idle
    }

    /// Clears any `.failed` / mid-turn state back to idle. Used by a manual
    /// "dismiss" / "try again" affordance, and by disconnect handling so a
    /// stale `.thinking` turn doesn't linger after the user backs out.
    func reset() {
        state = .idle
    }
}

/// What the reasoning leg produced for one turn. `errorMessage` mirrors
/// `ChatProvider.errorMessage` — read AFTER `sendMessage` returns nil, same
/// as the existing chat UI does, rather than inventing a second error
/// channel the bridge has to keep in sync.
struct CascadeReasoningResult: Equatable {
    let replyText: String?
    let errorMessage: String?
}
