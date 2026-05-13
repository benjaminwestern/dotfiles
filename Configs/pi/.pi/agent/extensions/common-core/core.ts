export function textResult(text: string, details: Record<string, unknown> = {}) {
	return {
		content: [{ type: "text" as const, text }],
		details,
	};
}

export function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
	return Math.max(min, Math.min(max, Math.trunc(value)));
}

export function linkedSignal(parent: AbortSignal | undefined, timeoutMs: number) {
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

export function decodeEntities(input: string): string {
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

export function parseJsonOrSse(raw: string, errorMessage = "Response was not JSON or SSE"): any {
	const trimmed = raw.trim();
	if (trimmed.startsWith("{")) return JSON.parse(trimmed);

	for (const line of trimmed.split(/\r?\n/)) {
		if (!line.startsWith("data:")) continue;
		const payload = line.slice("data:".length).trim();
		if (!payload || payload === "[DONE]") continue;
		return JSON.parse(payload);
	}

	throw new Error(errorMessage);
}

export function extractMcpText(result: any): string {
	const content = result?.content ?? result?.result?.content ?? result?.contents ?? result?.result?.contents;
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
	if (typeof result === "string") return result;
	return JSON.stringify(result?.result ?? result, null, 2);
}
