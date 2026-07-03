# Voice on a ChatGPT Subscription — Design (DREAM_BACKLOG item 8)

**Status:** Design only. No code changed. Branch `feat/native-provider-auth-v0.12.0`.
**Author pass:** dream iteration, 2026-07-03.
**Backlog item:** #8 — "ChatGPT-subscription realtime voice not wired" (Value 4 · Effort L · Risk Med).

Evidence tags: `[DIRECT]` = read in this repo · `[WEB]` = current public doc/issue · `[INFERRED]` = deduction.

---

## 0. Executive summary (the recommendation)

**Ground truth first, because it changes the whole ask:** a ChatGPT *subscription* login
(the Codex CLI OAuth token in `~/.codex/auth.json`) **cannot** authorize OpenAI's realtime
voice socket, or any OpenAI voice API, today. That token only funds ChatGPT-backend / Codex
*text* turns. OpenAI's Realtime API bills against the separate **Platform API** and needs a
funded `sk-` key. ChatGPT Advanced Voice Mode has no public API at all. This is confirmed by
OpenAI's own docs and by another project (OpenClaw) hitting the exact same wall. `[WEB]`

So "wire the ChatGPT subscription into GPT Realtime" is **not buildable** — the door is
locked on OpenAI's side, not ours.

**But Alex's actual want — "voice on the accounts I already pay for, not another API bill" —
IS buildable**, just not as native speech-to-speech. The fork already contains every piece of a
**cascade voice loop**: on-device speech-to-text (Parakeet) → reasoning through `ChatProvider`
(which can already run in ChatGPT/Codex mode) → spoken reply through the existing playback
service. Wiring item 8 = exposing that assembled loop as a first-class **"Voice via my ChatGPT
subscription"** choice, plus honest UI copy that native GPT Realtime still needs a bring-your-own
`sk-` key. `[DIRECT]`

**Recommendation: Option B (subscription cascade voice), shipped in two passes.** It gives Alex
real voice on his paid ChatGPT plan with zero new API bill, reuses mature code, and carries low
risk. Keep Option A (BYO `sk-` key = the only *native* realtime GPT path) exactly as-is and just
label it honestly. Reject any attempt to feed the Codex token to the realtime socket — it will
always 401.

Alternatives considered and why not:
- **A alone (BYO sk- key only):** honest but doesn't answer Alex's want (still an API bill).
- **C (wait for/upstream a fix):** nothing exists upstream; OpenAI offers no subscription voice API.

---

## 1. How voice authenticates today (code map)

Two distinct voice subsystems exist in-tree. Keeping them straight is the whole game.

### 1a. RealtimeHub — native speech-to-speech (audio + vision in one model)
- `Sources/FloatingControlBar/RealtimeHubController.swift` — owns one warm
  `RealtimeHubSession`. `ensureWarm()` (line ~321) picks auth: `[DIRECT]`
  - **BYOK branch:** if `APIKeyService.byokKey(provider.byokProvider)` returns a stored key,
    connect **client-direct** with it (`.byokKey`). For OpenAI that key is a real `sk-` Platform
    key; for Gemini a Google AI key.
  - **Managed branch:** else if signed into Omi, `mintAndConnect()` calls
    `APIClient.shared.mintRealtimeToken(provider:)` — Omi's **backend** mints a short-lived
    ephemeral token off *Omi's own* funded platform key, and the client connects with that.
- `Sources/FloatingControlBar/RealtimeHubSession.swift` — the actual socket. `[DIRECT]`
  - OpenAI: `wss://api.openai.com/v1/realtime?model=gpt-realtime-2`, header
    `Authorization: Bearer <auth.value>` where `auth.value` is **either** the BYOK `sk-` key
    **or** the ephemeral token (both are Platform-API credentials). (line ~389)
  - Gemini: `wss://generativelanguage.googleapis.com/…BidiGenerateContent` with the key/token.
- `Sources/RealtimeOmni/RealtimeOmniProvider` — the picker enum: `.auto`, `.geminiFlashLive`,
  `.gptRealtime2`. **No ChatGPT-subscription option exists here** — this is item 8's gap. `[DIRECT]`
- `Sources/VoiceProviderSelection.swift` — pure mapping of stored keys → picker state.
  `realtimeKeyStorageKey(forModel:)` proves the GPT realtime slot reads
  `BYOKProvider.openai.storageKey` — i.e. it *only* knows how to feed an `sk-` key. `[DIRECT]`

**Consequence:** every path into the GPT realtime socket carries a Platform-API credential
(`sk-` or an ephemeral minted from one). There is no code seam where a Codex OAuth token could
enter, and even if forced in, OpenAI rejects it (see §2). `[DIRECT]/[INFERRED]`

### 1b. The cascade — STT → reasoning → TTS (the pre-realtime path, still present)
- `Sources/RealtimeOmni/RealtimeOmniService.swift` header states it plainly: the omni model is
  "only the voice shell" and "Reasoning/tools are NOT done here — the transcript goes to
  `ChatProvider`… replaces Deepgram (STT) + OpenAI TTS in the cascade." `[DIRECT]`
- Speech-to-text: `Sources/LocalTranscriptionService.swift` (on-device Parakeet, Apple Silicon,
  no cloud) or Omi/BYO Deepgram — selected by `VoiceProviderSelection.TranscriptionChoice`
  (`onDevice` / `omiCloud` / `deepgramBYO`). `[DIRECT]`
- Reasoning brain: `Sources/Providers/ChatProvider.swift` — `BridgeMode` enum includes
  `userChatGPT = "codexCli"` (line ~902). `startChatGPTAuth()` shells out to real `codex login`;
  `isChatGPTConnected` is driven by `CodexAccountAuth.isConnected()` reading
  `~/.codex/auth.json`. In this mode, reasoning runs **on the ChatGPT subscription** via the
  codex-acp subprocess bridge. `[DIRECT]`
- Text-to-speech / playback: `Sources/FloatingControlBar/FloatingBarVoicePlaybackService.swift`
  — already supports chunked generated-audio playback **and** `AVSpeechSynthesizer` (system
  voice) as the no-audio fallback. `RealtimeHubController.speak(_:)` uses `AVSpeechUtterance`
  directly too. `[DIRECT]`

**Consequence:** a full voice loop that runs its brain on the ChatGPT subscription is ~90%
assembled from existing, shipping components. The missing 10% is UI wiring + a clean orchestrator,
not new infrastructure. `[INFERRED]`

### 1c. How the Codex text bridge authenticates (for contrast)
`Sources/Providers/CodexAccountAuth.swift`: connection = presence of a non-empty
`tokens.access_token` in `~/.codex/auth.json`, written by `codex login`'s own browser OAuth. The
app **never** extracts or forwards that token to any OpenAI HTTP/WS endpoint itself — it spawns
the `codex` CLI as an ACP subprocess and lets the CLI use its own token against the ChatGPT
backend. `[DIRECT]` This is the *only* sanctioned way that token is used, and it is text-only.

---

## 2. Ground truth: can a ChatGPT-plan token reach ANY OpenAI voice surface? — **No.**

| Question | Answer | Source |
|---|---|---|
| Does the Codex/ChatGPT OAuth token fund the Realtime API? | **No.** It funds ChatGPT-backend / Codex text turns only. | `[WEB]` OpenClaw issue #76498 (verbatim: "ChatGPT Plus/Pro/Codex subscription quota and `openai-codex/*` OAuth do not fund realtime Talk audio"). |
| What does the Realtime API require? | A funded **Platform API** `sk-` key; browser/mobile clients use an **ephemeral token minted server-side from that `sk-` key** (≈60s TTL). | `[WEB]` OpenAI Realtime guide + Realtime sessions API reference. |
| Is there a ChatGPT-subscription voice API (Advanced Voice Mode)? | **No public API.** App-only. | `[WEB]` OpenAI community + help center: ChatGPT Plus ≠ API access. |
| Does Codex OAuth work outside the CLI for other OpenAI APIs? | Only for ChatGPT-workspace / Codex entitlements. Not Platform API metered endpoints like Realtime. | `[WEB]` OpenAI Codex auth docs. |
| Has anyone shipped a workaround that routes the subscription into OpenAI voice? | **No.** Every project (OpenClaw, Cline, Roo-Code threads) concludes: use a separate funded Platform key, or route voice through a non-OpenAI shell. | `[WEB]` |

**Verdict: no direct path exists, and none is on OpenAI's roadmap publicly.** Any design that
tries to authorize `wss://api.openai.com/v1/realtime` with the Codex token is dead on arrival.
This is a valid, final finding — not a gap in our research. `[WEB]/[INFERRED]`

Sources:
- OpenAI Realtime guide — https://platform.openai.com/docs/guides/realtime
- OpenAI Realtime sessions (ephemeral tokens) — https://platform.openai.com/docs/api-reference/realtime-beta-sessions
- OpenAI Codex auth — https://developers.openai.com/codex/auth
- Using Codex with your ChatGPT plan — https://help.openai.com/en/articles/11369540
- OpenClaw issue #76498 (the exact parallel case) — https://github.com/openclaw/openclaw/issues/76498
- ChatGPT Plus ≠ API access (community) — https://community.openai.com/t/api-access-as-a-chatgpt-plus-subscriber/573409

---

## 3. Options evaluated

### Option A — Keep BYO `sk-` key as the only *native* GPT-realtime path; label it honestly
- **What:** leave RealtimeHub/GPT Realtime exactly as built. Fix only the UI copy so the GPT
  Realtime option clearly says "needs your own OpenAI API key (billed by OpenAI), not your ChatGPT
  subscription."
- **Pro:** zero risk, honest, already works. Native speech-to-speech + vision, lowest latency,
  barge-in.
- **Con:** does **not** satisfy Alex's want ("no new API bill"). It's a disclaimer, not a feature.
- **Effort:** S (copy only).

### Option B — Subscription cascade voice (**recommended**)
- **What:** expose a first-class voice mode = **STT (on-device Parakeet) → ChatProvider in
  `.userChatGPT` (Codex) mode → TTS (system `AVSpeech` first, optional neural TTS later)**. The
  brain runs on the ChatGPT plan Alex already pays for; **no OpenAI Platform bill**; transcription
  stays on-device (no Deepgram bill either).
- **Pro:** answers the real want. Reuses mature, shipping components (STT service, `ChatProvider`
  Codex bridge, playback service). No new credential surface — reuses the already-audited
  `CodexAccountAuth`. Works offline for STT+TTS; only the reasoning turn needs network.
- **Con / honest tradeoffs:**
  - **Not** true realtime speech-to-speech: it's turn-based (push-to-talk / VAD end-of-utterance →
    think → speak). Higher latency than GPT Realtime, no mid-sentence barge-in against the model's
    own generation, no *native* audio prosody.
  - **Vision:** RealtimeHub streams the screen *into* the model natively; the cascade cannot unless
    screenshots are passed as images to codex. Codex CLI is primarily text/code; screen-vision in
    the loop is **out of scope for v1** (documented limitation), or handled the way the app already
    does agent vision via `ChatProvider` tools. `[INFERRED]`
  - System TTS voice is robotic vs. GPT Realtime's native voice. Mitigated in the M pass with a
    neural TTS backend already used by the playback service's chunked-audio mode.
- **Effort:** M (mostly wiring), split S+M below.

### Option C — Adopt an upstream/community fix
- **Finding:** none exists. Upstream `BasedHardware/omi` recent work is about ChatGPT *connector*
  OAuth for MCP/text and realtime *reliability*, not subscription-funded voice. No PR/issue solves
  the billing wall. `[WEB]` So C collapses into "build B ourselves."

**Decision:** ship **B**, keep **A** as the honest native-realtime option beside it. They are
complementary rows in the same picker, not competitors.

---

## 4. Component-level plan for Option B

### 4a. New user-facing model
Add a third voice concept alongside "native realtime" and today's transcription picker: a
**Voice Engine** choice with two rows —
1. **GPT Realtime (bring your own OpenAI key)** — existing RealtimeHub path (Option A copy fix).
2. **My ChatGPT subscription (cascade)** — new Option B path.

Represent it as a new pure enum + mapping, mirroring `VoiceProviderSelection`'s no-I/O style so it
stays unit-testable and never drifts from runtime.

### 4b. Files to touch / add
- **New:** `Sources/VoiceEngineSelection.swift` — pure enum
  `{ nativeRealtimeBYOK, chatGPTSubscriptionCascade }` + derivation from persisted state
  (is a `sk-` key present? is `CodexAccountAuth.isConnected()`?), plus availability/disable logic
  ("subscription cascade unavailable until you connect ChatGPT" → deep-link to the existing
  `startChatGPTAuth()` flow). Pure, testable, no UI/IO — matches `VoiceProviderSelection.swift`.
- **New:** `Sources/RealtimeOmni/SubscriptionCascadeCoordinator.swift` (or extend
  `RealtimeOmniService`) — orchestrates one turn: receive final transcript from the STT service →
  submit to a `ChatProvider` pinned to `.userChatGPT` → stream the reply text into
  `FloatingBarVoicePlaybackService`. This is glue over existing services, not new transport.
- **Edit:** `Sources/RealtimeOmni/RealtimeOmniProvider.swift` **or** the settings view — surface
  the new Voice Engine row. Do **not** overload `RealtimeOmniProvider` (that enum is specifically
  multimodal-realtime models); add the engine choice one level up so GPT Realtime vs. subscription
  cascade is the first fork, and `.auto/gemini/gpt` only appears under "native realtime."
- **Edit:** the Advanced → AI Setup / Voice settings view (the one that renders the current Voice
  Model + Transcription pickers) — render the Voice Engine picker + honest subtitles. Reuse the
  existing "connect ChatGPT" card (`ChatProvider.startChatGPTAuth`, `isChatGPTConnected`) as the
  gating affordance.
- **Reuse untouched:** `LocalTranscriptionService` (STT), `CodexAccountAuth` (connection truth),
  `ChatProvider` Codex bridge (reasoning), `FloatingBarVoicePlaybackService` (TTS).

### 4c. Auth flow (Option B)
1. User picks "My ChatGPT subscription (cascade)." If `CodexAccountAuth.isConnected()` is false,
   the row is disabled with a "Connect ChatGPT" button → existing `startChatGPTAuth()` (`codex
   login`). No new OAuth code — this is the *already-audited* text-bridge auth. `[DIRECT]`
2. On a voice turn: STT runs on-device (no auth). Transcript → `ChatProvider` in `.userChatGPT`
   mode → the codex-acp subprocess uses its own `~/.codex/auth.json` token against the ChatGPT
   backend. The OMI process never touches the token. `[DIRECT]`
3. Reply text → playback service → spoken locally. No OpenAI Platform credential anywhere in the
   loop. `[INFERRED]`

### 4d. Failure modes & handling
- **ChatGPT not connected / token expired:** `isChatGPTConnected` flips false → disable the row,
  surface "Reconnect ChatGPT," and (per existing pattern) fall back to whatever the user's native
  realtime / cascade default is. Never silently do nothing (respects backlog complaints a & b).
- **codex CLI missing:** `CodexAccountAuth.locateCodexBinary()` returns nil → show the existing
  "install Codex" guidance (already implemented for the text bridge). `[DIRECT]`
- **Codex turn slow/stalled:** reuse the stall-narration work already shipped (items 1/3) — the
  cascade turn should surface "still thinking…" rather than dead air.
- **STT empty/garbled:** existing transcription-empty handling in the omni/cascade path applies.
- **TTS unavailable:** `AVSpeech` is the floor; it effectively never fails on macOS.

### 4e. What this deliberately does NOT do (documented limitations)
- No native speech-to-speech, no model-level barge-in, no screen-vision-into-model on the
  subscription path. Those remain the reason to keep Option A (BYO `sk-`) for users who want the
  premium realtime experience and accept the API bill.

---

## 5. Test plan
- **Pure logic (unit, fast, no I/O):**
  - `Tests/VoiceEngineSelectionTests.swift` — derivation from `(hasOpenAIKey, chatGPTConnected)`
    round-trips; availability/disable logic; deep-link gating. Mirror the existing
    `VoiceProviderSelectionTests` style. `[DIRECT]` (that test file already exists as the template).
  - Extend `VoiceProviderSelectionTests` if the transcription mapping is refactored under the new
    engine fork.
- **Coordinator seam (unit with fakes):** `SubscriptionCascadeCoordinator` against a fake STT
  source, a fake `ChatProvider` (or protocol seam) asserting it was invoked in `.userChatGPT`
  mode, and a fake playback sink — assert transcript→reason→speak ordering and that no OpenAI
  Platform credential is read on this path.
- **Manual / integration (documented, not automated — needs real codex login):**
  connect ChatGPT → pick subscription cascade → speak → hear reply; disconnect → row disables;
  expire token → graceful reconnect prompt.
- **Regression:** existing `RealtimeHub*Tests`, `CodexAccountAuthTests`, `FloatingBarVoiceResponse
  SettingsTests` must stay green — Option B must not alter the native realtime path.
- **Build discipline:** disk on the build Mac is tight; verify with incremental
  `swift test --filter VoiceEngineSelection` etc., never `swift package reset`. (per backlog note)

---

## 6. Effort estimate — split into dream-sized passes

- **Pass 1 (S, low risk) — honesty + scaffolding.** Fix Option A copy so GPT Realtime clearly
  states it needs a BYO OpenAI key (not the ChatGPT subscription). Add the pure
  `VoiceEngineSelection` enum + full unit tests. Add the disabled "My ChatGPT subscription
  (cascade) — coming in next pass" row wired to the real `startChatGPTAuth` gate. Ships value
  immediately (kills the "why won't my subscription work for voice" confusion) with near-zero risk.
- **Pass 2 (M, medium risk) — the working loop.** Build `SubscriptionCascadeCoordinator` gluing
  `LocalTranscriptionService` → `ChatProvider(.userChatGPT)` → `FloatingBarVoicePlaybackService`.
  Enable the row. Coordinator unit tests with fakes. Manual end-to-end verification with a real
  `codex login`.
- **Pass 3 (S–M, optional polish, deferrable) — neural TTS.** Swap system `AVSpeech` for the
  chunked neural-TTS backend the playback service already supports, so the subscription voice
  sounds less robotic. Independent; ship only if Alex wants nicer audio.

Original backlog sizing was **L**; splitting off the "no path to realtime" finding (which removes
the hardest imagined sub-problem — OAuth-into-realtime, which is simply impossible) drops the real
build to **M across passes 1–2**.

---

## 7. ToS / risk notes
- **Codex/ChatGPT ToS:** using `~/.codex/auth.json` via the official `codex` CLI as a subprocess is
  OpenAI's sanctioned flow (it's how Codex CLI itself works, and how OMI's *text* bridge already
  works, shipped). Option B introduces **no new** token handling — it reuses the audited path. `[DIRECT]`
- **Do NOT** attempt to extract the Codex `access_token` and present it as a Bearer to any
  `api.openai.com` endpoint — that both fails (§2) and would be an out-of-sanctioned-use of the
  token. The design explicitly forbids this.
- **Rate/usage:** subscription plans meter Codex usage; heavy voice use consumes ChatGPT-plan
  quota, not a metered API bill. This is exactly what Alex wants, but worth a one-line UI note so a
  burst of voice turns hitting a plan cap is understood, not surprising.
- **Privacy:** STT stays on-device (Parakeet) → only the transcript text leaves for reasoning, same
  surface as today's text ChatGPT bridge. No new audio egress.
- **Upstream drift:** if OpenAI ever ships a subscription-funded voice/realtime API, revisit — but
  as of 2026-07 none exists. `[WEB]`

---

## 8. One-line answer for Alex
"You can't put voice *directly* on your ChatGPT plan the fancy realtime way — OpenAI walls that
off behind a separate pay-per-use key. But we can give you real voice that *thinks* on the ChatGPT
plan you already pay for: your Mac listens and talks locally, and only the thinking goes to your
ChatGPT account. Slightly less snappy than the premium realtime voice, zero new bill."
