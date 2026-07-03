import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { AcpRuntimeAdapter } from "./acp.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface CodexRuntimeAdapterOptions {
  log?: (message: string) => void;
}

/**
 * Codex adapter: drives OpenAI's Codex agent over ACP, authenticated with the
 * user's ChatGPT subscription account.
 *
 * Codex is bundled with the app (via the @agentclientprotocol/codex-acp npm
 * dependency), so — like the Claude `acp` adapter and unlike Hermes/OpenClaw —
 * it launches a Node entry point (`patched-codex-entry.mjs`) rather than
 * shelling out to a user-installed external command. The entry runs with the
 * full (Anthropic-key-stripped) environment so codex-acp can locate the user's
 * ChatGPT credentials at ~/.codex/auth.json via $HOME.
 *
 * Omi tools reach Codex over an HTTP-transport MCP server: codex-acp advertises
 * `mcpCapabilities.acp:false` (it rejects MCP proxied over the ACP transport)
 * but `mcpCapabilities.http:true`, and maps an HTTP MCP entry to
 * `{ url, http_headers }` in the Codex session config. The bridge starts a
 * loopback, bearer-token-protected HTTP MCP server (see `omi-tools-http.ts`)
 * and injects its entry via `buildMcpServers` when the adapter is "codex", so
 * per-session MCP servers must be passed through (sessionMcpServersMode:
 * "passthrough"). Model switching is disabled because Codex model ids differ
 * from Omi's Claude aliases.
 */
export class CodexRuntimeAdapter extends AcpRuntimeAdapter {
  constructor(options: CodexRuntimeAdapterOptions = {}) {
    super({
      adapterId: "codex",
      acpEntry: join(__dirname, "..", "patched-codex-entry.mjs"),
      sessionMcpServersMode: "passthrough",
      supportsSessionSetModel: false,
      log: options.log,
    });
  }
}
