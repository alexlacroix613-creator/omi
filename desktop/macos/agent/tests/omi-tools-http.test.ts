import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createServer, type Server } from "net";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  startOmiToolsHttpServer,
  type OmiToolsHttpServerHandle,
} from "../src/omi-tools-http.js";

/**
 * Focused coverage for the loopback HTTP MCP server that feeds Omi tools to the
 * Codex adapter: it must (1) start on loopback, (2) reject requests without the
 * exact bearer token, (3) serve the tool list to authorized callers, and (4)
 * enforce the ask-mode SQL write-gate before forwarding.
 */
describe("omi-tools HTTP MCP server", () => {
  let relay: Server;
  let handle: OmiToolsHttpServerHandle;
  let pipePath: string;
  let dir: string;

  beforeAll(async () => {
    dir = mkdtempSync(join(tmpdir(), "omi-http-test-"));
    pipePath = join(dir, "relay.sock");
    // Minimal relay stand-in — the auth/list paths never touch it, and the
    // ask-mode gate short-circuits before any tool call is forwarded.
    relay = createServer(() => {});
    await new Promise<void>((resolve) => relay.listen(pipePath, () => resolve()));
    handle = await startOmiToolsHttpServer({
      bridgePipePath: pipePath,
      adapterId: "codex",
    });
  });

  afterAll(async () => {
    await handle.close();
    await new Promise<void>((resolve) => relay.close(() => resolve()));
    rmSync(dir, { recursive: true, force: true });
  });

  const post = (body: unknown, token?: string): Promise<Response> =>
    fetch(handle.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
    });

  it("binds to loopback and mints a token", () => {
    expect(handle.url).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/$/);
    expect(handle.token).toMatch(/^[0-9a-f]{64}$/);
  });

  it("rejects requests with no Authorization header", async () => {
    const res = await post({ jsonrpc: "2.0", id: 1, method: "tools/list" });
    expect(res.status).toBe(401);
  });

  it("rejects requests with a wrong token", async () => {
    const res = await post(
      { jsonrpc: "2.0", id: 1, method: "tools/list" },
      "deadbeef"
    );
    expect(res.status).toBe(401);
  });

  it("serves tools/list to an authorized caller", async () => {
    const res = await post(
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      handle.token
    );
    expect(res.status).toBe(200);
    const json = (await res.json()) as {
      result: { tools: Array<{ name: string }> };
    };
    const names = json.result.tools.map((t) => t.name);
    expect(names).toContain("execute_sql");
    expect(names).toContain("semantic_search");
  });

  it("answers the initialize handshake", async () => {
    const res = await post(
      { jsonrpc: "2.0", id: 3, method: "initialize", params: {} },
      handle.token
    );
    expect(res.status).toBe(200);
    const json = (await res.json()) as { result: { protocolVersion: string } };
    expect(json.result.protocolVersion).toBeTruthy();
  });

  it("blocks non-SELECT SQL in ask mode without forwarding", async () => {
    handle.setMode("ask");
    const res = await post(
      {
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: {
          name: "execute_sql",
          arguments: { query: "DELETE FROM action_items" },
        },
      },
      handle.token
    );
    expect(res.status).toBe(200);
    const json = (await res.json()) as {
      result: { content: Array<{ text: string }> };
    };
    expect(json.result.content[0].text).toContain("Blocked");
    handle.setMode("act");
  });
});
