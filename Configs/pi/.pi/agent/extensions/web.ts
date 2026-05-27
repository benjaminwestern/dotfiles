/*
===============================================================================
  EXTENSION: Web
  PURPOSE: Register websearch and webfetch tools for live web access.
===============================================================================
*/

// -----------------------------------------------------------------------------
// Imports
// -----------------------------------------------------------------------------

import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

// -----------------------------------------------------------------------------
// Shared constants and types
// -----------------------------------------------------------------------------

const DUCKDUCKGO_HTML_URL = "https://html.duckduckgo.com/html/";
const WEBSEARCH_TIMEOUT_MS = 25_000;
const DEFAULT_RESULTS = 8;
const MAX_RESULTS = 10;

const WEBFETCH_TIMEOUT_MS = 30_000;
const WEBFETCH_MAX_TIMEOUT_MS = 120_000;
const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;
const DEFAULT_MAX_CHARS = 30_000;

// -----------------------------------------------------------------------------
// Shared helpers
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Web search helpers
// -----------------------------------------------------------------------------

function stripSearchTags(input: string): string {
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

async function searchDuckDuckGo(query: string, numResults: number, signal: AbortSignal | undefined): Promise<string> {
	const linked = linkedSignal(signal, WEBSEARCH_TIMEOUT_MS);
	try {
		const body = new URLSearchParams({ q: query });
		const response = await fetch(DUCKDUCKGO_HTML_URL, {
			method: "POST",
			signal: linked.signal,
			headers: {
				accept: "text/html,application/xhtml+xml",
				"content-type": "application/x-www-form-urlencoded",
				"user-agent":
					"Mozilla/5.0 (compatible; pi-web/1.0; +https://github.com/earendil-works/pi/tree/main)",
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
				title: stripSearchTags(link[2] ?? ""),
				url: unwrapDuckDuckGoUrl(link[1] ?? ""),
				snippet: stripSearchTags(snippet),
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

// -----------------------------------------------------------------------------
// websearch tool
// -----------------------------------------------------------------------------

const websearchTool = defineTool({
	name: "websearch",
	label: "Web Search",
	description:
		"Search the web for current information using DuckDuckGo HTML search.",
	promptSnippet: "websearch: search the live web for current information, returning titles, URLs, and snippets/context.",
	promptGuidelines: [
		"Use websearch when the answer may depend on recent, external, or URL-discoverable information.",
		"Use webfetch after websearch when a source page needs direct inspection.",
	],
	parameters: Type.Object({
		query: Type.String({ description: "Search query" }),
		numResults: Type.Optional(Type.Number({ description: "Number of results, default 8, max 10" })),
	}),

	async execute(_toolCallId, params, signal) {
		const numResults = clampNumber(params.numResults, DEFAULT_RESULTS, 1, MAX_RESULTS);
		const text = await searchDuckDuckGo(params.query, numResults, signal);
		return textResult(text, {
			provider: "duckduckgo",
			query: params.query,
			numResults,
		});
	},
});

// -----------------------------------------------------------------------------
// Web fetch helpers
// -----------------------------------------------------------------------------

function ensureHttpUrl(raw: string): URL {
	const url = new URL(raw);
	if (url.protocol !== "http:" && url.protocol !== "https:") {
		throw new Error(`webfetch only supports http and https URLs, got ${url.protocol}`);
	}
	return url;
}

async function readLimited(response: Response, maxBytes: number): Promise<Buffer> {
	if (!response.body) return Buffer.from(await response.arrayBuffer());

	const reader = response.body.getReader();
	const chunks: Buffer[] = [];
	let total = 0;

	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		const chunk = Buffer.from(value);
		total += chunk.byteLength;
		if (total > maxBytes) {
			await reader.cancel();
			throw new Error(`Response exceeded ${maxBytes} byte limit`);
		}
		chunks.push(chunk);
	}

	return Buffer.concat(chunks);
}

function stripHtmlTags(html: string): string {
	return decodeEntities(html.replace(/<[^>]+>/g, " "));
}

function normaliseWhitespace(text: string): string {
	return text
		.replace(/\r\n/g, "\n")
		.replace(/[ \t]+\n/g, "\n")
		.replace(/\n{3,}/g, "\n\n")
		.replace(/[ \t]{2,}/g, " ")
		.trim();
}

function htmlToMarkdown(html: string): string {
	let body = html
		.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
		.replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "")
		.replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, "")
		.replace(/<!--[\s\S]*?-->/g, "");

	body = body.replace(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, (_match, href: string, label: string) => {
		const text = stripHtmlTags(label).trim();
		return text ? `[${text}](${decodeEntities(href)})` : decodeEntities(href);
	});

	body = body.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_match, level: string, content: string) => {
		return `\n\n${"#".repeat(Number(level))} ${stripHtmlTags(content).trim()}\n`;
	});

	body = body
		.replace(/<li\b[^>]*>/gi, "\n- ")
		.replace(/<\/(p|div|section|article|header|footer|main|aside|nav|ul|ol|li|blockquote|pre|table|tr)>/gi, "\n")
		.replace(/<br\s*\/?>/gi, "\n")
		.replace(/<[^>]+>/g, " ");

	return normaliseWhitespace(decodeEntities(body));
}

function htmlToText(html: string): string {
	return normaliseWhitespace(
		decodeEntities(
			html
				.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
				.replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "")
				.replace(/<!--[\s\S]*?-->/g, "")
				.replace(/<\/(p|div|section|article|header|footer|main|aside|nav|li|h[1-6]|tr)>/gi, "\n")
				.replace(/<br\s*\/?>/gi, "\n")
				.replace(/<[^>]+>/g, " "),
		),
	);
}

function truncateMiddle(text: string, maxChars: number): string {
	if (text.length <= maxChars) return text;
	const head = Math.floor(maxChars * 0.65);
	const tail = Math.max(0, maxChars - head - 120);
	return `${text.slice(0, head)}\n\n[webfetch truncated ${text.length - head - tail} characters from the middle]\n\n${text.slice(text.length - tail)}`;
}

// -----------------------------------------------------------------------------
// webfetch tool
// -----------------------------------------------------------------------------

const webfetchTool = defineTool({
	name: "webfetch",
	label: "Web Fetch",
	description:
		"Fetch an HTTP(S) URL and return readable text. Use this after websearch when a page needs to be inspected directly.",
	promptSnippet: "webfetch: fetch a URL and return text, markdown, or raw HTML for inspection.",
	promptGuidelines: [
		"Use webfetch when the user gives a URL or a search result needs direct inspection.",
		"Prefer format=markdown for HTML pages unless raw HTML is required.",
	],
	parameters: Type.Object({
		url: Type.String({ description: "HTTP or HTTPS URL to fetch" }),
		format: Type.Optional(
			Type.Union([
				Type.Literal("markdown"),
				Type.Literal("text"),
				Type.Literal("html"),
			], { description: "Output format. Defaults to markdown for HTML, text for non-HTML text." }),
		),
		timeoutSeconds: Type.Optional(Type.Number({ description: "Request timeout in seconds, max 120" })),
		maxCharacters: Type.Optional(Type.Number({ description: "Maximum characters returned to the model" })),
	}),

	async execute(_toolCallId, params, signal) {
		const url = ensureHttpUrl(params.url);
		const timeoutMs = clampNumber(params.timeoutSeconds, WEBFETCH_TIMEOUT_MS / 1000, 1, WEBFETCH_MAX_TIMEOUT_MS / 1000) * 1000;
		const maxCharacters = clampNumber(params.maxCharacters, DEFAULT_MAX_CHARS, 1_000, 200_000);
		const linked = linkedSignal(signal, timeoutMs);

		try {
			const response = await fetch(url, {
				signal: linked.signal,
				redirect: "follow",
				headers: {
					accept: "text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.8",
					"user-agent":
						"Mozilla/5.0 (compatible; pi-web/1.0; +https://github.com/earendil-works/pi/tree/main)",
				},
			});

			const contentType = response.headers.get("content-type") ?? "";
			const body = await readLimited(response, MAX_RESPONSE_BYTES);
			const raw = body.toString("utf8");
			const requestedFormat = params.format;
			const isHtml = /text\/html|application\/xhtml\+xml/i.test(contentType) || /<html[\s>]/i.test(raw);
			const isTextual = /^text\//i.test(contentType) || /json|xml|yaml|csv|markdown|javascript|typescript/i.test(contentType);

			if (!response.ok) {
				return textResult(
					truncateMiddle(
						`webfetch failed with HTTP ${response.status} ${response.statusText}\n\n${isHtml ? htmlToText(raw) : raw}`,
						maxCharacters,
					),
					{ ok: false, status: response.status, url: url.toString(), contentType },
				);
			}

			if (requestedFormat === "html") {
				return textResult(truncateMiddle(raw, maxCharacters), {
					ok: true,
					status: response.status,
					url: response.url,
					contentType,
					format: "html",
					bytes: body.byteLength,
				});
			}

			if (isHtml) {
				const text = requestedFormat === "text" ? htmlToText(raw) : htmlToMarkdown(raw);
				return textResult(truncateMiddle(text, maxCharacters), {
					ok: true,
					status: response.status,
					url: response.url,
					contentType,
					format: requestedFormat ?? "markdown",
					bytes: body.byteLength,
				});
			}

			if (isTextual || !contentType) {
				return textResult(truncateMiddle(raw, maxCharacters), {
					ok: true,
					status: response.status,
					url: response.url,
					contentType,
					format: "text",
					bytes: body.byteLength,
				});
			}

			return textResult(
				`Fetched ${response.url}, but it is non-text content (${contentType || "unknown content type"}, ${body.byteLength} bytes). Use a browser or a specialised media tool for this resource.`,
				{ ok: true, status: response.status, url: response.url, contentType, bytes: body.byteLength, nonText: true },
			);
		} finally {
			linked.cleanup();
		}
	},
});

// -----------------------------------------------------------------------------
// Extension registration
// -----------------------------------------------------------------------------

export default function web(pi: ExtensionAPI) {
	pi.registerTool(websearchTool);
	pi.registerTool(webfetchTool);
}
