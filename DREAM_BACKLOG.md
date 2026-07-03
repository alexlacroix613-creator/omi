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

### 5. Reroute Execute away from the ghosting cloud VM to a reporting agent
- **Value 5 · Effort L · Risk High** — the real structural fix; too big for one pass.
- Today's user-triggered Execute already uses the local bridge/pill path (good). The
  cloud VM is only used by background DB sync (`DesktopHomeView.swift:705`,
  `OnboardingView.swift:502`). If any future Execute is meant to run *on* the VM, it
  must stream status back. Design an agent that reports session/update events like the
  local bridge does, instead of a headless VM. Keep as an L design item.

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

### 8. ChatGPT-subscription realtime voice not wired
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
  / Pass 3 (S–M, optional neural TTS polish).
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
  - **Queued next: Pass 2 (M, medium risk)** — build
    `SubscriptionCascadeCoordinator` gluing `LocalTranscriptionService` →
    `ChatProvider(.userChatGPT)` → `FloatingBarVoicePlaybackService`, flip
    `VoiceEngineSelection.isAvailable(.chatGPTSubscriptionCascade, ...)` to
    `chatGPTConnected`, enable the row. Coordinator unit tests with fakes per the
    design doc §5; manual end-to-end verification needs a real `codex login`.

---

## Secondary (value 2–3, mostly S/M, low risk)

- **claude.ai web blocked by OMI OAuth** — documented limitation; the claude.ai web
  bridge is blocked by OMI's OAuth. Needs a native provider-auth path (this branch's
  theme). Value 3 · Effort L · Risk Med.
- **Pill `describeActivity` fallback is bare "Working…"** (`AgentPill.swift:1144`) —
  now partly covered by item 1's narration, but the base string could name the tool in
  flight when known. Value 2 · Effort S · Risk Low.
- **`replaceWithAutomationPills` seeds "SLEEP FOR 5" demo content** (`AgentPill.swift:947`)
  — looks like a dogfood/demo harness shipping in prod. Confirm it's test-only or gate it.
  Value 3 · Effort S · Risk Low.
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

## Notes for future iterations
- The in-app bridge path (AgentPill / ChatProvider / AgentRuntimeStatusStore /
  StallDetector) is mature and well-tested — build ON it, don't rebuild it.
- The cloud VM path is the genuinely-dark corner. Items 4 + 5 are where the "ghosting"
  reputation actually lives.
- Disk on the build Mac is tight (~2–3 GB free). Avoid `swift package reset` (forces a
  full rebuild); incremental `swift test --filter` is the safe verify loop.
