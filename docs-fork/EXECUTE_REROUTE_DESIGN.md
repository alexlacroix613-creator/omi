# EXECUTE_REROUTE_DESIGN — DREAM_BACKLOG item 5

**Reroute Execute away from the ghosting cloud VM to a reporting agent**
Value 5 · Effort L · Risk High · Design-only pass (no source changed)

Branch: `feat/native-provider-auth-v0.12.0` · Swift package root: `desktop/macos/Desktop`
Author: dream cycle 5 (design). Prior context: cycle 4 (commit `0165fd00d`, item 4).

---

## TL;DR (the one-paragraph answer)

**Execute is NOT ghosting today.** Every user-triggered Execute in the desktop app already
routes to the mature **local reporting-agent path** (`AgentPillsManager.spawn` /
`spawnFromUserQuery` → `AgentPill` → `AgentRuntimeStatusStore` → `StallDetector` /
`AgentStallNarration`), which streams session/update events and now narrates stalls
(items 1–3, done). The "ghosting cloud VM" (`AgentVMService`) **never receives an Execute
task and never returns task output** — it is a one-way *memory-database replica* pipeline
(upload `omi.db` → incrementally sync rows → hand the VM a Firebase token so a *server-side*
agent elsewhere can query the user's data). So the "reroute" the backlog imagined is
**already the architecture**: there is nothing left to route away from the VM, because the
desktop's Execute never went there. The real remaining work is small and preventive, not the
big-L rebuild the backlog feared: (1) **lock the invariant** so no *future* Execute can
silently route a task to the fire-and-forget VM without a reporting channel; (2) **finish the
honest relabelling** of the VM's user-facing surface so nobody mistakes "Cloud Sync" for task
execution; and (3) **spec** (do not yet build) the reporting channel that a hypothetical
"run this in the cloud" feature would need. The genuinely unfixable part is honest and stated
below: the desktop cannot stream events a cloud backend it does not control never emits.

---

## 1. Evidence — every caller of the cloud VM path, traced

Method: `grep` over `Sources/**.swift` for `AgentVMService`, `provisionAgentVM`,
`getAgentStatus`, `AgentVMStatusStore`, plus every `AgentPillsManager.spawn*` call site, plus
any dispatch of a user query to a VM IP / `:8080` / `/execute`. All tags `[DIRECT]` unless noted.

### 1a. The cloud VM (`AgentVMService`) — who calls it, and what for

`[DIRECT]` Only three call sites exist, all background/lifecycle, none user-Execute:

| Caller | Line | Trigger | Purpose |
|---|---|---|---|
| `DesktopHomeView.scheduleAgentVMProvisioning()` | `Sources/MainWindow/DesktopHomeView.swift:705` | app-launch **warmup** (delayed via `StartupWarmupPolicy.agentVMProvisioningDelay`) | `ensureProvisioned()` — make sure a replica VM exists |
| `OnboardingView` completion | `Sources/OnboardingView.swift:502` | onboarding finishes | `startPipeline()` — first-time provision + DB upload |
| `AgentSyncService` | `Sources/AgentSyncService.swift:220` | detected `databaseReady:false` on the VM mid-sync | `reuploadDatabase(...)` — repair a VM that lost its data |

`[DIRECT]` What the pipeline actually does (`AgentVMService.swift`, read in full):
`provision (POST v2/agent/provision)` → `pollUntilReady (GET v2/agent/status)` →
`uploadDatabase` (gzip `omi.db`, POST to `http://<vmIP>:8080/upload`) →
`startIncrementalSync` (`AgentSyncService` POSTs row deltas to `<vmIP>:8080/sync` every 3s) →
`sendFirebaseToken` (POST `<vmIP>:8080/auth` so the VM "can call backend tools").
**It is pure data egress + a credential.** There is no code path where the desktop sends the
VM a *task/prompt* or reads a *result/answer* back.

`[DIRECT]` Confirmed absence of a task-dispatch-to-VM: grepping for `vmIP` + `/query` /
`/chat` / `/execute` / `/run` returns only `AgentVMService`/`AgentSyncService`'s own
upload/sync endpoints and one unrelated **local** automation-bridge route
(`DesktopAutomationBridge.swift:1026 POST /execute-export`, a memory-export helper, nothing to
do with the VM). The VM never sees a user query.

`[INFERRED]` The pipeline's *consumer* lives outside this desktop app. `AgentStatusResponse`
carries a `lastQueryAt: String?` field (`APIClient.swift:5308`), i.e. the backend records when
the VM was last *queried* — but nothing in the desktop issues that query. The replica exists so
OMI's **cloud/mobile chat agent** (a different client) can answer questions over the user's
memory without the desktop being awake. The desktop is a *producer* to this pipeline, never a
consumer.

### 1b. Execute — where user-triggered execution actually goes

`[DIRECT]` Every Execute surface routes to the **local** pill path, not the VM:

| Surface | Line | Call |
|---|---|---|
| Tasks page Execute button | `Sources/MainWindow/Pages/TasksPage.swift:4387` | `AgentPillsManager.shared.spawn(query:model:)` |
| Floating control bar | `Sources/FloatingControlBar/FloatingControlBarView.swift:848` | `AgentPillsManager.shared.spawn(...)` |
| Floating bar window (send/handoff) | `Sources/FloatingControlBar/FloatingControlBarWindow.swift:2743/2779/2824` | `spawnFromUserQuery` / `spawnFromHandoff` |
| Realtime voice hub | `Sources/FloatingControlBar/RealtimeHubController.swift:1051` | `spawnFromUserQuery` |
| Chat tool executor | `Sources/Providers/ChatToolExecutor.swift:488` | `spawnFromUserQuery` |
| Memory export | `Sources/MemoryExportExecutor.swift:349` | `spawn(...)` |

`[DIRECT]` This is exactly the mature path the backlog's "Notes for future iterations"
tells us to build **on**, not rebuild: `AgentPill` / `AgentPillsManager` / `ChatProvider` /
`AgentRuntimeStatusStore` / `StallDetector` / `AgentStallNarration`. Items 1–3 already added
live elapsed-time narration + stall escalation + a pill-popover Stop button to it.

### 1c. Verdict on the backlog's hypothesis

The backlog said: *"Today's user-triggered Execute already uses the local bridge/pill path
(good). The cloud VM is only used by background DB sync."* **Verified true, in full.** The
"reroute" is therefore ~90% already done *by construction*. Item 5 is not an L rebuild; it is
an S/M **invariant-lock + honesty + forward-spec** job. The "High risk" rating in the backlog
was priced against a rebuild that turns out to be unnecessary — actual risk is Low/Med (see §6).

---

## 2. The honest conclusion first (per the brief's option 4)

There are two truths to hold at once:

1. **Client-side, Execute is already fixed.** Nothing the user Executes ghosts; it all lands on
   an instrumented local pill. Cycle 4 additionally made the *background* VM pipeline visible
   (the "Cloud Sync" status card + failure/timeout system notifications). So the two named
   complaints — "silence forever" and "Execute does nothing visible" — are addressed for every
   path the desktop actually controls.

2. **The residual ghosting is inherent to a backend the desktop does not own, and cannot be
   fully fixed here.** The cloud VM is designed to *become* an autonomous agent (it registers
   backend tools and holds a full memory replica). If OMI's backend ever runs a task *on* that
   VM, the desktop has **no channel to stream that agent's session/update events back** — the
   status endpoint (`v2/agent/status`) reports *VM lifecycle* (`ready`/`provisioning`/`error`),
   not *task progress*. You cannot render events the server never emits. Any promise of
   "live cloud task narration" is therefore a **backend** feature request, not a desktop one.

So the correct design is **not** "move Execute onto the VM and stream it" (the server can't feed
that yet) and **not** "leave a trap door open for a future Execute-on-VM to ghost." It is:
**keep Execute local, make that a guarded invariant, tell the truth about what the VM is, and
write down the exact contract a cloud-Execute would have to meet before anyone builds one.**

---

## 3. Target design

### 3a. Principle: one reporting substrate, the local one

`AgentRuntimeStatusStore` + `AgentPill` is the single source of truth for "what is my agent
doing right now." Any execution the user initiates — local today, cloud tomorrow — must render
through it. The VM's fire-and-forget model is banned from ever carrying a user task *unless* it
first adapts its events into this store. This is the whole design in one sentence.

### 3b. What must NOT be rerouted (protect the legitimate VM job)

The DB-replica pipeline is load-bearing for the *cloud/mobile* product and must keep running
untouched: `ensureProvisioned` / `startPipeline` / `reuploadDatabase` / `AgentSyncService`
stay exactly as-is. This design adds **zero** changes to the sync pipeline's behavior. The only
VM-facing changes contemplated are (i) labelling and (ii) a *new, additive* read-only session
channel that does not exist yet and is spec-only in this doc.

### 3c. The forward contract (spec only — do not build until a cloud-Execute is greenlit)

If a future feature wants "Execute this in the cloud," the VM side must expose a
**session-events stream**, and the desktop must adapt it into the local store. Concretely:

- **Backend prerequisite (not ours):** the VM exposes `GET http://<vmIP>:8080/session/<id>/events`
  as SSE or long-poll, emitting the same shape the local bridge already produces
  (`session.created`, `update`, `tool.start`, `tool.end`, `message`, `done`, `error`) plus a
  heartbeat. Without this, a cloud-Execute is not buildable and must not ship.
- **Desktop side (thin adapter):** a `CloudAgentSessionReader` that consumes that stream and
  drives an existing `AgentPill` through `AgentPillsManager` / `AgentRuntimeStatusStore` — so a
  cloud task reuses the *identical* pill UI, stall narration, and Stop affordance as a local one.
  The user cannot tell (or care) where it ran; they just see it working and can stop it.
- **Feature flag:** `AssistantSettings.cloudExecuteEnabled` (default `false`), gated *also* on
  the reader having received at least one heartbeat — so a dark/half-built backend can never
  present a live-looking-but-dead cloud task.
- **Backward-compat:** flag off = today's behavior byte-for-byte. No existing user is touched.

This contract is deliberately **written, not coded** — building the adapter against a backend
endpoint that does not exist yet would be speculative and untestable (and the brief is
design-only). It exists so a future iteration builds the right thing instead of re-opening the
ghost.

---

## 4. Work split — concrete dream-sized passes

Ordered so each pass is independently shippable and verifiable. Only Passes A–B are worth
building now; Pass C is the gated future build.

### Pass A (S · Risk Low) — Lock the invariant + document it at the chokepoint
- **Goal:** make "Execute is local-only" an *enforced, discoverable* fact, not an accident that
  a future PR could quietly break by pointing an Execute at `AgentVMService`.
- **Where:** `AgentPillsManager` (the single spawn chokepoint) and `AgentVMService`.
  - Add a header doc-comment to `AgentVMService` stating in one line: *"Data-replica pipeline
    only. Never dispatch a user task here — Execute routes through `AgentPillsManager`. A cloud
    task must adapt into `AgentRuntimeStatusStore` first (see EXECUTE_REROUTE_DESIGN.md §3c)."*
  - Add the mirror comment above `AgentPillsManager.spawn` / `spawnFromUserQuery`: *"Sole entry
    point for user-initiated execution. Keep it that way."*
- **Optional guard (still S):** a `#if DEBUG` `assertionFailure` (or a `PiMonoWiringTests`
  assertion) that greps the built module / call graph to prove no Execute UI imports
  `AgentVMService`. Cheapest honest version: a source-level test in `Tests/` that asserts the
  set of `AgentVMService` callers equals the known background trio (fails loudly if a fourth
  caller appears). See test plan.
- **Files:** `Sources/AgentVMService.swift`, `Sources/FloatingControlBar/AgentPillsManager*`,
  `Tests/` (new small wiring test).
- **No behavior change.**

### Pass B (S · Risk Low) — Finish the honesty pass on the VM's user-facing surface
- **Goal:** the surface Cycle 4 shipped is already honestly named "Cloud Sync" (not "agent") —
  good. Close the remaining gap: make the *subtitle/help text* say plainly this is a **memory
  backup replica for cloud/mobile answers**, and that **your tasks run locally on this Mac** —
  so a user who reads it never expects the card to show Execute progress.
- **Where:** `cloudSyncStatusCard` and its `cloudSyncSubtitle` in
  `Sources/MainWindow/Pages/Settings/Sections/SettingsContentView+Assistants.swift:~1186`; the
  `.idle` label in `AgentVMState.label` (`Sources/AgentVMStatusStore.swift:27`) could read
  "Idle — tasks run on this Mac" or carry a one-line footnote under the card.
- **Also:** the `AgentVMStatusStore` header comment still calls this the *"cloud agent VM
  pipeline"* — reword to *"cloud memory-replica pipeline"* to kill the "agent = it runs my
  tasks" implication at the source.
- **Files:** `Sources/AgentVMStatusStore.swift`, `SettingsContentView+Assistants.swift`.
- **Test:** none needed (copy only); the existing `AgentVMStatusStoreTests` (10/10) stay green.

### Pass C (M · Risk Med — GATED, do not start until a cloud-Execute is actually wanted)
- **Goal:** build the §3c reporting channel so a cloud task reuses the local pill UI.
- **Preconditions (all required):** (1) product decision to offer cloud Execute; (2) backend
  ships `GET /session/<id>/events`; (3) an endpoint to *start* a cloud task returning a
  `sessionId`.
- **Build:** `Sources/CloudAgentSessionReader.swift` (SSE/long-poll consumer, pure event→store
  mapping extracted for unit test); wire it behind `AssistantSettings.cloudExecuteEnabled` +
  heartbeat gate; adapt events onto an `AgentPill` via `AgentPillsManager`.
- **Do NOT** start this pass speculatively. If picked up while the backend endpoint is still
  absent, the correct output is a one-line note "blocked on backend" — not a mock.

---

## 5. Test plan

- **Pass A:**
  - New `Tests/AgentVMCallerInvariantTest` (pure, S): assert the documented invariant — e.g. a
    small source-scan test, or (simpler and deterministic) extend `PiMonoWiringTests` with an
    assertion that Execute entry points resolve to `AgentPillsManager`, and a comment-backed
    guard that `AgentVMService` is background-only. Must fail if a new `AgentVMService` caller is
    added outside the trio.
  - Regression: `AgentVMStatusStoreTests` (10/10), `PiMonoWiringTests` (24/24) stay green.
- **Pass B:** copy-only; `AgentVMStatusStoreTests` (10/10) unchanged. Manual: open
  Settings → Advanced → Troubleshooting, confirm the card reads as *backup/sync*, not *execution*.
- **Pass C (when built):** pure `CloudAgentSessionReader` event→`AgentRuntimeStatusStore`
  mapping tests (created/update/tool/done/error/heartbeat-timeout → stalled), mirroring
  `AgentStallNarrationTests`. Flag-off no-op test. Live QA: start a cloud task, confirm a pill
  appears, narrates, and Stop works — then kill the backend mid-task and confirm the pill shows
  "stalled/failed", never silent.
- **Build-Mac constraint (from backlog):** disk is tight (~2–3 GB). Use incremental
  `swift test --filter <Suite>`; never `swift package reset`.

## 6. Risk / rollback

- **Passes A–B are Low risk:** comments + copy + one additive test. No runtime path changes; the
  DB-sync pipeline is untouched. Rollback = revert the doc-comment/copy commit.
- **The backlog's "High risk" was priced for a rebuild that this trace shows is unnecessary.**
  Re-rate item 5 to **Low/Med** for the work actually worth doing now.
- **Residual (honest, unfixable here):** if OMI's backend one day runs tasks on the VM *without*
  shipping the §3c events endpoint, the desktop still can't narrate them. That is a backend
  dependency, flagged here so it is a conscious product choice, not a silent regression. The
  Pass A guard is the tripwire: it makes any attempt to route Execute at the VM fail a test
  loudly instead of shipping a new ghost.
- **Do-not-touch list:** `AgentSyncService`, `ensureProvisioned`, `startPipeline`,
  `reuploadDatabase`, `provisionAgentVM`, `getAgentStatus` — all load-bearing for the cloud/mobile
  product's memory replica. This design changes none of them.

---

## 7. One-line status for the backlog

> **Item 5 — reframed by code trace:** Execute already runs 100% local (instrumented pill path);
> the "ghosting cloud VM" is a one-way memory-replica pipeline that never carries a task. Reroute
> is already the architecture. Remaining work = Pass A (lock the local-only invariant + guard
> test, S) + Pass B (honest "Cloud Sync = backup, tasks run on this Mac" copy, S). Pass C (adapt a
> future cloud-task event stream into the local pill) is GATED on a backend endpoint that does not
> exist and must not be built speculatively. Re-rate Effort L→S+S, Risk High→Low/Med.
