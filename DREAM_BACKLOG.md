# DREAM_BACKLOG — Siempre OMI fork

Prioritized improvement backlog for the macOS desktop app (`desktop/macos`), branch
`feat/native-provider-auth-v0.12.0`. Ranking = **Value** (Alex-impact, 1–5) ×
**Effort** (S/M/L) × **Risk** (Low/Med/High). Each item has file/symbol refs and a
one-line fix. This drives later dream iterations.

Weighting note: Alex's top two complaints are (a) "I send OMI on a task then silence
forever" and (b) "Execute does nothing visible." Everything touching those is ranked up.

Legend: Value 5 = biggest win. Effort S = <1 file/hour, M = a few files, L = multi-file/design.

---

## Top ranked

### 1. [DONE this iteration] Realtime agent stall narration in the floating bar
- **Value 5 · Effort S · Risk Low** — directly kills complaint (a).
- Was: an agent pill that stops emitting events shows a frozen `latestActivity`
  ("Working…") with no sense of time. Alex can't tell running-fine from hung.
- Built: `Sources/FloatingControlBar/AgentStallNarration.swift` (pure helper),
  `AgentPill.lastActivityAt` stamp, and a `TimelineView(.periodic)` subtitle in
  `NotchAgentListRow` (FloatingControlBarView.swift) showing live elapsed and
  escalating to "Still working — quiet for 2m" → "No update for 2m — may have
  stalled". Tests: `Tests/AgentStallNarrationTests.swift`.

### 2. [DONE this iteration] Execute button gives zero in-page feedback (Tasks page)
- **Value 5 · Effort S · Risk Low** — complaint (b), the other headline pain.
- Was: `MainWindow/Pages/TasksPage.swift:~4376` Execute button called
  `AgentPillsManager.shared.spawn(query:model:)` and returned nothing to the row.
  The pill spawns in the floating bar, which may be off-screen/hidden, so from the
  Tasks page the click looked dead.
- Built: `TaskRow.showExecutedFeedback()` shows a transient "Sent to agents" toast
  (same spring-in/ease-out timing as the existing `shareCopiedToast`, ~2s) and
  reveals the floating bar via `FloatingControlBarManager.shared.showTemporarily()`
  when it isn't already visible — the same "show without changing the user's
  pinned/hidden preference" call `ChatProvider` already uses for background
  browser tools. No new execution path; no pure logic worth a unit test (it's UI
  toast wiring reusing an existing manager call), so none added.
- Deferred: an "Open" affordance that jumps straight to the new pill's chat via
  `state.activeAgentChatPillID` — `FloatingControlBarState.present(_:)` is the
  hook, but it lives behind `FloatingControlBarManager.shared.window?.state`
  with no small public wrapper yet. Worth a follow-up item if Alex wants one-tap
  jump-to-pill instead of just "it's now visible somewhere."

### 3. [DONE this iteration] Stall narration should also drive a Cancel/still-there prompt in the pill popover
- **Value 4 · Effort S · Risk Low** — completes item 1 for users who open the pill.
- Was: the popover (`AgentMainChatView` in `FloatingControlBarView.swift`, body
  ~line 1536 — the backlog's "AgentChatPanel" name was stale, no such type
  exists) showed the live transcript but no stall banner.
- Built: a `stallBanner` computed view reusing the same
  `AgentStallNarration.narrate(...)` + `TimelineView(.periodic(from:.now, by:5))`
  pattern as `NotchAgentListRow`, inserted between `header` and
  `ChatScrollContainer`. Renders nothing until `.level == .stalled`, then shows
  the narration text + a dedicated red "Stop" pill wired to the existing
  `AgentPillsManager.stop(pillID: UUID)` (verified signature — same call the
  header's small stop button already uses). No new pure logic, so no new
  tests; `AgentStallNarrationTests` (8/8) still pass and the module rebuilds
  clean.
- Discovered/fixed in the same pass: naively adding `stallBanner` as a plain
  child of the outer `VStack(spacing: 12)` leaves a permanent ~24pt dead gap
  around it even when hidden — SwiftUI reserves inter-item spacing for a
  conditional child regardless of whether it renders `EmptyView`. Fixed by
  setting the VStack to `spacing: 0` and giving `header` / `ChatScrollContainer`
  their own `.padding(.bottom, 12)`, with the banner supplying its own
  `.padding(.bottom, 12)` only when visible — normal (non-stalled) layout is
  now pixel-identical to before this change.

### 4. [DONE this iteration] Cloud VM Execute path (AgentVMService) is invisible and can silently die
- **Value 4 · Effort M · Risk Med** — the true "ghosting cloud VM" path.
- Was: `AgentVMService.swift` (provision → poll → upload DB) is fire-and-forget with
  only `log(...)`; nothing reaches SwiftUI. `pollUntilReady` gives up after 30×5s with
  no user signal; provision failure just returns. The `AgentStatusResponse`
  (`createdAt`/`lastQueryAt`, APIClient.swift ~5297) fields were never surfaced either
  (the backlog's "`agentStartedAt`" name was stale — that field belongs to
  `TaskActionItem`, a different agent-execution-tracking struct entirely; no such
  property exists on the VM status response).
- Built: `Sources/AgentVMStatusStore.swift` — a pure `AgentVMState` enum
  (idle/provisioning/polling/uploading/ready/failed(reason)/timedOut) with
  `isRunning`/`label`, a pure `AgentVMStallLogic.isStalled(state:since:now:)` helper
  (mirrors `AgentStallNarration`'s "quiet too long" idea but off discrete stage
  transitions instead of a continuous activity stream — 150s threshold, matching
  `pollUntilReady`'s own 30×5s give-up point), and an `@MainActor
  AgentVMStatusStore.shared` `ObservableObject` with `transition(to:)` +
  `lastTransitionAt`. `AgentVMService` now calls `transition(to:)` at every pipeline
  stage (`ensureProvisioned`, `runPipeline`, `reuploadDatabase`) — no behavior change
  to the pipeline itself, purely additive status reporting. Surfaced as a "Cloud
  Sync" status row (icon + state label + live "since" time via
  `TimelineView(.periodic)`, amber when stalled, red when failed/timed out) in
  Settings → Advanced → Troubleshooting (`cloudSyncStatusCard` in
  `SettingsContentView+Assistants.swift`), mirroring the existing
  `troubleshootingSubsection` card pattern (Report Issue / Rescan Files). Tests:
  `Tests/AgentVMStatusStoreTests.swift` (10/10) covering `AgentVMState.isRunning`/
  `Equatable`, `AgentVMStallLogic` boundary + clock-skew cases, and
  `AgentVMStatusStore.transition` (incl. same-state no-op, differing-reason
  `.failed` re-transition).
- Also closes the secondary "`pollUntilReady` swallows the timeout" item below:
  both `pollUntilReady` give-up paths (`ensureProvisioned`'s polling branch and
  `runPipeline`) and the provision-failure / no-IP paths now call
  `AgentVMStatusStore.markFailed(reason)` / `.markTimedOut()`, which transition the
  store AND post a one-shot system notification via the existing
  `NotificationService.shared.sendNotification(deliverSystemBanner: true,
  respectFrequency: false)` helper — the same pattern already used for the screen-
  capture-reset functional notification, so no new notification permission path was
  introduced.
- Deliberately not tested: `markFailed`/`markTimedOut` themselves (they call into
  `NotificationService`, which touches system notification permission APIs and the
  floating-bar window manager — out of scope for a fast unit test and would make the
  suite flaky/order-dependent on macOS notification state). The pure logic they
  delegate to (`transition(to:)`) is fully covered instead.

### 5. [DONE — Design + Passes A/B shipped; Pass C GATED] Reroute Execute away from the ghosting cloud VM to a reporting agent
- **Value 5 · Effort L→S+S (re-rated) · Risk High→Low/Med (re-rated)**.
- Was: assumed to need an L structural rebuild. Design pass
  (`docs-fork/EXECUTE_REROUTE_DESIGN.md`) traced every caller and found the
  "reroute" is already the architecture: user-triggered Execute already routes
  100% through the local reporting pill (`AgentPillsManager.spawn` /
  `spawnFromUserQuery`); the cloud VM (`AgentVMService`) has exactly 3
  callers, all background (`DesktopHomeView.swift:705` warmup,
  `OnboardingView.swift:502` onboarding, `AgentSyncService.swift:220` sync
  repair), and is a one-way memory-database backup pipeline that never
  dispatches a task or reads a result back.
- **Built (Pass A — lock the invariant, S):** doc-comment invariants at both
  chokepoints — `AgentVMService`'s header (`Sources/AgentVMService.swift`)
  states it is a backup-only pipeline that must never carry a user task, and
  `AgentPillsManager`'s header (`Sources/FloatingControlBar/AgentPill.swift`)
  states it is the sole Execute entry point — each pointing at the other and
  at the design doc. New `Tests/AgentVMCallerInvariantTests.swift` (2 tests):
  a source scan (via `#filePath`, same technique `StartupWarmupPolicyTests`
  already uses to read sibling source files) asserts the set of files calling
  `AgentVMService.shared.<method>` is EXACTLY the known background trio, and a
  companion test asserts the three known Execute surfaces (`TasksPage.swift`,
  `FloatingControlBarView.swift`, `MemoryExportExecutor.swift`) still call
  `AgentPillsManager.shared.spawn` and never call `AgentVMService` directly.
  Honest limitation: textual scan, not a real call-graph/SourceKit check — it
  can't see indirection through a closure or a renamed reference, but it is
  exact for the direct-call shape every known caller (and any careless future
  wiring attempt) would use.
- **Built (Pass B — finish the honesty pass, S):** reworded "cloud agent VM
  pipeline" → "cloud memory-replica pipeline" in `AgentVMStatusStore.swift`'s
  doc comments (kills the "agent = runs my tasks" implication at the source);
  `AgentVMState.idle.label` now reads "Idle — tasks run on this Mac"; the
  Troubleshooting card (`cloudSyncStatusCard`,
  `SettingsContentView+Assistants.swift`) gained a fixed one-line caption
  under the existing dynamic subtitle, shown in every state: "Memory backup
  for cloud/mobile access — your tasks run on this Mac." — copy-only, same
  card pattern, no new state.
- **Not built — Pass C is GATED, do not build speculatively:** the §3c
  reporting channel (`CloudAgentSessionReader` adapting a cloud task's
  session/update events into the local pill) requires a backend endpoint,
  `GET /session/<id>/events`, that does not exist yet. Building the adapter
  against a nonexistent endpoint would be untestable and speculative. Pick
  this up only when (1) a product decision is made to offer cloud Execute and
  (2) the backend ships that endpoint.
- Tests: new `AgentVMCallerInvariantTests` (2/2), regression
  `AgentVMStatusStoreTests` (10/10), `PiMonoWiringTests` (24/24),
  `AgentPillLifecycleTests` (48/48) — all green, confirming the doc-comment
  and copy edits didn't touch behavior.

### 6. [DONE this iteration] "Coming soon" provider placeholders may be dead toggles
- **Value 3 · Effort S · Risk Low**
- Was: `APIKeyService.swift:55` claimed "ChatGPT and Grok have no desktop harness yet
  and are shown as honest 'coming soon' placeholders" — audit needed to confirm no
  placeholder was a silently-inert tap target.
- Audited every provider surface: `ExternalAIAccountProvider` (Member Accounts card,
  `SettingsContentView+Advanced.swift:743` `aiAccountsCard`/`aiAccountRow`),
  `AIProvider.all` (AI Provider picker, `Providers/AIProvider.swift`),
  `RealtimeOmniProvider` (Voice Model picker, `RealtimeOmni/RealtimeOmniSettings.swift`),
  `BYOKProvider` (Developer Keys page) — grepped the whole `Sources` tree for
  "coming soon"/"comingSoon" to make sure no other placeholder exists outside these.
  Findings, provider by provider:
  - **Claude** — real, wired (`ChatProvider.BridgeMode.userClaude`, ACP bridge). Honest.
  - **ChatGPT** — real, wired (`BridgeMode.userChatGPT` / Codex CLI). Verified
    `startChatGPTAuth()` runs an actual `codex login` subprocess and
    `disconnectChatGPT()` moves the real `~/.codex/auth.json` aside — not a stub.
    Honest, and NOT a "coming soon" row (`comingSoon: false`).
  - **Grok** — the only real placeholder. `comingSoon: true` → the Connect button is
    `.disabled(comingSoon)`, so it cannot be tapped at all (not "tappable-but-inert").
    Label reads "Coming soon" with an explanatory subtitle. Honest.
  - **Hermes / OpenClaw** (AI Provider picker) — both wired to real local bridges.
  - **RealtimeOmniProvider** (auto/Gemini/GPT Realtime) — all three resolve to real
    models; no Grok/ChatGPT-subscription option is offered here at all (so nothing to
    mislabel — this is backlog item 8's gap, not a dead toggle).
  - **BYOKProvider** (openai/anthropic/gemini/deepgram, Developer Keys) — all four
    fully functional BYOK fields.
  - No occurrence of the old "cosmetic Grok connect" pattern (a button that flips a
    UserDefaults flag with no runtime effect) exists anywhere in `Sources`.
  - **Conclusion: no dead toggle found.** The one placeholder (Grok) was already
    correctly disabled before this pass.
- Fixed instead (found during the audit, not a UI dead-toggle but the same rot): two
  doc comments (`APIKeyService.swift:52-58`, `SettingsContentView+Advanced.swift:739-745`)
  still said ChatGPT "has no desktop harness yet" / renders as a disabled "coming
  soon" row — stale since the ChatGPT bridge shipped, and misleading for any future
  dev deciding whether to touch that row. Reworded both to state ChatGPT is real and
  only Grok is the placeholder.
- Also fixed `Tests/PiMonoWiringTests.swift:239` (`testAIProviderAllContainsSupportedProviders`)
  — asserted `AIProvider.all` excluded `"chatgpt"`, which was **failing at HEAD before
  this change** (confirmed via `git stash`). Same staleness as the doc comments: a
  test lying about which providers are supported. Updated the expected array to
  include `"chatgpt"` in its real position.
- Diff: 2 doc comments + 1 test assertion + this backlog entry. No UI/logic changed.
- Tests: `BYOKPaywallTests` (9/9), `PiMonoWiringTests` (24/24, including the fixed
  assertion), `StartupWarmupPolicyTests` (35/35) — 68/68 total, 0 failures.

### 7. [DONE this iteration] Rap slips the music filter (documented honest limitation)
- **Value 3 · Effort M · Risk Med**
- Was: the mic-channel music filter (commit 133e28c0b, `MusicFilterGate`) still let rap
  through because rap's speech-like cadence reads as conversation to Apple's
  SoundAnalysis classifier — the commit message named the cross-channel duplicate-text
  heuristic as the deferred proper fix for this residue.
- Built: `Sources/CrossChannelEchoGate.swift` — a pure, mutating `struct` (no wall
  clock inside; every method takes the segment's own `start`/`end` audio-time offsets,
  which are comparable across the mic and system `LocalTranscriptionService` instances
  because both start recording within milliseconds of each other on the same 10s
  window). `recordSystemSegment(text:start:end:)` remembers recent system-channel
  utterances (source of truth, never suppressed); `shouldSuppressMic(text:start:end:)`
  flags a mic segment as an echo when it substantially duplicates one of them. Design
  decisions, all named constants on the type: normalized-text **Jaccard token-overlap
  similarity** (lowercase, strip punctuation, collapse whitespace, then
  `|intersection|/|union|` of the token sets) — chosen over edit-distance for
  simplicity/explainability per the brief; **`similarityThreshold = 0.6`** (tolerates
  the mic's independent ASR decode of the same audio diverging by a word or two, e.g.
  room reverb, while still requiring most words to match — a topically-related but
  genuinely different reply won't cross it); **`windowSeconds = 6.0`** (covers
  window-boundary drift between the two independently-flushing 10s channels plus the
  ~0-2s an echo takes to travel speaker → mic → decode; also the pruning horizon for
  old system entries — same "first-pass guess, tune later" honesty as
  `AgentStallNarration`'s thresholds); **`minTokenCount = 4`**, applied to BOTH sides
  of the comparison — the false-positive guard from the brief ("yeah"/"yeah" must never
  suppress real short replies).
- Wired into the SAME "Filter Music From Conversations" toggle
  (`AssistantSettings.shared.filterMusicFromConversations`) that gates `MusicFilterGate`
  — reused rather than adding a second toggle, since this is that feature's own
  documented follow-up, not a separate concern. New `AppState.handleLocalTranscriptionSegments(_:)`
  (`Sources/AppState/AppState+ListenEvents.swift`) is the integration point: both
  on-device mic+system `LocalTranscriptionService` instances now deliver through it
  (previously straight to `handleBackendSegments`, both call sites in
  `AppState+Transcription.swift` — initial `startTranscription()` and the 4-hour
  rotation re-arm). It records every system-channel segment into a per-session
  `AppState.crossChannelEchoGate` (new property on `AppServicesCoordinator`, reset to a
  fresh instance at both call sites so echo state never leaks across conversations),
  drops a mic-channel segment when the gate flags it (logged, never persisted/counted),
  and always keeps + forwards the system channel untouched — structurally there is no
  code path that can suppress a system segment. The cloud STT path
  (`transcriptionService`, server-side diarization) is untouched — this only applies to
  the on-device Parakeet path where the commit's honest-limitation note lives.
- Tests: `Tests/CrossChannelEchoGateTests.swift` (25/25) — exact/near-exact duplicate
  suppressed (incl. one dropped word simulating ASR divergence), case/punctuation
  insensitivity, paraphrase and unrelated speech kept, short-utterance guard on both
  the mic AND system side (incl. the exact `minTokenCount` boundary), window-boundary
  inclusive/exclusive edges, stale-entry pruning, multiple tracked system segments (not
  just the latest), and the pure helpers (`timeGap`, `normalize`, `tokens`,
  `jaccardSimilarity`) directly. `MusicFilterGateTests` (7/7) still pass unchanged, and
  the full `Omi ComputerPackageTests` target builds clean (validates the `AppState` /
  `AppServicesCoordinator` wiring compiles, not just the pure gate in isolation).
- Residual risk (honest): the "sys channel never suppressed" guarantee is enforced
  structurally in `handleLocalTranscriptionSegments` (no suppression branch exists for
  `!segment.is_user`), not by a dedicated integration test — `AppState` isn't
  practically unit-testable here (MainActor, live services), matching how prior items
  (3, 4) left UI/AppState wiring untested while covering the pure logic fully. The
  0.6/6.0/4 constants are first-pass judgment calls, not tuned against real dual-channel
  rap logs — flag for revisit once real "mic re-hears speaker" recordings exist.
  `windowSeconds=6.0` assumes mic and system start within ~milliseconds of each other
  (true today per `AppState+Transcription.swift`'s sequential `mic.start()` /
  `system.start()` calls); if that ordering ever grows a meaningful async gap, the
  window constant would need revisiting too.

### 8. [DONE — Passes 1–3 shipped; only live manual QA remains] ChatGPT-subscription realtime voice not wired
- **Value 4 · Effort L · Risk Med** — known gap; Alex wants voice.
- `VoiceProviderSelection.swift` + realtime hub. BYOK realtime + Deepgram exist
  (commit fc952e0b4) but a ChatGPT *subscription* (not API key) realtime path isn't
  wired. Covered indirectly by `VoiceProviderSelectionTests`.
- Fix: add a subscription-auth provider option; likely needs an OAuth/token bridge like
  the OpenRouter PKCE work (commit 467519dd5). Design item.
- **Design done:** `docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md` — ground truth is
  a ChatGPT-subscription OAuth token **cannot** fund OpenAI's Realtime API or
  Advanced Voice Mode (OpenAI docs + OpenClaw issue #76498); "wire the subscription
  into GPT Realtime" is not buildable. Recommendation: Option B, a turn-based
  subscription **cascade** (on-device STT → `ChatProvider(.userChatGPT)` → TTS) that
  answers Alex's real want (voice on the ChatGPT plan he pays for, zero new API
  bill) using mature, already-shipped components. Split into Pass 1 (S) / Pass 2 (M)
  / Pass 3 (S, neural-TTS honesty) — ALL THREE NOW DONE; only the live manual QA
  script (bottom of this item) is left before item 8 is fully closed.
- **Pass 1 (S) done this iteration:** honesty + scaffolding, zero runtime behavior
  change.
  - `RealtimeOmniProvider.gptRealtime2.subtitle` (`Sources/RealtimeOmni/
    RealtimeOmniSettings.swift`) now states plainly it needs a funded OpenAI
    Platform key (`sk-`), not a ChatGPT plan — this is the text shown directly under
    the Voice Model picker. `realtimeVoiceKeyField` (`SettingsContentView+Advanced.swift`)
    gained the same disclaimer inline when the OpenAI key field is empty.
  - New pure `Sources/VoiceEngineSelection.swift` — `Engine` enum
    (`nativeRealtimeBYOK` / `chatGPTSubscriptionCascade`) + `isAvailable`,
    `chatGPTCascadeSubtitle`, `effectiveEngine`. Pass 1 hard-codes the cascade engine
    as unavailable regardless of ChatGPT connection state (no coordinator exists to
    run it yet) — `effectiveEngine` falls back to native even for a stale/tampered
    stored selection. Mirrors `VoiceProviderSelection`'s no-I/O style per the design
    doc so Pass 2 has a tested seam to flip on rather than inventing the rule then.
  - New disabled row in the Voice Model card, `voiceEngineChatGPTCascadeRow`
    (`SettingsContentView+Advanced.swift`) — "Voice via ChatGPT plan" /
    "Coming soon" button `.disabled(true)`, subtitle driven by
    `VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected:)` reading the
    real `chatProvider?.isChatGPTConnected` gate (informational only — does not
    enable the row). Mirrors the Grok placeholder pattern audited in item 6
    (tappable-but-inert dead toggles do not exist here either).
  - Tests: new `Tests/VoiceEngineSelectionTests.swift` (10/10). Regression:
    `VoiceProviderSelectionTests` (8/8), `PiMonoWiringTests` (24/24),
    `BYOKPaywallTests` (9/9) — all green, confirming the new UI wiring compiles and
    the native realtime path is untouched.
- **Pass 2 (M) done this iteration:** the working loop.
  - New `Sources/RealtimeOmni/SubscriptionCascadeCoordinator.swift` — turn-lifecycle
    state machine (`.idle` → `.thinking(startedAt:)` → `.speaking` → `.idle`, or
    `.failed(CascadeTurnError)`) that takes an already-finalized transcript, checks
    `CascadeTurnError` preconditions (ChatGPT connected, `codex` binary present,
    transcript non-blank) via a pure `precondition(transcript:chatGPTConnected:
    codexInstalled:)`, then runs the reasoning leg and speaks the reply. Owns no I/O
    itself — the three legs (ChatGPT connection check, reasoning, speak) are injected
    closures; `init()` wires the real defaults (a **dedicated**
    `ChatProvider(bridgeHarnessOverride: .codex)` instance — separate from the app's
    main chat `ChatProvider` so a cascade voice turn never touches the visible chat's
    bridge mode/messages — plus `FloatingBarVoicePlaybackService.shared.speakOneShot`).
    `SubscriptionCascadeCoordinator.shared` is the runtime singleton. A second `runTurn`
    call while `.thinking`/`.speaking` is dropped (never stacks); `.failed` self-heals
    on the next `runTurn` (no manual dismiss required, though `reset()` exists for one).
    Mid-turn auth expiry (connection flag flips false between the precondition check and
    the reasoning leg returning) is classified as the same `.chatGPTNotConnected` story
    as a cold-start disconnect, per design doc §4d.
  - `VoiceEngineSelection.isAvailable(.chatGPTSubscriptionCascade, chatGPTConnected:)`
    now returns `chatGPTConnected` (was hard-coded `false` in Pass 1) —
    `SubscriptionCascadeCoordinator` exists to actually run the loop now.
    `chatGPTCascadeSubtitle` copy updated from "Coming soon" to describe the live
    tradeoff (thinking, not full realtime; no new OpenAI API bill).
  - `voiceEngineChatGPTCascadeRow` (`SettingsContentView+Advanced.swift`) is a real
    selector now, not the Pass 1 `.disabled(true)` placeholder: a new
    `@AppStorage("voiceEngineSelection")` (`SettingsPage.swift`) persists the user's
    choice; the button writes it (gated by the same `VoiceEngineSelection.isAvailable`
    the runtime checks, so it can't be tappable-but-inert), and shows a checkmark +
    "Switch back" once selected.
  - `PushToTalkManager` wiring — the actual runtime hookup, not just a settings toggle:
    a new `static func effectiveVoiceEngine()` reads the persisted selection +
    `CodexAccountAuth.isConnected()` fresh on every call (no caching, so a
    connect/disconnect between two PTT turns takes effect immediately). Two call sites:
    `startAudioTranscription()` skips native-realtime-hub mode and forces the omni-STT
    path when the cascade engine is effective (the hub is BYOK/Omi-token funded, never
    the ChatGPT plan, so a cascade turn must never enter hub mode); `sendQuery(_:
    wasFollowUp:)` routes the finalized transcript to
    `SubscriptionCascadeCoordinator.shared.runTurn(transcript:)` instead of the normal
    floating-bar pill/window dispatch. Both branches are no-ops for every existing user
    — nobody had `voiceEngineSelection = chatGPTSubscriptionCascade` persisted before
    this change, so `effectiveVoiceEngine()` always resolved to `.nativeRealtimeBYOK`
    and behavior is byte-for-byte unchanged unless a user explicitly connects ChatGPT
    AND selects the row.
  - **Honest limitation vs. the design doc's literal wording:** §4b describes the loop
    as "on-device STT (Parakeet)". In this codebase `LocalTranscriptionService`
    (Parakeet) is wired ONLY into the passive background memory-transcription pipeline
    (`AppState+Transcription.swift`) — the interactive PTT command loop this feature
    hooks into has never used it; it uses the existing omni-STT relay (falls back to
    Deepgram) that already ran for every PTT turn regardless of voice engine. The
    coordinator is STT-technology-agnostic by design (it takes an already-finalized
    transcript string, per §4b/§5's "receive final transcript from the STT service" /
    "fake STT source"), so this doesn't weaken the "no new OpenAI Platform bill" claim
    — the STT leg's cost was already being paid before this feature existed, unaffected
    by which reasoning engine a turn uses. Wiring literal on-device Parakeet into the
    interactive command loop (new mic-capture plumbing, different windowing than the
    10 s background-memory windows) is a separate, larger piece of work, not attempted
    this pass.
  - **Tests:** new `Tests/SubscriptionCascadeCoordinatorTests.swift` (20/20) — pure
    `precondition` cases, `CascadeTurnError.userMessage` copy, happy path
    (transcript → reason → speak → idle), `.thinking` observed mid-flight via a
    manually-released `CheckedContinuation` (no sleeps), every precondition failure
    never touches reason/speak, provider-error vs. mid-turn-auth-expiry
    classification, never-stacks-a-second-turn (deterministic, continuation-gated),
    `reset()`, and self-heal after a prior failure. `Tests/VoiceEngineSelectionTests.swift`
    updated for Pass 2 semantics (11/11 — was 10/10 in Pass 1; the "always false" /
    "always says coming soon" assertions were rewritten to assert the new
    connection-tracking behavior, the same kind of intentional test update as item 6's
    `testAIProviderAllContainsSupportedProviders` fix). Regression, unchanged and
    green: `VoiceProviderSelectionTests` (8/8), `PiMonoWiringTests` (24/24),
    `BYOKPaywallTests` (9/9), `CodexAccountAuthTests` (7/7). 79/79 total across all
    six suites, 0 failures. The full package (`swift test --filter
    SubscriptionCascadeCoordinatorTests`) also compiles clean, confirming the
    `SettingsPage.swift` / `SettingsContentView+Advanced.swift` / `PushToTalkManager
    .swift` edits build correctly, not just the isolated coordinator file.
  - **NOT verified this pass (needs a live session, out of scope per the runtime
    guardrails):** a real `codex login` + connected ChatGPT account; actually holding
    ⌥, speaking, and hearing a reply come back through the ChatGPT/Codex bridge; a
    real mid-turn token expiry; confirming the settings row's checkmark/"Switch back"
    round-trips visually in the running app; confirming `startRealtimeHubCapture` is
    genuinely never entered when the cascade is selected (traced by code reading, not
    an instrumented run). Manual QA script for whoever runs this next: connect ChatGPT
    in Advanced → AI Setup, tap "Use this" on the ChatGPT-plan row, hold ⌥ and speak,
    confirm a spoken reply comes back and no floating-bar pill/window opened; then
    disconnect ChatGPT and confirm the row shows "Connect ChatGPT first" again and a
    PTT turn falls back to native realtime.
- **Pass 3 (S) done this iteration — item 8 now fully closed except live manual QA.**
  - **Surprise finding that reshaped the pass:** the design doc's Pass 3 framing
    ("swap system `AVSpeech` for the chunked neural-TTS backend") was already true by
    accident. Pass 2's speak leg calls `FloatingBarVoicePlaybackService.speakOneShot`,
    which resolves `ShortcutSettings.selectedVoiceID` — and the app's shipped default
    (`defaultVoiceID = openAIShimmerVoiceID`) is ALREADY an OpenAI **neural** voice
    synthesized via `APIClient.synthesizeSpeech` (backend TTS proxy `v1/tts/synthesize`),
    with automatic system-voice fallback baked into `speakOneShot`'s catch path and
    `startPlayback(fallbackText:)`. All four selectable voices in
    `ShortcutSettings.availableVoices` are OpenAI neural; that picker has no
    system-voice option at all. So the literal "swap" had nothing to swap.
  - **What reading the real wiring surfaced instead (the honest gap Pass 3 fixed):**
    the neural leg rides `APIClient.buildHeaders`, which forwards the user's own BYOK
    keys whenever `APIKeyService.isByokActive` (all four providers configured). A
    full-BYOK user's own OpenAI key silently pays for cascade TTS — quietly
    contradicting `chatGPTCascadeSubtitle`'s "no new OpenAI API bill" promise that
    `VoiceEngineSelectionTests` treats as an invariant. Also noted: `speakOneShot`'s
    neural path is single-shot (one synthesis call per reply, not the chunked
    `updateStreamingResponseIfEnabled` pipeline) — fine for cascade v1 turn lengths.
  - New pure `Sources/CascadeVoiceQualitySelection.swift` — `Quality` enum
    (`system` / `neural`), `defaultQuality = .neural` (matches the app-wide default
    sound), `forcesSystemVoice`, and `costSubtitle(quality:isByokActive:)` with
    honest per-state copy: `.system` = always free, no network call (identical copy
    under both BYOK states — it's an unconditional guarantee); `.neural` + BYOK
    active = "may bill your own key"; `.neural` without BYOK = "no bill to you."
    Mirrors `VoiceEngineSelection`'s no-I/O style.
  - `FloatingBarVoicePlaybackService.speakOneShotSystemVoice(_:)` — new entry point
    that forces `AVSpeechSynthesizer` and can never reach `APIClient.synthesizeSpeech`
    (so it can never carry a forwarded BYOK key).
  - `SubscriptionCascadeCoordinator.convenience init()` speak leg now reads the
    persisted `cascadeVoiceQuality` fresh on every turn (no caching, same pattern as
    `PushToTalkManager.effectiveVoiceEngine()`): `.system` → the hard
    `speakOneShotSystemVoice` guarantee; `.neural` (default) → Pass 2's `speakOneShot`
    byte-for-byte unchanged, including its built-in graceful fallback to system voice
    when neural synthesis/playback fails or the backend is unreachable. The
    injected-closure seam is untouched — all 20 coordinator tests run against fakes
    exactly as before.
  - Settings UI: new `voiceCascadeQualityRow` (`SettingsContentView+Advanced.swift`)
    directly under `voiceEngineChatGPTCascadeRow` in the Voice Model card — minimal
    "Voice quality (ChatGPT plan)" menu picker (System voice / Neural (when
    available)) + cost subtitle driven by `CascadeVoiceQualitySelection.costSubtitle`
    reading the real `APIKeyService.isByokActive` gate. New
    `@AppStorage("cascadeVoiceQuality")` in `SettingsPage.swift`. Scoped to the
    cascade engine only — `ShortcutSettings.selectedVoiceID` and every other
    floating-bar voice reply are untouched.
  - **Tests:** new `Tests/CascadeVoiceQualitySelectionTests.swift` (11/11) — enum
    shape, default-is-neural, `forcesSystemVoice`, and the cost-copy invariants
    (`.system` copy identical under both BYOK states; `.neural` copy differs by BYOK
    state, mentions the user's own key when BYOK is active, promises "no bill" only
    when that's true). Regression, all green this pass:
    `SubscriptionCascadeCoordinatorTests` (20/20), `VoiceEngineSelectionTests`
    (11/11), `VoiceProviderSelectionTests` (8/8), `PiMonoWiringTests` (24/24),
    `BYOKPaywallTests` (9/9), `CodexAccountAuthTests` (7/7). 90/90 total across seven
    suites, 0 failures; the full test target compiles clean (confirming the
    `SettingsPage` / `SettingsContentView+Advanced` / playback-service edits build,
    not just the pure files).
  - **⚠️ MANUAL QA STILL REQUIRED — the one thing left open on item 8.** Nothing in
    this item has ever been verified with a live session (dream-iteration guardrail:
    no real codex login, no live network TTS). Script for whoever runs it next:
    (1) connect ChatGPT in Advanced → AI Setup, tap "Use this" on the ChatGPT-plan
    row, hold ⌥ and speak — confirm a spoken reply comes back (neural Shimmer voice
    by default) and no floating-bar pill/window opened; (2) flip Voice quality to
    "System voice", repeat — confirm the system voice speaks and NO
    `v1/tts/synthesize` request fires (proxy/Console check); (3) with full BYOK
    configured, confirm the neural subtitle warns about billing the user's own key;
    (4) disconnect ChatGPT — row shows "Connect ChatGPT first" and a PTT turn falls
    back to native realtime; (5) real mid-turn token expiry — "reconnect ChatGPT"
    story, never silence.

---

## Secondary (value 2–3, mostly S/M, low risk)

- **claude.ai web blocked by OMI OAuth** — documented limitation; the claude.ai web
  bridge is blocked by OMI's OAuth. Needs a native provider-auth path (this branch's
  theme). Value 3 · Effort L · Risk Med.
- **[DONE this iteration] Pill `describeActivity` fallback is bare "Working…"**
  (`AgentPill.swift:~1144`) — was: once no tool call and no finished text exist yet
  in a message, the fallback was a static ellipsis even when the agent's own
  `.thinking` block already had real reasoning text sitting right there, discarded.
  Built: `describeActivity` now captures the most-recent non-empty `.thinking` block's
  text while scanning newest-first, and returns it (truncated to 110 chars, same limit
  as the other branches) if no tool call or finished text ever turns up — a completed
  tool call or finished text still always wins over it (unchanged priority order).
  Made the function `nonisolated static` (was `private`, `@MainActor`-isolated via the
  class) so `AgentPillDescribeActivityTests` can call it synchronously with synthetic
  `ChatMessage`s — same testability pattern this file already uses for
  `providerDirective`/`floatingAgentHandoff`. Tests: new
  `Tests/AgentPillDescribeActivityTests.swift` (15/15) — regression coverage for every
  existing branch (tool call + summary, most-recent-tool-wins, finished text, streaming
  text skipped/falls back to an earlier tool, empty message) plus the new thinking
  fallback (most-recent-wins, 110-char truncation, empty/whitespace-only thinking
  doesn't suppress "Working…", tool call and finished text still win over an earlier
  thinking block, discoveryCard still skipped and doesn't block the fallback).
  Regression: `AgentPillLifecycleTests` (48/48), `PiMonoWiringTests` (24/24),
  `AgentVMCallerInvariantTests` (2/2) — all green.
- **[DONE this iteration — audited, no logic change] `replaceWithAutomationPills`
  seeds "SLEEP FOR 5" demo content** (`AgentPill.swift:~970`, was line 947) — traced
  every caller: `replaceWithAutomationPills` ← `FloatingControlBarWindow
  .seedSubagentsForAutomation` ← `DesktopAutomationBridge.swift:614`, the ONLY call
  site anywhere in `Sources`. `DesktopAutomationBridge` is a loopback-only
  (127.0.0.1) HTTP listener gated by `DesktopAutomationLaunchOptions.isEnabled`; it
  is never wired to any menu item, button, or other UI affordance — there is no path
  from normal app usage to this function. Verdict: **not reachable via any UI in any
  build**, but it is reachable over localhost in more builds than the code's own
  comment claimed — the pre-existing comment said the bridge "is never enabled on the
  production bundle," which was false as written: `isEnabled` also returns true for
  the *production* bundle if launched with `--automation-bridge` or
  `OMI_ENABLE_LOCAL_AUTOMATION=1` (auto-enable is what's restricted to
  non-production bundles; the explicit flag/env-var opt-ins are not bundle-gated at
  all). No ordinary user launch sets either, so this is a deliberate scripted-QA
  escape hatch, not a shipped-content bug — left the mechanism as-is (changing it
  would touch the team's QA harness for Release-configuration builds, well outside
  a Value-3/Effort-S/Risk-Low audit) and fixed the misleading comment instead. Also
  added a doc comment directly on `replaceWithAutomationPills` recording the
  reachability chain and pointing at the corrected comment, so the next person
  auditing this doesn't have to re-trace it. No `#if DEBUG` gate added — it would be
  the wrong gate for this codebase's convention (runtime bundle-id/flag checks via
  `AppBuild.isNonProduction`, not compile-time DEBUG, specifically so QA can drive
  Release-configuration non-production-bundle builds) and the function is already
  unreachable without deliberately enabling the bridge. Files touched:
  `Sources/DesktopAutomationBridge.swift` (comment only), `Sources/FloatingControlBar/
  AgentPill.swift` (doc comment only). No tests added for this half — no logic
  changed, matches iteration 6's "clean audit, no code change" precedent.
- **[DONE — covered by item 4] AgentVMService `pollUntilReady` swallows the timeout**
  (`AgentVMService.swift:115`) — now transitions `AgentVMStatusStore` to `.timedOut`
  and posts a one-shot system notification on every give-up path. Value 2 · Effort S ·
  Risk Low.
- **StallThresholds are first-pass guesses** (`StallThresholds.swift:31`, 8s/20s) and
  `AgentStallNarration` (45s/120s) — tune both against real inter-event-gap
  distributions once telemetry exists. Value 2 · Effort S · Risk Low.
- **Onboarding doesn't wire StallDetector** (`OnboardingChatView.swift:1989`) — the
  onboarding chat can't show slow/stalled. Low priority. Value 1 · Effort M · Risk Low.

## Testing / hardening gaps
- No UI/snapshot test that the notch agent row actually renders the stall subtitle
  (pure logic is covered; view wiring is not). Value 2 · Effort M · Risk Low.
- `AgentVMService` itself still has no tests (network + Process shell-out) — item 4
  added coverage for the new `AgentVMStatusStore`/`AgentVMStallLogic` it feeds, but
  the actor's provision/poll/upload/sync methods remain untested. Value 2 · Effort M.

---

## Iteration shipped 2026-07-05 (branch `feat/native-provider-auth-v0.12.0`)

Three features built, tested, committed, pushed, and installed as incremental
siempre builds (siempre4 → siempre7 / build 12002 → 12006). Current installed
version: **siempre7 / 12006**.

### 9. [DONE this iteration] Screen capture self-heal — stop clobbering `screenAnalysisEnabled`
- **Value 5 · Effort M · Risk Med** — screen capture was breaking on every re-sign.
- Was: `ProactiveAssistantsPlugin` clobbered `screenAnalysisEnabled = false` at six
  call sites whenever `CGPreflightScreenCaptureAccess()` returned false transiently
  on launch (the OS returns false before the first window gains focus). One TCC
  reset and the feature was dead until manually re-armed.
- Built (commit `033a1cebf`, siempre4 / 12003):
  - Extracted `permissionNotGrantedError` as a static constant (was a string
    literal duplicated across 4 call sites — fragile).
  - Changed 4 call sites to NOT clobber `screenAnalysisEnabled` on transient
    preflight failures — only the user-intent toggle path flips it now.
  - Added one-shot self-heal paths gated behind `screenAnalysisSelfHeal_v3` flag —
    fires once per install to recover from a stale TCC grant without fighting
    user intent.
  - Fixed `RewindPage` notification-observer clobber on the same flag.
  - Tests: `Tests/ScreenCaptureSelfHealTests.swift` (7/7). Regression: 51 suites, 0 failures.
- Verified live: TCC grant landed, `screenAnalysisEnabled = 1`, `Capture timer set to 9.0s`,
  `Screenshot captured 3024x1964` — frames flowing.
- **Recurring breakage root cause (honest):** every ad-hoc re-sign changes the cdhash,
  making the prior TCC grant stale. macOS won't write a new grant while a
  `/Volumes/omi/omi.app` ghost lingers in Launch Services (leftover DMG entry).
  Mitigation: `~/Desktop/DROPBOX/fix-omi-screen-capture.sh` — one-command fix that
  resets TCC, re-registers with Launch Services, clears the self-heal migration flag,
  re-arms `screenAnalysisEnabled`, and relaunches. **Permanent fix:** a stable Apple
  Developer certificate so the signature stops churning ($99/yr), OR stop ad-hoc
  re-signing for every change.

### 10. [DONE this iteration] Live cost-aware model router — re-route real traffic to cheapest capable provider
- **Value 4 · Effort M · Risk Med** — Alex pays for multiple providers; the app
  should use the cheapest one that can handle the workload.
- Built (commit `f52134631`, siempre5 / 12004):
  - `Sources/FloatingControlBar/CostAwareModelRouter.swift` — `Route` enum,
    `Workload` enum (`.light` / `.balanced` / `.heavy`), `Availability` struct,
    `route(workload:availability:)` → cheapest capable route, `bridgeMode(for:)` →
    `ChatProvider.BridgeMode` mapping.
  - `ChatProvider.applyCostAwareRouting(workload:)` (line 947) — guards on the
    toggle (`costAwareRoutingEnabled`), checks `!isSending && !modeSwitchInProgress`,
    routes, and calls `switchBridgeMode(to:)` if the target differs from the current.
  - Called at `ChatProvider.sendMessage()` (line 3356) before every non-follow-up
    send — follow-ups keep the original provider.
  - Settings toggle "Auto-route to cheapest" in Advanced → AI Setup, opt-in
    (`shortcut_costAwareRoutingEnabled`).
  - Tests: `Tests/CostAwareModelRouterTests.swift` (13/13).
- Verified live: code path traced end-to-end, binary strings present, opt-in toggle
  ready. Won't fire until Alex toggles it on.

### 11. [DONE this iteration] Agent voice announcements — speak results aloud when agents finish
- **Value 4 · Effort S · Risk Low** — Alex wants audible feedback when an agent
  completes a task so he doesn't have to keep checking the screen.
- Built (commit `cc4be3408`, siempre6 / 12005):
  - `AgentPill.complete()` calls `speakOneShot(spokenSummary(...))` when
    `ShortcutSettings.agentVoiceAnnouncementsEnabled` is true (defaults to true).
  - `spokenSummary(from:)` — `nonisolated static` helper on `AgentPillsManager`
    (pure function, no actor state). Strips markdown headers (`(?m)^#\\s+`),
    bullets (`(?m)^[-*]\\s+`), code fences, and collapses whitespace to produce a
    clean spoken line. Uses `(?m)` inline flag for multiline matching (not
    `.anchorsMatchLines` — fragile across Swift versions).
  - `ShortcutSettings.agentVoiceAnnouncementsEnabled` — new setting, defaults to
    true (opt-out).
  - Tests: `Tests/AgentVoiceAnnouncementTests.swift` (10/10) — regex cleanup edge
    cases, spoken summary shape, enable/disable flag.
- Diagnostic log lines added (commit `d5443665b`, siempre7 / 12006) at both
  `AgentPill.complete()` and `FloatingBarVoicePlaybackService.speakOneShot()` so
  we can verify the TTS fires end-to-end. Verified in-binary; will fire on the
  next agent completion.
- **Next step (not yet built):** Alex wants the spoken summary structured as
  "question, answer, next steps and follow up" instead of the raw result. This is
  item 12 below.

### 12. [DONE this iteration] Structured spoken summary — question / answer / next steps / follow-up
- **Value 4 · Effort S · Risk Low** — Alex explicitly asked for the spoken summary
  to be structured, not just the raw result read aloud.
- Built:
  - `AgentPillsManager.structuredSpokenSummary(query:answer:followUps:)` — pure,
    `nonisolated static`. Assembles four parts: "You asked: <query>." / "Here's what
    I found: <cleaned answer>." / "Next: <next steps>." / "Want me to go further?
    Just say so." Empty parts are skipped so we never read "blank. blank."
  - `AgentPillsManager.spokenAnswer(from:)` — factored out of the old `spokenSummary`
    so the structured path can reuse the markdown-stripping/truncation logic. Truncation
    lowered from 500 → 300 chars so the structured summary (which adds question +
    next-steps + follow-up framing) doesn't run too long.
  - `AgentPillsManager.extractNextSteps(from:)` — pure sentence-action detector.
    Splits on `.`, `!`, `?`, then flags sentences containing action keywords
    ("next", "should", "need to", "TODO", "I'll", "I will", "recommend", "suggest")
    OR starting with an imperative verb (open, run, check, verify, review, update,
    create, delete, send, write, fix, build, test, deploy, install, git). Caps at 2
    candidates. Falls back to the derived `suggestedFollowUps` if the answer has no
    detectable action lines.
  - `AgentPill.complete()` call site now calls `structuredSpokenSummary` with
    `pill.query`, the cleaned final text, and `pill.suggestedFollowUps` (derived
    before the voice call so they're available).
  - `spokenSummary(from:)` is now a thin wrapper over `spokenAnswer` — the old
    single-arg API is preserved so existing call sites and tests don't break.
  - Tests: `Tests/AgentPillSpokenSummaryTests.swift` (21/21) — all 10 original
    markdown/stripping/truncation tests updated for the 300-char limit, plus 11 new
    tests covering the structured summary (all four parts present, follow-up
    fallback when no actions in answer, next-step extraction from answer, empty
    query handling, long-query truncation, no-next-line when no follow-ups and no
    actions, imperative-starter detection, action-keyword detection, 2-candidate cap,
    empty-result case, follow-up always last).

## Notes for future iterations
- The in-app bridge path (AgentPill / ChatProvider / AgentRuntimeStatusStore /
  StallDetector) is mature and well-tested — build ON it, don't rebuild it.
- The cloud VM path is the genuinely-dark corner. Items 4 + 5 are where the "ghosting"
  reputation actually lives.
- Disk on the build Mac is tight (~2–3 GB free). Avoid `swift package reset` (forces a
  full rebuild); incremental `swift test --filter` is the safe verify loop.
