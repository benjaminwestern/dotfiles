import { existsSync, readdirSync, readFileSync, statSync, type Dirent } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import {
	addUsage,
	compactNumber,
	formatCost,
	formatNumber,
	modelBucket,
	numberValue,
	parseTimestamp,
	piAssistantUsageRecord,
	type EntryLike,
	type ModelBucket,
	type Usage,
	type UsageRecord,
} from "./usage-core/core.js";
import {
	fitText,
	padRight,
	panelBlank,
	panelLine,
	panelRule,
	panelTopRule,
	showHud,
	withPanelShadow,
	type ThemeLike,
} from "./ui-core/core.js";

const WINDOWS = [
	{ label: "Last 1 day", days: 1 },
	{ label: "Last 7 days", days: 7 },
	{ label: "Last 30 days", days: 30 },
	{ label: "Last 90 days", days: 90 },
];

const MODELS_DEV_URL = "https://models.dev/api.json";
const PRICE_TIMEOUT_MS = 15_000;
const MILLION = 1_000_000;

type JsonObject = Record<string, unknown>;

type ParseResult = {
	records: UsageRecord[];
	skipped: number;
	files: number;
};

type Price = {
	provider: string;
	model: string;
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	matched: string;
};

type PriceLookup = {
	ok: boolean;
	date: string;
	message?: string;
	models: Map<string, Price>;
	unmatched: Set<string>;
};

type UsageWindow = {
	label: string;
	days: number;
	buckets: Map<string, ModelBucket>;
};

type UsageSnapshot = {
	generatedAt: number;
	windows: UsageWindow[];
	lookup: PriceLookup;
	pi: ParseResult;
	codex: ParseResult;
};

function objectValue(value: unknown) {
	return value && typeof value === "object" && !Array.isArray(value) ? (value as JsonObject) : undefined;
}

function stringValue(value: unknown) {
	return typeof value === "string" && value.trim() ? value : undefined;
}

function fileModifiedAt(path: string) {
	try {
		return statSync(path).mtimeMs;
	} catch {
		return Date.now();
	}
}

function jsonlFiles(root: string) {
	const files: string[] = [];
	if (!existsSync(root)) return files;
	const stack = [root];
	while (stack.length > 0) {
		const dir = stack.pop();
		if (!dir) continue;
		let entries: Dirent[];
		try {
			entries = readdirSync(dir, { withFileTypes: true });
		} catch {
			continue;
		}
		for (const entry of entries) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) {
				stack.push(path);
			} else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
				files.push(path);
			}
		}
	}
	return files;
}

function parseJsonLine(line: string) {
	try {
		return { value: JSON.parse(line) as unknown };
	} catch {
		return { skipped: true };
	}
}

function readLines(path: string) {
	try {
		return readFileSync(path, "utf8").split(/\r?\n/).filter((line) => line.trim());
	} catch {
		return undefined;
	}
}

function parsePiSessions(root = join(homedir(), ".pi", "agent", "sessions")): ParseResult {
	const records: UsageRecord[] = [];
	let skipped = 0;
	const files = jsonlFiles(root);
	for (const file of files) {
		const fallbackTimestamp = fileModifiedAt(file);
		const lines = readLines(file);
		if (!lines) {
			skipped += 1;
			continue;
		}
		for (const line of lines) {
			const parsed = parseJsonLine(line);
			if (parsed.skipped) {
				skipped += 1;
				continue;
			}
			const entry = objectValue(parsed.value) as EntryLike | undefined;
			if (!entry) continue;
			const record = piAssistantUsageRecord(entry);
			if (record) records.push({ ...record, timestamp: record.timestamp ?? fallbackTimestamp });
		}
	}
	return { records, skipped, files: files.length };
}

function codexUsageFromTokenCount(value: JsonObject) {
	const payload = objectValue(value.payload);
	if (payload?.type !== "token_count") return undefined;
	const info = objectValue(payload.info);
	const last = objectValue(info?.last_token_usage);
	if (!last) return undefined;
	return {
		input: numberValue(last.input_tokens),
		output: numberValue(last.output_tokens),
		cacheRead: numberValue(last.cached_input_tokens),
		cacheWrite: 0,
		totalTokens: numberValue(last.total_tokens),
	} satisfies Usage;
}

function parseCodexSessions(roots = [join(homedir(), ".codex", "sessions"), join(homedir(), ".codex", "archived_sessions")]): ParseResult {
	const records: UsageRecord[] = [];
	let skipped = 0;
	const files = roots.flatMap((root) => jsonlFiles(root));
	for (const file of files) {
		const fallbackTimestamp = fileModifiedAt(file);
		const lines = readLines(file);
		if (!lines) {
			skipped += 1;
			continue;
		}

		let provider = "openai";
		let model = "unknown";

		for (const line of lines) {
			const parsed = parseJsonLine(line);
			if (parsed.skipped) {
				skipped += 1;
				continue;
			}
			const entry = objectValue(parsed.value);
			if (!entry) continue;
			const payload = objectValue(entry.payload);

			if (entry.type === "session_meta" && payload) {
				provider = stringValue(payload.model_provider) ?? provider;
				model = stringValue(payload.model) ?? model;
			}
			if (entry.type === "turn_context" && payload) {
				provider = stringValue(payload.model_provider) ?? provider;
				model = stringValue(payload.model) ?? model;
			}

			const usage = codexUsageFromTokenCount(entry);
			if (!usage) continue;
			records.push({
				source: "Codex CLI",
				provider,
				model,
				usage,
				timestamp: parseTimestamp(entry.timestamp) ?? fallbackTimestamp,
			});
		}
	}
	return { records, skipped, files: files.length };
}

function normalize(value: string) {
	return value.toLowerCase().replace(/[^a-z0-9._/-]+/g, "");
}

function priceKey(provider: string, model: string) {
	return `${provider}/${model}`;
}

function providerCandidates(provider: string, model: string) {
	const normalized = normalize(provider);
	const candidates = [normalized];
	const slashProvider = model.includes("/") ? normalize(model.split("/")[0]) : undefined;
	if (slashProvider) candidates.push(slashProvider);
	if (normalized === "openai-codex" || normalized === "codex-cli") candidates.push("openai");
	if (normalized === "google-generative-ai" || normalized === "google-vertex") candidates.push("google");
	if (normalized === "anthropic-bedrock" || normalized === "amazon-bedrock") candidates.push("anthropic", "amazon");
	if (model.toLowerCase().includes("gpt") || model.toLowerCase().includes("codex")) candidates.push("openai");
	if (model.toLowerCase().includes("claude")) candidates.push("anthropic");
	if (model.toLowerCase().includes("gemini")) candidates.push("google");
	return [...new Set(candidates.filter(Boolean))];
}

function modelCandidates(model: string) {
	const values = [model];
	if (model.includes("/")) values.push(model.split("/").slice(1).join("/"));
	if (model.startsWith("models/")) values.push(model.slice("models/".length));
	return [...new Set(values.map(normalize))];
}

function modelMapForProvider(api: JsonObject, provider: string) {
	const providerObject = objectValue(api[provider]);
	return objectValue(providerObject?.models);
}

function extractPrice(provider: string, modelId: string, modelObject: JsonObject, matched: string): Price | undefined {
	const cost = objectValue(modelObject.cost);
	if (!cost) return undefined;
	return {
		provider,
		model: modelId,
		input: numberValue(cost.input),
		output: numberValue(cost.output),
		cacheRead: numberValue(cost.cache_read) || numberValue(cost.cacheRead),
		cacheWrite: numberValue(cost.cache_write) || numberValue(cost.cacheWrite),
		matched,
	};
}

function findPrice(api: JsonObject, provider: string, model: string) {
	for (const providerCandidate of providerCandidates(provider, model)) {
		const models = modelMapForProvider(api, providerCandidate);
		if (!models) continue;
		const wanted = modelCandidates(model);
		for (const wantedModel of wanted) {
			for (const [modelId, modelObject] of Object.entries(models)) {
				if (normalize(modelId) !== wantedModel) continue;
				const price = extractPrice(providerCandidate, modelId, objectValue(modelObject) ?? {}, `${providerCandidate}/${modelId}`);
				if (price) return price;
			}
		}
		for (const wantedModel of wanted) {
			for (const [modelId, modelObject] of Object.entries(models)) {
				const normalizedId = normalize(modelId);
				if (!normalizedId.endsWith(wantedModel) && !wantedModel.endsWith(normalizedId)) continue;
				const price = extractPrice(providerCandidate, modelId, objectValue(modelObject) ?? {}, `${providerCandidate}/${modelId}`);
				if (price) return price;
			}
		}
	}
	return undefined;
}

async function fetchModelsDevPrices(buckets: ModelBucket[]) {
	const lookup: PriceLookup = {
		ok: false,
		date: new Date().toISOString().slice(0, 10),
		models: new Map(),
		unmatched: new Set(),
	};
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), PRICE_TIMEOUT_MS);
	try {
		const response = await fetch(MODELS_DEV_URL, {
			headers: { "User-Agent": "Mozilla/5.0 Pi usage extension" },
			signal: controller.signal,
		});
		if (!response.ok) throw new Error(`HTTP ${response.status}`);
		const api = objectValue(await response.json());
		if (!api) throw new Error("invalid models.dev response");
		lookup.ok = true;
		for (const bucket of buckets) {
			const slash = bucket.model.indexOf("/");
			const provider = slash > 0 ? bucket.model.slice(0, slash) : bucket.source;
			const model = slash > 0 ? bucket.model.slice(slash + 1) : bucket.model;
			const price = findPrice(api, provider, model);
			const key = priceKey(provider, model);
			if (price) {
				lookup.models.set(key, price);
			} else {
				lookup.unmatched.add(key);
			}
		}
	} catch (error) {
		lookup.message = error instanceof Error ? error.message : String(error);
		for (const bucket of buckets) lookup.unmatched.add(bucket.model);
	} finally {
		clearTimeout(timer);
	}
	return lookup;
}

function aggregate(records: UsageRecord[], now = Date.now()) {
	const windows: UsageWindow[] = WINDOWS.map((window) => ({ ...window, buckets: new Map<string, ModelBucket>() }));
	for (const record of records) {
		const timestamp = record.timestamp;
		if (!timestamp) continue;
		const model = `${record.provider}/${record.model}`;
		for (const window of windows) {
			const cutoff = now - window.days * 86_400_000;
			if (timestamp < cutoff) continue;
			addUsage(modelBucket(window.buckets, record.source, model), record.usage, numberValue(record.cost));
		}
	}
	return windows;
}

function bucketPrice(bucket: ModelBucket, lookup: PriceLookup) {
	const slash = bucket.model.indexOf("/");
	const provider = slash > 0 ? bucket.model.slice(0, slash) : bucket.source;
	const model = slash > 0 ? bucket.model.slice(slash + 1) : bucket.model;
	const price = lookup.models.get(priceKey(provider, model));
	if (!price) return bucket.cost;
	return (
		(bucket.input * price.input +
			bucket.output * price.output +
			bucket.cacheRead * price.cacheRead +
			bucket.cacheWrite * price.cacheWrite) /
		MILLION
	);
}

function totalsFor(buckets: ModelBucket[], lookup: PriceLookup) {
	return buckets.reduce(
		(total, bucket) => ({
			requests: total.requests + bucket.requests,
			input: total.input + bucket.input,
			output: total.output + bucket.output,
			cacheRead: total.cacheRead + bucket.cacheRead,
			totalTokens: total.totalTokens + bucket.totalTokens,
			price: total.price + bucketPrice(bucket, lookup),
		}),
		{ requests: 0, input: 0, output: 0, cacheRead: 0, totalTokens: 0, price: 0 },
	);
}

function usageTable(window: UsageWindow, lookup: PriceLookup) {
	const buckets = [...window.buckets.values()].sort((left, right) => `${left.source}/${left.model}`.localeCompare(`${right.source}/${right.model}`));
	if (buckets.length === 0) return ["No usage recorded in this window."];
	const totals = totalsFor(buckets, lookup);
	return [
		"| Source | Model | Messages/Turns | Input | Output | Cached In | Total Tokens | Price |",
		"| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
		...buckets.map((bucket) => `| ${bucket.source} | ${bucket.model} | ${bucket.requests} | ${formatNumber(bucket.input)} | ${formatNumber(bucket.output)} | ${formatNumber(bucket.cacheRead)} | ${formatNumber(bucket.totalTokens)} | ${formatCost(bucketPrice(bucket, lookup))} |`),
		`| **Total** |  | **${totals.requests}** | **${formatNumber(totals.input)}** | **${formatNumber(totals.output)}** | **${formatNumber(totals.cacheRead)}** | **${formatNumber(totals.totalTokens)}** | **${formatCost(totals.price)}** |`,
	];
}

function pricingNotes(lookup: PriceLookup, pi: ParseResult, codex: ParseResult) {
	const notes = [
		`- models.dev lookup: ${lookup.ok ? `ok (${lookup.date})` : `failed (${lookup.message ?? "unknown error"})`}.`,
		`- Parsed ${pi.files} Pi session files and ${codex.files} Codex CLI session files.`,
		`- Skipped malformed/unreadable lines: Pi ${pi.skipped}, Codex CLI ${codex.skipped}.`,
		"- Codex CLI uses token_count.info.last_token_usage per turn; reasoning_output_tokens are treated as already included in output/total.",
		"- Cached In uses cached input/read tokens only; no cached output column is reported.",
	];
	if (lookup.unmatched.size > 0) {
		notes.push(`- Unmatched pricing keys, using recorded local cost where present and $0 otherwise: ${[...lookup.unmatched].sort().join(", ")}.`);
	}
	return notes;
}

async function buildUsageSnapshot(): Promise<UsageSnapshot> {
	const pi = parsePiSessions();
	const codex = parseCodexSessions();
	const records = [...pi.records, ...codex.records];
	const windows = aggregate(records);
	const allBucketsByKey = new Map<string, ModelBucket>();
	for (const window of windows) {
		for (const bucket of window.buckets.values()) {
			const existing = allBucketsByKey.get(`${bucket.source}/${bucket.model}`);
			if (!existing) allBucketsByKey.set(`${bucket.source}/${bucket.model}`, bucket);
		}
	}
	const lookup = await fetchModelsDevPrices([...allBucketsByKey.values()]);
	return { generatedAt: Date.now(), windows, lookup, pi, codex };
}

function buildUsageReport(snapshot: UsageSnapshot) {
	return [
		"# Pi Usage",
		"",
		`Generated: ${new Date(snapshot.generatedAt).toLocaleString()}`,
		"",
		...snapshot.windows.flatMap((window) => [`## ${window.label}`, "", ...usageTable(window, snapshot.lookup), ""]),
		"## Pricing notes",
		...pricingNotes(snapshot.lookup, snapshot.pi, snapshot.codex),
	]
		.filter((line, index, lines) => !(line === "" && lines[index - 1] === ""))
		.join("\n");
}

function sourceLabel(source: string) {
	return source === "Codex CLI" ? "codex" : source.toLowerCase();
}

function priceTone(price: number): "normal" | "warning" | "error" {
	if (price >= 100) return "error";
	if (price >= 10) return "warning";
	return "normal";
}

function usageWindowTotals(window: UsageWindow, lookup: PriceLookup) {
	return totalsFor([...window.buckets.values()], lookup);
}

function usageBucketLine(bucket: ModelBucket, lookup: PriceLookup, width: number) {
	const price = bucketPrice(bucket, lookup);
	const source = sourceLabel(bucket.source);
	const priceColumn = padRight(formatCost(price), 10);
	const tokenColumn = padRight(`${compactNumber(bucket.totalTokens)} tok`, 13);
	const turnColumn = padRight(`${bucket.requests}x`, 7);
	const sourceColumn = padRight(source, 7);
	const prefix = `${priceColumn}  ${tokenColumn}  ${turnColumn}  ${sourceColumn}  `;
	return `${prefix}${fitText(bucket.model, Math.max(8, width - prefix.length))}`;
}

function renderWindow(theme: ThemeLike | undefined, width: number, window: UsageWindow, lookup: PriceLookup, expanded: boolean) {
	const totals = usageWindowTotals(window, lookup);
	const title = `${window.label} · ${formatCost(totals.price)} · ${compactNumber(totals.totalTokens)} tokens · ${totals.requests} turns`;
	const buckets = [...window.buckets.values()].sort((left, right) => bucketPrice(right, lookup) - bucketPrice(left, lookup));
	const lines = [panelRule(theme, width, title), panelBlank(theme, width)];
	if (buckets.length === 0) {
		lines.push(panelLine(theme, "  no usage recorded", width, "muted"), panelBlank(theme, width));
		return lines;
	}
	lines.push(panelLine(theme, "  price       tokens         turns    source   model", width, "muted"));
	lines.push(panelLine(theme, "  ──────────  ─────────────  ───────  ───────  ─────────────────────────────────", width, "muted"));
	const visibleRows = expanded ? buckets : buckets.slice(0, 5);
	for (const bucket of visibleRows) {
		lines.push(panelLine(theme, `  ${usageBucketLine(bucket, lookup, Math.max(1, width - 6))}`, width, priceTone(bucketPrice(bucket, lookup))));
	}
	if (!expanded && buckets.length > visibleRows.length) {
		const hidden = buckets.slice(visibleRows.length);
		const hiddenTotals = totalsFor(hidden, lookup);
		lines.push(panelLine(theme, `  +${hidden.length} more · ${compactNumber(hiddenTotals.totalTokens)} tokens · ${formatCost(hiddenTotals.price)} · press a to expand, m for full table`, width, "muted"));
	}
	lines.push(panelBlank(theme, width));
	return lines;
}

function renderUsageHud(snapshot: UsageSnapshot, width: number, theme: ThemeLike | undefined, expanded: boolean) {
	const panelWidth = Math.min(Math.max(78, width - 4), 128);
	const longestWindow = snapshot.windows.at(-1);
	const grand = longestWindow ? usageWindowTotals(longestWindow, snapshot.lookup) : { requests: 0, totalTokens: 0, price: 0 };
	const priceStatus = snapshot.lookup.ok ? `pricing models.dev ${snapshot.lookup.date}` : `pricing failed: ${snapshot.lookup.message ?? "unknown"}`;
	const help = `esc/q close · a ${expanded ? "collapse" : "expand"} · m full markdown`;
	const title = `Pi usage  ${formatCost(grand.price)}  ${compactNumber(grand.totalTokens)} tokens  ${grand.requests} turns`;
	const lines = [panelTopRule(theme, panelWidth, title, help), panelBlank(theme, panelWidth), panelLine(theme, `  ${priceStatus}`, panelWidth, snapshot.lookup.ok ? "muted" : "warning"), panelBlank(theme, panelWidth)];

	for (const window of snapshot.windows) {
		lines.push(...renderWindow(theme, panelWidth, window, snapshot.lookup, expanded));
	}

	const skipped = `parsed Pi ${snapshot.pi.files} files, Codex ${snapshot.codex.files}; skipped Pi ${snapshot.pi.skipped}, Codex ${snapshot.codex.skipped}`;
	lines.push(panelRule(theme, panelWidth, "Notes"));
	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelLine(theme, `  ${skipped}`, panelWidth, "muted"));
	lines.push(panelLine(theme, "  cached input/read only; Codex uses last_token_usage per token_count", panelWidth, "muted"));
	if (snapshot.lookup.unmatched.size > 0) {
		lines.push(panelLine(theme, `  unpriced: ${[...snapshot.lookup.unmatched].sort().join(", ")}`, panelWidth, "warning"));
	}
	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, undefined, false, true));

	return withPanelShadow(lines, panelWidth, theme);
}

async function showUsage(_pi: ExtensionAPI, ctx: ExtensionCommandContext) {
	const snapshot = await buildUsageSnapshot();
	const report = buildUsageReport(snapshot);
	if (!ctx.hasUI) {
		console.log(report);
		return;
	}
	let expanded = false;
	const result = await showHud(ctx, {
		render: (width, theme) => renderUsageHud(snapshot, width, theme, expanded),
		handleInput: (data, controls) => {
			if (data !== "a" && data !== "A") return false;
			expanded = !expanded;
			controls.requestRender();
			return true;
		},
	});
	if (result === "markdown") {
		await ctx.ui.editor("Usage", report);
	}
}

export default function usageExtension(pi: ExtensionAPI) {
	pi.registerCommand("usage", {
		description: "Show Pi and Codex CLI usage/cost over the last 1, 7, 30, and 90 days",
		handler: async (_args, ctx) => {
			await showUsage(pi, ctx);
		},
	});
}
