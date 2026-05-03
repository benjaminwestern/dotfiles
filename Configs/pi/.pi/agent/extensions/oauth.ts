/**
 * oauth — Client-credentials OAuth for Pi model providers.
 *
 * Transparently injects Bearer tokens into outgoing LLM provider HTTP requests.
 * No browser, no callback server, no refresh tokens — just grant_type=client_credentials
 * with in-memory caching, expiry-aware re-acquisition, and single invalid-token retry.
 *
 * ## How it works
 *
 * 1. Reads client-credentials config at extension load time and again on
 *    `/reload`. Search order is `~/.pi/agent/client-credentials.json`, then
 *    `.pi/client-credentials.json` in the Pi process cwd.
 * 2. Patches `globalThis.fetch` to intercept requests whose full URL starts
 *    with a configured `baseUrls` prefix. First matching provider wins.
 * 3. Acquires OAuth tokens via the configured token endpoint using the original,
 *    unpatched fetch, then caches tokens in memory with expiry tracking.
 * 4. Replaces (or adds) the configured auth header on every matching request;
 *    the default header is `Authorization`.
 * 5. On 401 or explicit invalid_token responses, clears the cached token,
 *    acquires a fresh one, and retries once.
 *
 * ## Canonical transport path
 *
 * OAuth for model providers is handled at the HTTP transport boundary.  The
 * required path is:
 *
 *   provider serializer / SDK → globalThis.fetch → OAuth interceptor → gateway
 *
 * Pi's built-in OpenAI-compatible providers (openai-completions,
 * openai-responses, etc.) construct their HTTP clients inside the stream
 * function at request time.  The OpenAI SDK resolves `globalThis.fetch` via
 * `getDefaultFetch()` at construction time, so patching `fetch` before the first
 * request intercepts all downstream calls.
 *
 * A custom `streamSimple` may still exist for provider-specific payload
 * serialization, but it must use `globalThis.fetch` for HTTP.  This extension
 * intentionally does not implement a parallel OAuth path inside streamSimple;
 * non-fetch HTTP clients are unsupported for OAuth-managed providers.
 *
 * ## Configuration
 *
 * Create `~/.pi/agent/client-credentials.json` for global config, or
 * `.pi/client-credentials.json` in the Pi process cwd as a project-local
 * fallback when no global config is present:
 *
 * ```json
 * {
 *   "providers": [
 *     {
 *       "name": "corp-openai",
 *       "baseUrls": ["https://gateway.example.com"],
 *       "tokenUrl": "https://auth.example.com/oauth2/token",
 *       "clientId": "${APIGEE_CLIENT_ID}",
 *       "clientSecret": "${APIGEE_CLIENT_SECRET}",
 *       "clientAuthMethod": "client_secret_basic",
 *       "scope": "llm.invoke",
 *       "audience": "https://gateway.example.com"
 *     }
 *   ]
 * }
 * ```
 *
 * - `${ENV_VAR}` placeholders are expanded when acquiring a token. They are
 *   supported in `clientId`, `clientSecret`, `scope`, `audience`, `resource`,
 *   and `extraParams` values.
 * - `clientAuthMethod` defaults to `client_secret_post` (params in body).
 *   Set to `client_secret_basic` for HTTP Basic auth.
 * - `baseUrls` is an array of URL prefixes to intercept.  Every outgoing request
 *   whose full URL starts with one of these prefixes gets the OAuth token.
 * - `authHeaderName` optionally changes the injected Bearer-token header name;
 *   otherwise the extension uses `Authorization`.
 *
 * ## Usage
 *
 * 1. Place this file in `~/.pi/agent/extensions/oauth.ts`
 * 2. Create `~/.pi/agent/client-credentials.json` or `.pi/client-credentials.json`
 *    with your provider configs
 * 3. Configure the corresponding provider in `~/.pi/agent/models.json`; set
 *    `apiKey` to any dummy value (the extension replaces the header):
 *
 *    ```json
 *    {
 *      "providers": {
 *        "corp-openai": {
 *          "baseUrl": "https://gateway.example.com/openai/v1",
 *          "api": "openai-completions",
 *          "apiKey": "oauth-managed",
 *          "models": [{ "id": "gpt-4o", ... }]
 *        }
 *      }
 *    }
 *    ```
 *
 * 4. Run `pi`, select your model, and start prompting.
 *
 * ## Commands
 *
 * - `/cc-status`  — Show token cache state for every configured provider.
 * - `/cc-refresh` — Force immediate token re-acquisition (clears cache first).
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface OAuthProviderConfig {
  /** Human-readable label shown in status / commands. */
  name: string;
  /** URL prefixes to intercept.  Any outgoing request whose href starts with
   *  one of these prefixes receives the OAuth Bearer token. */
  baseUrls: string[];
  /** Token endpoint (full URL). */
  tokenUrl: string;
  /** Client identifier.  `${ENV_VAR}` placeholders are expanded. */
  clientId: string;
  /** Client secret.  `${ENV_VAR}` placeholders are expanded. */
  clientSecret: string;
  /** Authentication method sent to the token endpoint.
   *  - `client_secret_post` (default): `client_id` + `client_secret` in POST body.
   *  - `client_secret_basic`: HTTP Basic `Authorization` header, no ID/secret in body. */
  clientAuthMethod?: "client_secret_basic" | "client_secret_post";
  /** OAuth scope parameter (optional). */
  scope?: string;
  /** OAuth audience parameter (optional). */
  audience?: string;
  /** OAuth resource parameter (optional). */
  resource?: string;
  /** Arbitrary extra parameters appended to the token request body. */
  extraParams?: Record<string, string>;
  /** HTTP header name used for the Bearer token on proxied requests.
   *  Defaults to `Authorization`. */
  authHeaderName?: string;
}

interface ClientCredentialsConfig {
  providers: OAuthProviderConfig[];
}

interface TokenCacheEntry {
  accessToken: string;
  tokenType: string;
  expiresAt: number; // epoch ms
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/** Maps `tokenUrl + ":" + resolvedClientId` → cached token. */
const tokenCache = new Map<string, TokenCacheEntry>();

/** In-flight token acquisitions (deduplicates concurrent requests for the same
 *  provider).  Maps the same cache key → Promise<TokenCacheEntry>. */
const pendingTokens = new Map<string, Promise<TokenCacheEntry>>();

/** Cleanup function returned by the fetch interceptor.  Called on shutdown so
 *  hot-reloading does not stack patched fetch instances. */
let uninstallFetch: (() => void) | null = null;

/** Logging sink.  Pi extensions run in a Node process; we write to stderr so
 *  messages appear in the terminal but do not pollute stdout tool output. */
const log = (...args: unknown[]) => console.error("[oauth]", ...args);
const TOKEN_EXPIRY_BUFFER_MS = 30_000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Expand `${ENV_VAR}` placeholders in a string. */
function resolveEnv(value: string): string {
  return value.replace(/\$\{(\w+)\}/g, (_, name) => process.env[name] ?? "");
}

/** Resolve a required secret/config value and fail closed if an env var was missing. */
function resolveRequiredEnv(value: string, fieldName: string, providerName: string): string {
  const missing: string[] = [];
  const resolved = value.replace(/\$\{(\w+)\}/g, (_, name) => {
    const found = process.env[name];
    if (!found) missing.push(name);
    return found ?? "";
  });
  if (missing.length > 0) {
    throw new Error(`${providerName}.${fieldName} references missing env var(s): ${missing.join(", ")}`);
  }
  if (!resolved) throw new Error(`${providerName}.${fieldName} resolved to an empty value`);
  return resolved;
}

/** OAuth 2.0 client_secret_basic uses application/x-www-form-urlencoded encoding
 *  for the client id/secret before joining with `:` and Base64-encoding. */
function formEncodeComponent(value: string): string {
  return encodeURIComponent(value).replace(/%20/g, "+");
}

function basicCredentials(clientId: string, clientSecret: string): string {
  return btoa(`${formEncodeComponent(clientId)}:${formEncodeComponent(clientSecret)}`);
}

/** Merge headers from both a Request object and RequestInit.  OpenAI usually
 *  calls fetch(url, init), but this keeps the interceptor correct for generic
 *  fetch(Request, init) usage too. */
function mergedRequestHeaders(input: RequestInfo | URL, init?: RequestInit): Headers {
  const headers = new Headers();
  if (typeof input !== "string" && !(input instanceof URL)) {
    input.headers.forEach((value, key) => headers.set(key, value));
  }
  if (init?.headers) {
    new Headers(init.headers).forEach((value, key) => headers.set(key, value));
  }
  return headers;
}

async function responseIndicatesInvalidToken(response: Response): Promise<boolean> {
  if (response.status === 401) return true;

  const wwwAuthenticate = response.headers.get("www-authenticate")?.toLowerCase() ?? "";
  if (wwwAuthenticate.includes("invalid_token")) return true;

  if (response.status !== 400 && response.status !== 403) return false;
  const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.includes("json") && !contentType.includes("text")) return false;

  const body = await response.clone().text().catch(() => "");
  return body.toLowerCase().includes("invalid_token");
}

/** Deterministic cache key for a provider. */
function cacheKey(cfg: OAuthProviderConfig): string {
  return `${cfg.tokenUrl}:${resolveEnv(cfg.clientId)}`;
}

/** Safely read and parse the config file.  Returns null on any error. */
function loadConfig(): ClientCredentialsConfig | null {
  const paths = [
    resolve(
      process.env.HOME ?? process.env.USERPROFILE ?? "/tmp",
      ".pi/agent/client-credentials.json",
    ),
    // Also check project-local for monorepo-style setups.
    resolve(process.cwd(), ".pi/client-credentials.json"),
  ];

  for (const path of paths) {
    if (!existsSync(path)) continue;
    try {
      const raw = readFileSync(path, "utf-8");
      const cfg = JSON.parse(raw) as ClientCredentialsConfig;
      if (!cfg.providers?.length) {
        log(`Config at ${path} has no providers array — skipping.`);
        continue;
      }
      const providers = cfg.providers.filter((p, i) => {
        if (!p.baseUrls?.length) {
          log(`Provider #${i} ("${p.name}") has no baseUrls — skipping.`);
          return false;
        }
        if (!p.tokenUrl || !p.clientId || !p.clientSecret) {
          log(`Provider #${i} ("${p.name}") missing required fields — skipping.`);
          return false;
        }
        return true;
      });
      if (providers.length === 0) {
        log(`Config at ${path} has no valid providers — skipping.`);
        continue;
      }
      return { providers };
    } catch (err) {
      log(`Failed to parse ${path}:`, (err as Error).message);
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Token acquisition
// ---------------------------------------------------------------------------

/** Request an OAuth 2.0 client_credentials token.  Handles both
 *  `client_secret_basic` and `client_secret_post` methods. */
async function acquireToken(cfg: OAuthProviderConfig): Promise<TokenCacheEntry> {
  const key = cacheKey(cfg);

  // Return cached token if it still has life left, with a small refresh buffer.
  const cached = tokenCache.get(key);
  if (cached && cached.expiresAt > Date.now() + TOKEN_EXPIRY_BUFFER_MS) {
    return cached;
  }

  // Deduplicate concurrent acquisitions.
  const inflight = pendingTokens.get(key);
  if (inflight) return inflight;

  const promise = (async (): Promise<TokenCacheEntry> => {
    const clientId = resolveRequiredEnv(cfg.clientId, "clientId", cfg.name);
    const clientSecret = resolveRequiredEnv(cfg.clientSecret, "clientSecret", cfg.name);

    const body = new URLSearchParams();
    body.append("grant_type", "client_credentials");

    const headers: Record<string, string> = {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    };

    if (cfg.clientAuthMethod === "client_secret_basic") {
      headers["Authorization"] = `Basic ${basicCredentials(clientId, clientSecret)}`;
    } else {
      // client_secret_post (default)
      body.append("client_id", clientId);
      body.append("client_secret", clientSecret);
    }

    if (cfg.scope) body.append("scope", resolveEnv(cfg.scope));
    if (cfg.audience) body.append("audience", resolveEnv(cfg.audience));
    if (cfg.resource) body.append("resource", resolveEnv(cfg.resource));
    if (cfg.extraParams) {
      for (const [k, v] of Object.entries(cfg.extraParams)) {
        body.append(k, resolveEnv(v));
      }
    }

    // Use the ORIGINAL fetch (not our patched one) so we don't
    // infinitely recurse or inject the LLM token into the OAuth call.
    const rawFetch = (globalThis as any).__cc_oauth_originalFetch ?? globalThis.fetch;

    const res = await rawFetch(cfg.tokenUrl, {
      method: "POST",
      headers,
      body: body.toString(),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "<unreadable>");
      throw new Error(
        `Token endpoint returned ${res.status} ${res.statusText}: ${text.slice(0, 500)}`,
      );
    }

    const data = (await res.json()) as {
      access_token?: string;
      token_type?: string;
      expires_in?: number;
    };

    if (!data.access_token) {
      throw new Error(
        `Token response missing access_token: ${JSON.stringify(data).slice(0, 500)}`,
      );
    }

    const entry: TokenCacheEntry = {
      accessToken: data.access_token,
      tokenType: data.token_type ?? "Bearer",
      expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
    };

    tokenCache.set(key, entry);
    log(`Acquired token for "${cfg.name}" (expires in ${data.expires_in ?? 3600}s)`);
    return entry;
  })();

  pendingTokens.set(key, promise);
  try {
    return await promise;
  } finally {
    pendingTokens.delete(key);
  }
}

// ---------------------------------------------------------------------------
// Fetch interceptor
// ---------------------------------------------------------------------------

/** Install the global fetch interceptor.  Returns a cleanup function that
 *  restores the original `globalThis.fetch`. */
function installFetchInterceptor(providers: OAuthProviderConfig[]): () => void {
  // Guard against double-install (e.g. if called from both factory and reload).
  if ((globalThis as any).__cc_oauth_originalFetch) {
    // Already installed — just update the provider list.
    (globalThis as any).__cc_oauth_providers = providers;
    return () => {
      // no-op; another install call will handle teardown
    };
  }

  const originalFetch = globalThis.fetch.bind(globalThis);
  (globalThis as any).__cc_oauth_originalFetch = originalFetch;

  // We store providers on globalThis so the interceptor closure can access
  // the latest config across /reload cycles without re-wrapping fetch.
  (globalThis as any).__cc_oauth_providers = providers;

  globalThis.fetch = async function (
    this: typeof globalThis,
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> {
    const providersSnapshot: OAuthProviderConfig[] =
      (globalThis as any).__cc_oauth_providers ?? [];

    // Resolve the request URL to a string.
    let urlStr: string;
    if (typeof input === "string") {
      urlStr = input;
    } else if (input instanceof URL) {
      urlStr = input.href;
    } else {
      // Request instance
      urlStr = input.url;
    }

    // Find the first provider whose baseUrl matches.
    const matched = providersSnapshot.find((p) =>
      p.baseUrls.some((prefix) => urlStr.startsWith(prefix)),
    );

    // Not an LLM provider call — pass through unchanged.
    if (!matched) {
      return originalFetch(input, init);
    }

    const authHeader = matched.authHeaderName ?? "Authorization";

    // Acquire a valid token.
    let token: TokenCacheEntry;
    try {
      token = await acquireToken(matched);
    } catch (err) {
      const message = `Failed to acquire token for "${matched.name}": ${(err as Error).message}`;
      log(message);
      // Fail closed: do not send the prompt to the gateway with dummy or missing auth.
      throw new Error(`[oauth] ${message}`);
    }

    // Build a headers object from the original request, injecting our token.
    const mergedHeaders = mergedRequestHeaders(input, init);
    mergedHeaders.set(authHeader, `${token.tokenType} ${token.accessToken}`);

    const augmentedInit: RequestInit = {
      ...init,
      headers: mergedHeaders,
    };

    // First attempt.
    const response = await originalFetch(input, augmentedInit);

    // If the gateway says the token is invalid, clear cache and retry once.
    if (await responseIndicatesInvalidToken(response)) {
      log(`Token rejected for "${matched.name}" — clearing cache and retrying.`);
      tokenCache.delete(cacheKey(matched));

      try {
        const freshToken = await acquireToken(matched);
        const retryHeaders = mergedRequestHeaders(input, init);
        retryHeaders.set(authHeader, `${freshToken.tokenType} ${freshToken.accessToken}`);
        const retryResponse = await originalFetch(input, {
          ...init,
          headers: retryHeaders,
        });

        // Always return the retry response; it is the most current answer from
        // the gateway.  If it is still an auth failure, the caller should see
        // that latest error body.
        const retryStillRejected = await responseIndicatesInvalidToken(retryResponse);
        void response.body?.cancel();
        if (retryStillRejected) log(`Retry also rejected token for "${matched.name}".`);
        return retryResponse;
      } catch (err) {
        log(`Retry failed for "${matched.name}":`, (err as Error).message);
      }
    }

    return response;
  } as typeof globalThis.fetch;

  // Return cleanup callback.
  return () => {
    if ((globalThis as any).__cc_oauth_originalFetch) {
      globalThis.fetch = (globalThis as any).__cc_oauth_originalFetch;
      delete (globalThis as any).__cc_oauth_originalFetch;
      delete (globalThis as any).__cc_oauth_providers;
    }
  };
}

// ---------------------------------------------------------------------------
// Extension entry point
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  // ── Install interceptor immediately (on extension load) ─────────────
  const cfg = loadConfig();
  if (cfg?.providers?.length) {
    uninstallFetch = installFetchInterceptor(cfg.providers);
  }

  // ── Re-read config on reload ────────────────────────────────────────
  pi.on("session_start", async (event) => {
    if (event.reason !== "reload") return;

    const fresh = loadConfig();
    if (!fresh?.providers?.length) {
      // No valid config — tear down the interceptor if it's running.
      uninstallFetch?.();
      uninstallFetch = null;
      return;
    }

    // Update the provider list in-place without re-wrapping fetch.
    (globalThis as any).__cc_oauth_providers = fresh.providers;
    // If the interceptor was never installed (e.g. first reload), install it.
    if (!(globalThis as any).__cc_oauth_originalFetch) {
      uninstallFetch = installFetchInterceptor(fresh.providers);
    }
    log(`Reloaded OAuth config: ${fresh.providers.length} provider(s).`);
  });

  // ── Cleanup on shutdown / reload ────────────────────────────────────
  pi.on("session_shutdown", () => {
    uninstallFetch?.();
    uninstallFetch = null;
    // Clear caches so stale tokens are not reused across sessions.
    tokenCache.clear();
    pendingTokens.clear();
  });

  // ── Notify on startup ────────────────────────────────────────────────
  pi.on("session_start", async (event, ctx) => {
    if (event.reason !== "startup") return;
    if (!cfg?.providers?.length) return;
    const names = cfg.providers.map((p) => p.name).join(", ");
    ctx.ui.notify(
      `[oauth] ${cfg.providers.length} provider(s) configured: ${names}`,
      "info",
    );
  });

  // ── /cc-status — show token cache state ─────────────────────────────
  pi.registerCommand("cc-status", {
    description: "Show client-credentials OAuth token status",
    handler: async (_args, ctx) => {
      const currentCfg = loadConfig();
      if (!currentCfg?.providers?.length) {
        ctx.ui.notify(
          "No client-credentials config found at ~/.pi/agent/client-credentials.json or .pi/client-credentials.json",
          "warning",
        );
        return;
      }

      const lines: string[] = [
        `fetch path: ${(globalThis as any).__cc_oauth_originalFetch ? "installed" : "not installed"}`,
      ];
      for (const p of currentCfg.providers) {
        const key = cacheKey(p);
        const cached = tokenCache.get(key);
        if (cached) {
          const remaining = Math.round((cached.expiresAt - Date.now()) / 1000);
          lines.push(
            `${p.name}: ✓ valid (${cached.tokenType} ${cached.accessToken.slice(0, 8)}…, expires in ${remaining}s)`,
          );
        } else {
          lines.push(`${p.name}: ✗ no cached token`);
        }
      }

      ctx.ui.notify(lines.join("\n"), "info");
    },
  });

  // ── /cc-refresh — force token re-acquisition ────────────────────────
  pi.registerCommand("cc-refresh", {
    description: "Force-refresh all client-credentials OAuth tokens",
    handler: async (_args, ctx) => {
      const currentCfg = loadConfig();
      if (!currentCfg?.providers?.length) {
        ctx.ui.notify(
          "No client-credentials config found at ~/.pi/agent/client-credentials.json or .pi/client-credentials.json",
          "warning",
        );
        return;
      }

      const results: string[] = [];
      for (const p of currentCfg.providers) {
        tokenCache.delete(cacheKey(p));
        try {
          await acquireToken(p);
          results.push(`${p.name}: ✓ refreshed`);
        } catch (err) {
          results.push(`${p.name}: ✗ ${(err as Error).message}`);
        }
      }

      ctx.ui.notify(results.join("\n"), "info");
    },
  });
}
