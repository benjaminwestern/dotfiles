export type Usage = {
	input?: number;
	output?: number;
	cacheRead?: number;
	cacheWrite?: number;
	totalTokens?: number;
	cost?: { total?: number };
};

export type ContentBlock = {
	type?: string;
	name?: string;
};

export type MessageLike = {
	role?: string;
	provider?: string;
	model?: string;
	usage?: Usage;
	content?: string | ContentBlock[];
	toolName?: string;
	isError?: boolean;
	exitCode?: number;
	cancelled?: boolean;
	customType?: string;
	timestamp?: number | string;
};

export type EntryLike = {
	type?: string;
	timestamp?: string;
	message?: MessageLike;
};

export type ModelBucket = {
	source: string;
	model: string;
	requests: number;
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	totalTokens: number;
	cost: number;
};

export type UsageRecord = {
	source: string;
	provider: string;
	model: string;
	usage: Usage;
	timestamp?: number;
	cost?: number;
};

export function formatNumber(value: number | null | undefined) {
	return typeof value === "number" && Number.isFinite(value) ? value.toLocaleString() : "unknown";
}

export function formatCost(value: number) {
	return value >= 1 ? `$${value.toFixed(2)}` : `$${value.toFixed(4)}`;
}

export function compactNumber(value: number | null | undefined) {
	if (typeof value !== "number" || !Number.isFinite(value)) return "unknown";
	const abs = Math.abs(value);
	if (abs >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(2)}B`;
	if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(2)}M`;
	if (abs >= 10_000) return `${(value / 1_000).toFixed(1)}k`;
	return value.toLocaleString();
}

export function basename(path: string | undefined | null) {
	if (!path) return undefined;
	const parts = path.split(/[\\/]/).filter(Boolean);
	return parts.at(-1) ?? path;
}

export function toolName(tool: unknown) {
	if (typeof tool === "string") return tool;
	if (tool && typeof tool === "object" && "name" in tool && typeof (tool as { name?: unknown }).name === "string") {
		return (tool as { name: string }).name;
	}
	return String(tool);
}

export function numberValue(value: unknown) {
	return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

export function parseTimestamp(value: unknown) {
	if (typeof value === "number" && Number.isFinite(value)) return value;
	if (typeof value !== "string") return undefined;
	const parsed = Date.parse(value);
	return Number.isFinite(parsed) ? parsed : undefined;
}

export function entryTimestamp(entry: EntryLike) {
	return parseTimestamp(entry.timestamp) ?? parseTimestamp(entry.message?.timestamp);
}

export function increment(map: Map<string, number>, key: string, amount = 1) {
	map.set(key, (map.get(key) ?? 0) + amount);
}

export function contentBlocks(message: MessageLike | undefined) {
	return Array.isArray(message?.content) ? message.content : [];
}

export function toolCallBlocks(message: MessageLike | undefined) {
	return contentBlocks(message).filter((block) => block.type === "toolCall" && typeof block.name === "string");
}

export function messageRole(entry: EntryLike) {
	if (entry.type === "message" && entry.message?.role) return entry.message.role;
	return entry.type || "unknown";
}

export function roleLabel(entry: EntryLike) {
	const role = messageRole(entry);
	if (role === "custom" && entry.message?.customType) return `custom:${entry.message.customType}`;
	return role;
}

export function modelBucket(map: Map<string, ModelBucket>, source: string, model: string) {
	const key = `${source}/${model}`;
	let bucket = map.get(key);
	if (!bucket) {
		bucket = { source, model, requests: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: 0 };
		map.set(key, bucket);
	}
	return bucket;
}

export function usageTotal(usage: Usage) {
	const input = numberValue(usage.input);
	const output = numberValue(usage.output);
	const cacheRead = numberValue(usage.cacheRead);
	const cacheWrite = numberValue(usage.cacheWrite);
	return numberValue(usage.totalTokens) || input + output + cacheRead + cacheWrite;
}

export function addUsage(bucket: ModelBucket, usage: Usage, cost = numberValue(usage.cost?.total)) {
	const input = numberValue(usage.input);
	const output = numberValue(usage.output);
	const cacheRead = numberValue(usage.cacheRead);
	const cacheWrite = numberValue(usage.cacheWrite);
	bucket.requests += 1;
	bucket.input += input;
	bucket.output += output;
	bucket.cacheRead += cacheRead;
	bucket.cacheWrite += cacheWrite;
	bucket.totalTokens += usageTotal(usage);
	bucket.cost += cost;
}

export function piAssistantUsageRecord(entry: EntryLike) {
	if (entry.type !== "message") return undefined;
	if (entry.message?.role !== "assistant") return undefined;
	const usage = entry.message.usage;
	if (!usage) return undefined;
	const provider = entry.message.provider || "unknown";
	const model = entry.message.model || "unknown";
	return {
		source: "Pi",
		provider,
		model,
		usage,
		timestamp: entryTimestamp(entry),
		cost: numberValue(usage.cost?.total),
	} satisfies UsageRecord;
}
