import { Type } from "@mariozechner/pi-ai";
import { defineTool, type ExtensionAPI } from "@mariozechner/pi-coding-agent";

const EXA_MCP_URL = "https://mcp.exa.ai/mcp";
const DUCKDUCKGO_HTML_URL = "https://html.duckduckgo.com/html/";
const DEFAULT_TIMEOUT_MS = 25_000;
const DEFAULT_RESULTS = 8;
const MAX_RESULTS = 10;
const DEFAULT_CONTEXT_CHARS = 10_000;

type SearchProvider = "auto" | "exa" | "duckduckgo";

function textResult(text: string, details: Record<string, unknown> = {}) {
	return {
		content: [{ type: "text" as const, text }],
		details,
	};
}

function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
	return Math.max(min, Math.min(max, Math.trunc(value)));
}

function linkedSignal(parent: AbortSignal | undefined, timeoutMs: number) {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(new Error(`Timed out after ${timeoutMs}ms`)), timeoutMs);
	const abort = () => controller.abort(parent?.reason ?? new Error("Aborted"));

	if (parent) {
		if (parent.aborted) abort();
		else parent.addEventListener("abort", abort, { once: true });
	}

	return {
		signal: controller.signal,
		cleanup: () => {
			clearTimeout(timer);
			parent?.removeEventListener("abort", abort);
		},
	};
}

function decodeEntities(input: string): string {
	const named: Record<string, string> = {
		amp: "&",
		lt: "<",
		gt: ">",
		quot: "\"",
		apos: "'",
		nbsp: " ",
		ndash: "-",
		mdash: "-",
		hellip: "...",
	};

	return input.replace(/&(#x?[0-9a-f]+|[a-z][a-z0-9]+);/gi, (_match, entity: string) => {
		if (entity[0] === "#") {
			const radix = entity[1]?.toLowerCase() === "x" ? 16 : 10;
			const digits = radix === 16 ? entity.slice(2) : entity.slice(1);
			const codepoint = Number.parseInt(digits, radix);
			return Number.isFinite(codepoint) ? String.fromCodePoint(codepoint) : _match;
		}
		return named[entity.toLowerCase()] ?? _match;
	});
}

function stripTags(input: string): string {
	return decodeEntities(input.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim());
}

function unwrapDuckDuckGoUrl(raw: string): string {
	const decoded = decodeEntities(raw);
	try {
		const url = new URL(decoded, "https://duckduckgo.com");
		const wrapped = url.searchParams.get("uddg");
		return wrapped ? decodeURIComponent(wrapped) : url.toString();
	} catch {
		return decoded;
	}
}

function truncateText(text: string, maxChars: number): string {
	if (text.length <= maxChars) return text;
	return `${text.slice(0, maxChars)}\n\n[websearch truncated ${text.length - maxChars} characters]`;
}

function parseJsonOrSse(raw: string): unknown {
	const trimmed = raw.trim();
	if (trimmed.startsWith("{")) return JSON.parse(trimmed);

	for (const line of trimmed.split(/\r?\n/)) {
		if (!line.startsWith("data:")) continue;
		const payload = line.slice("data:".length).trim();
		if (!payload || payload === "[DONE]") continue;
		return JSON.parse(payload);
	}

	throw new Error("MCP server returned neither JSON nor SSE data");
}

function extractMcpText(result: any): string {
	const content = result?.content ?? result?.result?.content;
	if (Array.isArray(content)) {
		const text = content
			.map((item) => {
				if (typeof item?.text === "string") return item.text;
				if (typeof item === "string") return item;
				return "";
			})
			.filter(Boolean)
			.join("\n\n");
		if (text.trim()) return text.trim();
	}

	if (typeof result?.text === "string") return result.text;
	if (typeof result?.result === "string") return result.result;
	return JSON.stringify(result?.result ?? result, null, 2);
}

async function callExa(query: string, numResults: number, type: string, livecrawl: string, contextMaxCharacters: number, signal: AbortSignal | undefined): Promise<string> {
	const apiKey = process.env.EXA_API_KEY;
	const endpoint = new URL(EXA_MCP_URL);
	if (apiKey) endpoint.searchParams.set("exaApiKey", apiKey);

	const linked = linkedSignal(signal, DEFAULT_TIMEOUT_MS);
	try {
		const response = await fetch(endpoint, {
			method: "POST",
			signal: linked.signal,
			headers: {
				accept: "application/json, text/event-stream",
				"content-type": "application/json",
				...(apiKey ? { authorization: `Bearer ${apiKey}` } : {}),
			},
			body: JSON.stringify({
				jsonrpc: "2.0",
				id: 1,
				method: "tools/call",
				params: {
					name: "web_search_exa",
					arguments: {
						query,
						numResults,
						type,
						livecrawl,
						contextMaxCharacters,
					},
				},
			}),
		});

		const raw = await response.text();
		if (!response.ok) {
			throw new Error(`Exa MCP HTTP ${response.status}: ${raw.slice(0, 500)}`);
		}

		const payload: any = parseJsonOrSse(raw);
		if (payload.error) throw new Error(payload.error.message ?? JSON.stringify(payload.error));
		return extractMcpText(payload.result ?? payload);
	} finally {
		linked.cleanup();
	}
}

async function searchDuckDuckGo(query: string, numResults: number, signal: AbortSignal | undefined): Promise<string> {
	const linked = linkedSignal(signal, DEFAULT_TIMEOUT_MS);
	try {
		const body = new URLSearchParams({ q: query });
		const response = await fetch(DUCKDUCKGO_HTML_URL, {
			method: "POST",
			signal: linked.signal,
			headers: {
				accept: "text/html,application/xhtml+xml",
				"content-type": "application/x-www-form-urlencoded",
				"user-agent":
					"Mozilla/5.0 (compatible; pi-websearch/1.0; +https://github.com/mariozechner/pi)",
			},
			body,
		});

		const html = await response.text();
		if (!response.ok) throw new Error(`DuckDuckGo HTTP ${response.status}: ${html.slice(0, 300)}`);

		const results: Array<{ title: string; url: string; snippet: string }> = [];
		const itemRegex = /<div[^>]+class="[^"]*result[^"]*"[^>]*>([\s\S]*?)(?=<div[^>]+class="[^"]*result[^"]*"|<\/body>)/gi;
		let itemMatch: RegExpExecArray | null;

		while ((itemMatch = itemRegex.exec(html)) && results.length < numResults) {
			const block = itemMatch[1] ?? "";
			const link = block.match(/<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
			if (!link) continue;

			const snippet =
				block.match(/<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/a>/i)?.[1] ??
				block.match(/<div[^>]+class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/div>/i)?.[1] ??
				"";

			results.push({
				title: stripTags(link[2] ?? ""),
				url: unwrapDuckDuckGoUrl(link[1] ?? ""),
				snippet: stripTags(snippet),
			});
		}

		if (results.length === 0) return `No DuckDuckGo results found for "${query}".`;

		return results
			.map((result, index) => {
				const snippet = result.snippet ? `\n   ${result.snippet}` : "";
				return `${index + 1}. ${result.title}\n   ${result.url}${snippet}`;
			})
			.join("\n\n");
	} finally {
		linked.cleanup();
	}
}

const websearchTool = defineTool({
	name: "websearch",
	label: "Web Search",
	description:
		"Search the web for current information. Uses Exa MCP when available and falls back to DuckDuckGo HTML search.",
	promptSnippet: "websearch: search the live web for current information, returning titles, URLs, and snippets/context.",
	promptGuidelines: [
		"Use websearch when the answer may depend on recent, external, or URL-discoverable information.",
		"Use webfetch after websearch when a source page needs direct inspection.",
	],
	parameters: Type.Object({
		query: Type.String({ description: "Search query" }),
		numResults: Type.Optional(Type.Number({ description: "Number of results, default 8, max 10" })),
		provider: Type.Optional(
			Type.Union([
				Type.Literal("auto"),
				Type.Literal("exa"),
				Type.Literal("duckduckgo"),
			], { description: "Search provider. auto tries Exa then DuckDuckGo." }),
		),
		type: Type.Optional(
			Type.Union([
				Type.Literal("auto"),
				Type.Literal("fast"),
				Type.Literal("deep"),
			], { description: "Exa search mode" }),
		),
		livecrawl: Type.Optional(
			Type.Union([
				Type.Literal("fallback"),
				Type.Literal("preferred"),
				Type.Literal("always"),
				Type.Literal("never"),
			], { description: "Exa livecrawl mode" }),
		),
		contextMaxCharacters: Type.Optional(Type.Number({ description: "Maximum Exa context characters" })),
	}),

	async execute(_toolCallId, params, signal) {
		const numResults = clampNumber(params.numResults, DEFAULT_RESULTS, 1, MAX_RESULTS);
		const provider = (params.provider ?? "auto") as SearchProvider;
		const searchType = params.type ?? "auto";
		const livecrawl = params.livecrawl ?? "fallback";
		const contextMaxCharacters = clampNumber(params.contextMaxCharacters, DEFAULT_CONTEXT_CHARS, 1_000, 50_000);

		if (provider === "exa" || provider === "auto") {
			try {
				const text = await callExa(params.query, numResults, searchType, livecrawl, contextMaxCharacters, signal);
				return textResult(truncateText(text, contextMaxCharacters), {
					provider: "exa",
					query: params.query,
					numResults,
				});
			} catch (error: any) {
				if (provider === "exa") {
					return textResult(`Exa websearch failed: ${error?.message ?? String(error)}`, {
						provider: "exa",
						error: true,
					});
				}
			}
		}

		const text = await searchDuckDuckGo(params.query, numResults, signal);
		return textResult(text, {
			provider: "duckduckgo",
			query: params.query,
			numResults,
		});
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(websearchTool);
}
