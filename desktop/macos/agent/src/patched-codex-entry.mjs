#!/usr/bin/env node
/**
 * Codex ACP entry point.
 *
 * Launches @agentclientprotocol/codex-acp as a stdio ACP agent server. That
 * package starts the Codex App Server (bundling @openai/codex), translates ACP
 * requests into Codex operations, and maps Codex events back to the client.
 *
 * Unlike patched-acp-entry.mjs — which monkey-patches ClaudeAcpAgent to recover
 * per-turn USD cost and token usage from the Claude Agent SDK — codex-acp ships
 * as a bundled CLI with no patchable JS agent class, and ChatGPT-plan usage is a
 * flat subscription (there is no per-turn USD cost to capture). So we simply run
 * it: our AcpRuntimeAdapter already speaks the same ACP methods (initialize,
 * session/new, session/prompt, session/update, session/cancel) at
 * protocolVersion 1, which codex-acp advertises.
 *
 * ChatGPT-account authentication is handled out of band via the `codex` CLI
 * (`codex login`, writing ~/.codex/auth.json). We set NO_BROWSER so codex-acp
 * never spontaneously opens a browser tab from inside the agent subprocess; the
 * desktop app owns the connect flow.
 */

// Keep stdout clean for JSON-RPC — route all console output to stderr.
console.log = console.error;
console.info = console.error;
console.warn = console.error;
console.debug = console.error;

// Never let the ACP server pop a browser on its own; the app drives login.
if (!process.env.NO_BROWSER) {
  process.env.NO_BROWSER = "1";
}

// Importing the bundled entry runs it (no main-module guard): it wires the ACP
// method handlers and calls .connect() on the stdio stream.
await import("@agentclientprotocol/codex-acp/dist/index.js");

// Keep the process alive for the stdio session.
process.stdin.resume();
