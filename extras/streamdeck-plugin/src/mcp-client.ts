export const MCP_PROTOCOL_VERSION = "2025-06-18";
export const DEFAULT_MCP_HOST = "127.0.0.1";
export const DEFAULT_MCP_PORT = 41773;

export type AllowedLoopbackHost = "127.0.0.1" | "localhost";

export interface MCPConnectionConfig {
  host?: string;
  port?: number;
  bearerToken: string;
}

export interface MCPToolCallOutcome {
  ok: boolean;
  message: string;
  structuredContent?: Record<string, unknown>;
}

export class MCPError extends Error {
  readonly statusCode?: number;
  readonly errorCode?: string;

  constructor(message: string, statusCode?: number, errorCode?: string) {
    super(message);
    this.name = "MCPError";
    this.statusCode = statusCode;
    this.errorCode = errorCode;
  }
}

/**
 * Strictly validates that the configured host is local loopback (`127.0.0.1` or `localhost`)
 * and builds the local Streamable HTTP `/mcp` endpoint URL.
 */
export function buildLoopbackMCPEndpoint(hostRaw?: string, portRaw?: number): string {
  const normalizedHost = (hostRaw ?? DEFAULT_MCP_HOST).trim().toLowerCase();
  if (normalizedHost !== "127.0.0.1" && normalizedHost !== "localhost") {
    throw new MCPError(
      `Refusing non-loopback MCP host "${normalizedHost}". Only 127.0.0.1 or localhost is permitted.`,
      undefined,
      "invalid_loopback_host"
    );
  }

  const port = portRaw ?? DEFAULT_MCP_PORT;
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new MCPError(
      `Invalid local MCP port "${String(port)}". Expected an integer between 1024 and 65535.`,
      undefined,
      "invalid_port"
    );
  }

  const parsed = new URL(`http://${normalizedHost}:${port}/mcp`);
  if (parsed.hostname !== "127.0.0.1" && parsed.hostname !== "localhost") {
    throw new MCPError("Resolved host failed loopback verification.", undefined, "invalid_loopback_host");
  }
  return parsed.toString();
}

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Streamable HTTP (`2025-06-18`) MCP client strictly bound to `127.0.0.1` / `localhost`.
 * Performs `initialize` + `notifications/initialized` session handshake, caches `Mcp-Session-Id`,
 * re-initializes on `404` expired sessions, and backs off on `429`.
 */
export class GlassGridMCPClient {
  private config: MCPConnectionConfig;
  private sessionId: string | null = null;
  private requestCounter = 1;
  private initPromise: Promise<string> | null = null;

  constructor(config: MCPConnectionConfig) {
    this.config = { ...config };
  }

  updateConfig(config: MCPConnectionConfig): void {
    const endpointChanged =
      (config.host ?? DEFAULT_MCP_HOST) !== (this.config.host ?? DEFAULT_MCP_HOST) ||
      (config.port ?? DEFAULT_MCP_PORT) !== (this.config.port ?? DEFAULT_MCP_PORT) ||
      config.bearerToken !== this.config.bearerToken;

    this.config = { ...config };
    if (endpointChanged) {
      this.sessionId = null;
      this.initPromise = null;
    }
  }

  private get endpoint(): string {
    return buildLoopbackMCPEndpoint(this.config.host, this.config.port);
  }

  private requireBearerToken(): string {
    const token = (this.config.bearerToken ?? "").trim();
    if (!token) {
      throw new MCPError(
        "Missing Bearer token. Configure it in Stream Deck Property Inspector from GlassGrid You → Settings → AI & Automation.",
        401,
        "missing_bearer_token"
      );
    }
    return token;
  }

  private buildHeaders(includeSession: boolean): Record<string, string> {
    const headers: Record<string, string> = {
      "Authorization": `Bearer ${this.requireBearerToken()}`,
      "Content-Type": "application/json",
      "Accept": "application/json",
      "MCP-Protocol-Version": MCP_PROTOCOL_VERSION
    };
    if (includeSession && this.sessionId) {
      headers["Mcp-Session-Id"] = this.sessionId;
    }
    return headers;
  }

  private async postJSONRPC(
    payload: Record<string, unknown>,
    includeSession: boolean,
    maxRateLimitRetries = 2
  ): Promise<{ status: number; sessionHeader: string | null; json: Record<string, unknown> | null }> {
    let attempt = 0;
    while (true) {
      const response = await fetch(this.endpoint, {
        method: "POST",
        headers: this.buildHeaders(includeSession),
        body: JSON.stringify(payload)
      });

      if (response.status === 401) {
        this.sessionId = null;
        throw new MCPError(
          "Unauthorized (401): Bearer token rejected by GlassGrid You.",
          401,
          "unauthorized"
        );
      }

      if (response.status === 429) {
        if (attempt >= maxRateLimitRetries) {
          throw new MCPError("Rate limited (429) by GlassGrid You MCP server.", 429, "rate_limited");
        }
        const retryAfterRaw = response.headers.get("retry-after");
        const retryAfterSec = retryAfterRaw ? Number.parseFloat(retryAfterRaw) : Number.NaN;
        const baseDelayMs = Number.isFinite(retryAfterSec) && retryAfterSec > 0
          ? Math.min(retryAfterSec * 1000, 5000)
          : Math.min(250 * Math.pow(2, attempt), 2000);
        const jitterMs = Math.floor(Math.random() * 100);
        attempt += 1;
        await sleepMs(baseDelayMs + jitterMs);
        continue;
      }

      const sessionHeader = response.headers.get("mcp-session-id");
      const text = await response.text();
      let json: Record<string, unknown> | null = null;
      if (text.trim().length > 0) {
        try {
          const parsed: unknown = JSON.parse(text);
          if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
            json = parsed as Record<string, unknown>;
          }
        } catch {
          json = null;
        }
      }

      return { status: response.status, sessionHeader, json };
    }
  }

  async ensureSession(): Promise<string> {
    if (this.sessionId) {
      return this.sessionId;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = (async () => {
      try {
        const initId = this.requestCounter++;
        const initRes = await this.postJSONRPC(
          {
            jsonrpc: "2.0",
            id: initId,
            method: "initialize",
            params: {
              protocolVersion: MCP_PROTOCOL_VERSION,
              capabilities: {},
              clientInfo: {
                name: "com.glassgridyou.streamdeck",
                version: "1.5.0"
              }
            }
          },
          false
        );

        if (initRes.status < 200 || initRes.status >= 300) {
          throw new MCPError(
            `MCP initialize failed with HTTP ${initRes.status}.`,
            initRes.status,
            "initialize_failed"
          );
        }

        const sid = initRes.sessionHeader?.trim();
        if (!sid) {
          throw new MCPError(
            "MCP server did not return an Mcp-Session-Id header.",
            initRes.status,
            "missing_session_id"
          );
        }
        this.sessionId = sid;

        await this.postJSONRPC(
          {
            jsonrpc: "2.0",
            method: "notifications/initialized"
          },
          true
        );

        return sid;
      } finally {
        this.initPromise = null;
      }
    })();

    return this.initPromise;
  }

  async callTool(name: string, args: Record<string, unknown> = {}): Promise<MCPToolCallOutcome> {
    await this.ensureSession();

    const makePayload = () => ({
      jsonrpc: "2.0",
      id: this.requestCounter++,
      method: "tools/call",
      params: {
        name,
        arguments: args
      }
    });

    let res = await this.postJSONRPC(makePayload(), true);

    // 404 indicates an evicted or expired Mcp-Session-Id: re-initialize once and retry.
    if (res.status === 404) {
      this.sessionId = null;
      await this.ensureSession();
      res = await this.postJSONRPC(makePayload(), true);
    }

    if (res.status < 200 || res.status >= 300) {
      throw new MCPError(`MCP tools/call(${name}) failed with HTTP ${res.status}.`, res.status, "http_error");
    }

    const rpcError = res.json?.["error"];
    if (rpcError && typeof rpcError === "object") {
      const errObj = rpcError as Record<string, unknown>;
      throw new MCPError(String(errObj["message"] ?? "MCP JSON-RPC error"), res.status, "rpc_error");
    }

    const result = res.json?.["result"];
    if (result && typeof result === "object") {
      const resultObj = result as Record<string, unknown>;
      const structured = resultObj["structuredContent"] as Record<string, unknown> | undefined;
      const isError = resultObj["isError"] === true;
      const message = typeof structured?.["message"] === "string"
        ? structured["message"]
        : (isError ? `${name} failed` : `${name} ok`);

      if (isError) {
        const code = typeof structured?.["errorCode"] === "string" ? structured["errorCode"] : "tool_error";
        throw new MCPError(message, res.status, code);
      }

      return {
        ok: true,
        message,
        structuredContent: structured
      };
    }

    return { ok: true, message: `${name} ok` };
  }
}
