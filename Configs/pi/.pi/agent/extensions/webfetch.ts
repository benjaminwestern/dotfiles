import { Type } from "@mariozechner/pi-ai";
import { defineTool, type ExtensionAPI } from "@mariozechner/pi-coding-agent";

const DEFAULT_TIMEOUT_MS = 30_000;
const MAX_TIMEOUT_MS = 120_000;
const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;
const DEFAULT_MAX_CHARS = 30_000;

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

function ensureHttpUrl(raw: string): URL {
	const url = new URL(raw);
	if (url.protocol !== "http:" && url.protocol !== "https:") {
		throw new Error(`webfetch only supports http and https URLs, got ${url.protocol}`);
	}
	return url;
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

function stripTags(html: string): string {
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
		const text = stripTags(label).trim();
		return text ? `[${text}](${decodeEntities(href)})` : decodeEntities(href);
	});

	body = body.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_match, level: string, content: string) => {
		return `\n\n${"#".repeat(Number(level))} ${stripTags(content).trim()}\n`;
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
		const timeoutMs = clampNumber(params.timeoutSeconds, DEFAULT_TIMEOUT_MS / 1000, 1, MAX_TIMEOUT_MS / 1000) * 1000;
		const maxCharacters = clampNumber(params.maxCharacters, DEFAULT_MAX_CHARS, 1_000, 200_000);
		const linked = linkedSignal(signal, timeoutMs);

		try {
			const response = await fetch(url, {
				signal: linked.signal,
				redirect: "follow",
				headers: {
					accept: "text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.8",
					"user-agent":
						"Mozilla/5.0 (compatible; pi-webfetch/1.0; +https://github.com/mariozechner/pi)",
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

export default function (pi: ExtensionAPI) {
	pi.registerTool(webfetchTool);
}
