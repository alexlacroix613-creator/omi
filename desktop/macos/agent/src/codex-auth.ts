/**
 * Codex / ChatGPT-account authentication status.
 *
 * The Codex agent (via @agentclientprotocol/codex-acp and the bundled
 * @openai/codex) authenticates the user's ChatGPT subscription by reading
 * ~/.codex/auth.json, which the `codex login` CLI writes after the browser
 * OAuth handshake. Connection status is defined purely by the presence of a
 * usable access token in that file.
 *
 * Tokens rotate, so callers MUST read fresh on every check — never cache the
 * parsed contents. These helpers open and parse the file on each call.
 */

import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

export interface CodexAuthStatus {
  /** Absolute path that was inspected. */
  path: string;
  /** Whether ~/.codex/auth.json exists and is readable. */
  exists: boolean;
  /** Whether the file parsed and carries a non-empty tokens.access_token. */
  hasAccessToken: boolean;
}

/** Resolve the auth.json path for a given home directory (defaults to $HOME). */
export function codexAuthPath(home: string = homedir()): string {
  return join(home, ".codex", "auth.json");
}

/**
 * Read ~/.codex/auth.json fresh and report whether a ChatGPT/Codex access token
 * is present. Any read/parse failure is treated as "not connected" rather than
 * throwing, so callers can gate on a simple boolean.
 */
export function readCodexAuth(home: string = homedir()): CodexAuthStatus {
  const path = codexAuthPath(home);
  let raw: string;
  try {
    raw = readFileSync(path, "utf8");
  } catch {
    return { path, exists: false, hasAccessToken: false };
  }

  return { path, exists: true, hasAccessToken: authTextHasAccessToken(raw) };
}

/**
 * Parse the raw auth.json text and report whether it carries a non-empty
 * `tokens.access_token`. Exposed separately so it can be unit-tested without
 * touching the filesystem.
 */
export function authTextHasAccessToken(raw: string): boolean {
  try {
    const parsed = JSON.parse(raw) as { tokens?: { access_token?: unknown } };
    const token = parsed?.tokens?.access_token;
    return typeof token === "string" && token.trim().length > 0;
  } catch {
    return false;
  }
}

/** True when a usable ChatGPT/Codex token is present right now. */
export function isCodexAuthenticated(home: string = homedir()): boolean {
  return readCodexAuth(home).hasAccessToken;
}
