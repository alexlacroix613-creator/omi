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

### 4. Cloud VM Execute path (AgentVMService) is invisible and can silently die
- **Value 4 · Effort M · Risk Med** — the true "ghosting cloud VM" path.
- `AgentVMService.swift` (provision → poll → upload DB) is fire-and-forget with only
  `log(...)`; nothing reaches SwiftUI. `pollUntilReady` gives up after 30×5s with no
  user signal; provision failure just returns. `getAgentStatus`/`agentStartedAt`
  (APIClient.swift ~5293) are never surfaced.
- Fix: add an `@MainActor` observable (`AgentVMStatusStore`) fed by the pipeline
  (provisioning/queued/ready/failed/timed-out + timestamp), render a small settings
  card, and mark "stalled" when a run sits >N min. Pure stall helper reusable from item 1.

### 5. Reroute Execute away from the ghosting cloud VM to a reporting agent
- **Value 5 · Effort L · Risk High** — the real structural fix; too big for one pass.
- Today's user-triggered Execute already uses the local bridge/pill path (good). The
  cloud VM is only used by background DB sync (`DesktopHomeView.swift:705`,
  `OnboardingView.swift:502`). If any future Execute is meant to run *on* the VM, it
  must stream status back. Design an agent that reports session/update events like the
  local bridge does, instead of a headless VM. Keep as an L design item.

### 6. "Coming soon" provider placeholders may be dead toggles
- **Value 3 · Effort S · Risk Low**
- `APIKeyService.swift:55` — some providers "aren't wired into the desktop harness yet
  and are shown as honest 'coming soon' placeholders." Confirm each placeholder is
  either hidden or clearly disabled (not tappable-but-inert).
- Fix: audit the provider list; gate placeholders behind a `.disabled(true)` + label.

### 7. Rap slips the music filter (documented honest limitation)
- **Value 3 · Effort M · Risk Med**
- The mic-channel music filter (commit 133e28c0b, `MusicFilterGate`) still lets rap
  through because rap's speech-like cadence reads as conversation. Covered by
  `MusicFilterGateTests`.
- Fix: add a rap-specific heuristic (beat/BPM + repetition detection) or a second-pass
  classifier; expand test fixtures. Medium risk of false-positives muting real speech.

### 8. ChatGPT-subscription realtime voice not wired
- **Value 4 · Effort L · Risk Med** — known gap; Alex wants voice.
- `VoiceProviderSelection.swift` + realtime hub. BYOK realtime + Deepgram exist
  (commit fc952e0b4) but a ChatGPT *subscription* (not API key) realtime path isn't
  wired. Covered indirectly by `VoiceProviderSelectionTests`.
- Fix: add a subscription-auth provider option; likely needs an OAuth/token bridge like
  the OpenRouter PKCE work (commit 467519dd5). Design item.

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
- **AgentVMService `pollUntilReady` swallows the timeout** (`AgentVMService.swift:115`) —
  even without full UI (item 4), at least post a one-shot notification on give-up so the
  DB sync failure isn't silent. Value 2 · Effort S · Risk Low.
- **StallThresholds are first-pass guesses** (`StallThresholds.swift:31`, 8s/20s) and
  `AgentStallNarration` (45s/120s) — tune both against real inter-event-gap
  distributions once telemetry exists. Value 2 · Effort S · Risk Low.
- **Onboarding doesn't wire StallDetector** (`OnboardingChatView.swift:1989`) — the
  onboarding chat can't show slow/stalled. Low priority. Value 1 · Effort M · Risk Low.

## Testing / hardening gaps
- No UI/snapshot test that the notch agent row actually renders the stall subtitle
  (pure logic is covered; view wiring is not). Value 2 · Effort M · Risk Low.
- `AgentVMService` has no tests at all (network + Process shell-out). Value 2 · Effort M.

## Notes for future iterations
- The in-app bridge path (AgentPill / ChatProvider / AgentRuntimeStatusStore /
  StallDetector) is mature and well-tested — build ON it, don't rebuild it.
- The cloud VM path is the genuinely-dark corner. Items 4 + 5 are where the "ghosting"
  reputation actually lives.
- Disk on the build Mac is tight (~2–3 GB free). Avoid `swift package reset` (forces a
  full rebuild); incremental `swift test --filter` is the safe verify loop.
