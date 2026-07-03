import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  authTextHasAccessToken,
  codexAuthPath,
  isCodexAuthenticated,
  readCodexAuth,
} from "../src/codex-auth.js";

describe("codex auth status (~/.codex/auth.json)", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codex-auth-test-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  function writeAuth(contents: string): void {
    const dir = join(home, ".codex");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "auth.json"), contents);
  }

  it("resolves the auth.json path under the home dir", () => {
    expect(codexAuthPath(home)).toBe(join(home, ".codex", "auth.json"));
  });

  it("reports not-connected when auth.json is absent", () => {
    const status = readCodexAuth(home);
    expect(status.exists).toBe(false);
    expect(status.hasAccessToken).toBe(false);
    expect(isCodexAuthenticated(home)).toBe(false);
  });

  it("detects a present, non-empty access token", () => {
    writeAuth(JSON.stringify({ tokens: { access_token: "sk-abc123" } }));
    const status = readCodexAuth(home);
    expect(status.exists).toBe(true);
    expect(status.hasAccessToken).toBe(true);
    expect(isCodexAuthenticated(home)).toBe(true);
  });

  it("treats an empty or missing access token as not-connected", () => {
    writeAuth(JSON.stringify({ tokens: { access_token: "   " } }));
    expect(readCodexAuth(home).hasAccessToken).toBe(false);

    writeAuth(JSON.stringify({ tokens: {} }));
    expect(readCodexAuth(home).hasAccessToken).toBe(false);

    writeAuth(JSON.stringify({ OPENAI_API_KEY: "sk-key" }));
    expect(readCodexAuth(home).hasAccessToken).toBe(false);
  });

  it("treats malformed JSON as not-connected without throwing (file still exists)", () => {
    writeAuth("{ not valid json");
    const status = readCodexAuth(home);
    expect(status.exists).toBe(true);
    expect(status.hasAccessToken).toBe(false);
  });

  it("authTextHasAccessToken parses raw text directly", () => {
    expect(authTextHasAccessToken('{"tokens":{"access_token":"t"}}')).toBe(true);
    expect(authTextHasAccessToken('{"tokens":{"access_token":""}}')).toBe(false);
    expect(authTextHasAccessToken("garbage")).toBe(false);
  });
});
