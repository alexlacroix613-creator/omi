/**
 * Localhost HTTP MCP server that exposes Omi's tools (memories, screen history,
 * tasks, SQL, semantic search, …) to ACP agents that accept MCP servers over
 * the HTTP transport but reject command/stdio configs spawned under their own
 * sandbox.
 *
 * This is the path used by the Codex/ChatGPT adapter: `@agentclientprotocol/
 * codex-acp` advertises `mcpCapabilities.http:true` and maps an HTTP MCP entry
 * to `{ url, http_headers }` in the Codex session config, while the Claude ACP
 * adapter uses the command/stdio server (`omi-tools-stdio.ts`) instead.
 *
 * Design:
 * - Runs IN the bridge process (index.ts), bound to 127.0.0.1 on an ephemeral
 *   port. Never listens on a routable interface.
 * - Every request must carry `Authorization: Bearer <token>` with a random
 *   per-run token. Requests without the exact token get 401 and never reach a
 *   tool. The token and URL are never logged.
 * - Tool definitions come from the canonical manifest (single source of truth,
 *   shared with the stdio server).
 * - Tool CALLS are forwarded to Swift by connecting to the same Unix-socket
 *   relay the stdio server uses (`OMI_BRIDGE_PIPE`). That reuses the bridge's
 *   existing tool correlation, control-tool handling, and Swift forwarding
 *   verbatim — this file adds only the HTTP transport + auth on top.
 */

import { createServer, type IncomingMessage, type ServerResponse } from "http";
import { createConnection, type Socket } from "net";
import { randomBytes, timingSafeEqual } from "crypto";
import {
  mcpToolDefinitionsForAdapter,
  normalizeOmiToolName,
} from "./runtime/omi-tool-manifest.js";

export interface OmiToolsHttpServerOptions {
  /** Path to the bridge's omi-tools Unix-socket relay (OMI_BRIDGE_PIPE). */
  bridgePipePath: string;
  /** Adapter id used for tool-call correlation on the relay (e.g. "codex"). */
  adapterId: string;
  /** Optional structured logger. Must never receive the token or URL. */
  log?: (message: string) => void;
}

export interface OmiToolsHttpServerHandle {
  /** Loopback URL to hand to the ACP agent's session/new mcpServers entry. */
  readonly url: string;
  /** Random bearer token required on every request. */
  readonly token: string;
  /** Update the ask/act mode used for write-gating (call per query). */
  setMode(mode: "ask" | "act"): void;
  /** Shut the server and relay connection down. */
  close(): Promise<void>;
}

const TOOL_CALL_TIMEOUT_MS = 120_000;

/**
 * Start the HTTP MCP server. Resolves once it is listening on loopback.
 */
export async function startOmiToolsHttpServer(
  options: OmiToolsHttpServerOptions
): Promise<OmiToolsHttpServerHandle> {
  const log = options.log ?? (() => {});
  const adapterId = options.adapterId;
  const token = randomBytes(32).toString("hex");
  const expectedAuth = Buffer.from(`Bearer ${token}`);

  let currentMode: "ask" | "act" = "act";

  // Non-onboarding tool projection — codex sessions are never onboarding.
  const TOOLS = mcpToolDefinitionsForAdapter("omi-tools-stdio", {});

  // --- Relay client (forward tool calls to Swift via the bridge relay) ---

  const pendingToolCalls = new Map<
    string,
    { resolve: (result: string) => void; timeout: ReturnType<typeof setTimeout> }
  >();
  let callIdCounter = 0;
  let relay: Socket | null = null;
  let relayBuffer = "";
  let closed = false;

  const connectRelay = (): void => {
    if (closed) return;
    const socket = createConnection(options.bridgePipePath, () => {
      log("omi-tools HTTP relay connected");
    });
    relay = socket;
    socket.on("data", (data: Buffer) => {
      relayBuffer += data.toString();
      let idx: number;
      while ((idx = relayBuffer.indexOf("\n")) >= 0) {
        const line = relayBuffer.slice(0, idx);
        relayBuffer = relayBuffer.slice(idx + 1);
        if (!line.trim()) continue;
        try {
          const msg = JSON.parse(line) as {
            type?: string;
            callId?: string;
            result?: string;
          };
          if (msg.type === "tool_result" && msg.callId) {
            const pending = pendingToolCalls.get(msg.callId);
            if (pending) {
              pendingToolCalls.delete(msg.callId);
              clearTimeout(pending.timeout);
              pending.resolve(msg.result ?? "");
            }
          }
        } catch {
          log("omi-tools HTTP relay: failed to parse relay line");
        }
      }
    });
    socket.on("error", (err) => {
      log(`omi-tools HTTP relay error: ${err.message}`);
    });
    socket.on("close", () => {
      relay = null;
      // Fail any in-flight calls so HTTP requests don't hang forever.
      for (const [callId, pending] of pendingToolCalls) {
        pendingToolCalls.delete(callId);
        clearTimeout(pending.timeout);
        pending.resolve("Error: omi-tools relay disconnected");
      }
      if (!closed) {
        // Reconnect lazily on the next tool call rather than hot-looping here.
      }
    });
  };

  const ensureRelay = (): Socket => {
    if (!relay || relay.destroyed) {
      connectRelay();
    }
    return relay!;
  };

  const forwardTool = (
    name: string,
    input: Record<string, unknown>
  ): Promise<string> => {
    const callId = `omi-http-${++callIdCounter}-${Date.now()}`;
    return new Promise<string>((resolve) => {
      const socket = ensureRelay();
      if (!socket) {
        resolve("Error: omi-tools relay unavailable");
        return;
      }
      const timeout = setTimeout(() => {
        if (pendingToolCalls.delete(callId)) {
          resolve("Error: timed out waiting for tool result");
        }
      }, TOOL_CALL_TIMEOUT_MS);
      pendingToolCalls.set(callId, { resolve, timeout });
      try {
        // No requestId/clientId/protocolVersion: the relay resolves the active
        // request for this adapter via adapter-scoped correlation.
        socket.write(
          JSON.stringify({ type: "tool_use", callId, name, input, adapterId }) + "\n"
        );
      } catch (err) {
        if (pendingToolCalls.delete(callId)) {
          clearTimeout(timeout);
          resolve(`Error: failed to dispatch tool call: ${err}`);
        }
      }
    });
  };

  // --- JSON-RPC (MCP) handling ---

  const textResult = (id: unknown, text: string): Record<string, unknown> => ({
    jsonrpc: "2.0",
    id,
    result: { content: [{ type: "text", text }] },
  });

  const handleToolCall = async (
    id: unknown,
    params: Record<string, unknown>
  ): Promise<Record<string, unknown>> => {
    const rawName = params.name as string;
    const { canonicalName } = normalizeOmiToolName("omi-tools-stdio", rawName);
    const args = (params.arguments ?? {}) as Record<string, unknown>;

    const advertised = TOOLS.some((tool) => tool.name === canonicalName);
    if (!advertised) {
      return {
        jsonrpc: "2.0",
        id,
        error: { code: -32601, message: `Unknown tool: ${rawName}` },
      };
    }

    // Write-gate: in ask mode only SELECT SQL is permitted, mirroring the
    // stdio server so the HTTP path is not a way around read-only mode.
    if (canonicalName === "execute_sql" && currentMode === "ask") {
      const query = String(args.query ?? "").trim().toUpperCase();
      if (!query.startsWith("SELECT")) {
        return textResult(
          id,
          "Blocked: Only SELECT queries are allowed in Ask mode. Switch to Act mode to run UPDATE/INSERT/DELETE."
        );
      }
    }

    const result = await forwardTool(canonicalName, args);
    return textResult(id, result);
  };

  const handleJsonRpc = async (
    body: Record<string, unknown>
  ): Promise<Record<string, unknown> | null> => {
    const id = body.id;
    const method = body.method as string;
    const params = (body.params ?? {}) as Record<string, unknown>;
    const isNotification = id === undefined || id === null;

    switch (method) {
      case "initialize":
        return {
          jsonrpc: "2.0",
          id,
          result: {
            protocolVersion: "2024-11-05",
            capabilities: { tools: {} },
            serverInfo: { name: "omi-tools", version: "1.0.0" },
          },
        };
      case "notifications/initialized":
        return null; // notification — no response body
      case "tools/list":
        return { jsonrpc: "2.0", id, result: { tools: TOOLS } };
      case "tools/call":
        return handleToolCall(id, params);
      default:
        if (isNotification) return null;
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32601, message: `Method not found: ${method}` },
        };
    }
  };

  // --- HTTP transport ---

  const readBody = (req: IncomingMessage): Promise<string> =>
    new Promise((resolve, reject) => {
      let data = "";
      req.on("data", (chunk: Buffer) => {
        data += chunk.toString();
      });
      req.on("end", () => resolve(data));
      req.on("error", reject);
    });

  const authorized = (req: IncomingMessage): boolean => {
    const header = req.headers["authorization"];
    if (typeof header !== "string") return false;
    const provided = Buffer.from(header);
    if (provided.length !== expectedAuth.length) return false;
    return timingSafeEqual(provided, expectedAuth);
  };

  const server = createServer(async (req: IncomingMessage, res: ServerResponse) => {
    if (!authorized(req)) {
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", error: { code: -32001, message: "Unauthorized" } }));
      return;
    }

    if (req.method === "POST") {
      try {
        const body = await readBody(req);
        const parsed = JSON.parse(body) as Record<string, unknown>;
        const result = await handleJsonRpc(parsed);
        if (result === null) {
          res.writeHead(202);
          res.end();
          return;
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(result));
      } catch {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ jsonrpc: "2.0", error: { code: -32700, message: "Parse error" } }));
      }
      return;
    }

    if (req.method === "GET") {
      // Some MCP HTTP clients open a GET stream for server→client messages.
      // This server is request/response only, so decline the stream cleanly.
      res.writeHead(405, { Allow: "POST" });
      res.end();
      return;
    }

    res.writeHead(405, { Allow: "POST" });
    res.end();
  });

  connectRelay();

  const url = await new Promise<string>((resolve, reject) => {
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      if (addr && typeof addr === "object") {
        resolve(`http://127.0.0.1:${addr.port}/`);
      } else {
        reject(new Error("Failed to resolve omi-tools HTTP server address"));
      }
    });
  });

  log("omi-tools HTTP MCP server listening on loopback");

  return {
    url,
    token,
    setMode(mode: "ask" | "act") {
      currentMode = mode;
    },
    async close() {
      closed = true;
      for (const [callId, pending] of pendingToolCalls) {
        pendingToolCalls.delete(callId);
        clearTimeout(pending.timeout);
        pending.resolve("Error: omi-tools HTTP server closed");
      }
      relay?.destroy();
      relay = null;
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}
