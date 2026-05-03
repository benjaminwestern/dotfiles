import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const DEFAULT_RATIO = 0.75;
const STATUS_ID = "compaction";

type RatioSource = "env" | "project" | "global" | "default";

interface RatioConfig {
	enabled: boolean;
	ratio: number;
	source: RatioSource;
}

interface RawSettings {
	compaction?: {
		enabled?: boolean;
		trigger?: {
			type?: string;
			ratio?: unknown;
		};
		contextRatio?: unknown;
		ratio?: unknown;
	};
}

function parseJsonFile(path: string): RawSettings | undefined {
	try {
		if (!existsSync(path)) return undefined;
		return JSON.parse(readFileSync(path, "utf-8")) as RawSettings;
	} catch {
		return undefined;
	}
}

function expandHome(path: string): string {
	return path === "~" ? homedir() : path.startsWith("~/") ? join(homedir(), path.slice(2)) : path;
}

function agentDir(): string {
	return expandHome(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"));
}

function numericRatio(value: unknown): number | undefined {
	const ratio = typeof value === "string" ? Number(value) : typeof value === "number" ? value : Number.NaN;
	if (!Number.isFinite(ratio)) return undefined;
	return Math.max(0.01, Math.min(0.99, ratio));
}

function ratioFromSettings(settings: RawSettings | undefined): number | undefined {
	const compaction = settings?.compaction;
	if (!compaction) return undefined;

	if (compaction.trigger?.type === "contextRatio") {
		const triggerRatio = numericRatio(compaction.trigger.ratio);
		if (triggerRatio !== undefined) return triggerRatio;
	}

	return numericRatio(compaction.contextRatio) ?? numericRatio(compaction.ratio);
}

function compactionEnabled(settings: RawSettings | undefined): boolean | undefined {
	const enabled = settings?.compaction?.enabled;
	return typeof enabled === "boolean" ? enabled : undefined;
}

function loadRatioConfig(cwd: string): RatioConfig {
	const envRatio = numericRatio(process.env.PI_CONTEXT_COMPACTION_RATIO ?? process.env.PI_COMPACTION_RATIO);
	if (envRatio !== undefined) {
		return { enabled: true, ratio: envRatio, source: "env" };
	}

	const globalSettings = parseJsonFile(join(agentDir(), "settings.json"));
	const projectSettings = parseJsonFile(join(cwd, ".pi", "settings.json"));

	const enabled = compactionEnabled(projectSettings) ?? compactionEnabled(globalSettings) ?? true;
	const projectRatio = ratioFromSettings(projectSettings);
	if (projectRatio !== undefined) return { enabled, ratio: projectRatio, source: "project" };

	const globalRatio = ratioFromSettings(globalSettings);
	if (globalRatio !== undefined) return { enabled, ratio: globalRatio, source: "global" };

	return { enabled, ratio: DEFAULT_RATIO, source: "default" };
}

function formatTokens(tokens: number | null): string {
	if (tokens === null) return "unknown";
	if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
	if (tokens >= 1_000) return `${Math.round(tokens / 1_000)}k`;
	return String(tokens);
}

function ratioLabel(ratio: number): string {
	return `${Math.round(ratio * 100)}%`;
}

function statusLabel(ctx: ExtensionContext, config: RatioConfig, compacting: boolean): string {
	if (!config.enabled) return "ctx off";
	const usage = ctx.getContextUsage();
	const current = usage?.percent == null ? "--" : `${Math.round(usage.percent)}%`;
	return `ctx ${current}/${ratioLabel(config.ratio)}${compacting ? " compacting" : ""}`;
}

function updateStatus(ctx: ExtensionContext, compacting: boolean) {
	const config = loadRatioConfig(ctx.cwd);
	ctx.ui.setStatus(STATUS_ID, statusLabel(ctx, config, compacting));
}

function triggerCompaction(
	ctx: ExtensionContext,
	config: RatioConfig,
	currentPercent: number,
	onDone?: () => void,
	manual = false,
) {
	const currentLabel = Number.isFinite(currentPercent) ? `${Math.round(currentPercent)}%` : "unknown";
	ctx.ui.setStatus(STATUS_ID, `ctx ${currentLabel}/${ratioLabel(config.ratio)} compacting`);
	if (ctx.hasUI) {
		const reason = manual
			? "Manual context compaction started"
			: `Context ${currentLabel} crossed ${ratioLabel(config.ratio)}; compaction started`;
		ctx.ui.notify(reason, "info");
	}

	ctx.compact({
		customInstructions: `${manual ? "Manual" : "Ratio-triggered"} compaction at ${currentLabel} of the model context window. Preserve current task state, decisions, file paths, commands run, open questions, and next actions.`,
		onComplete: () => {
			onDone?.();
			if (ctx.hasUI) ctx.ui.notify("Context compaction completed", "info");
			updateStatus(ctx, false);
		},
		onError: (error) => {
			onDone?.();
			if (ctx.hasUI) ctx.ui.notify(`Context compaction failed: ${error.message}`, "error");
			updateStatus(ctx, false);
		},
	});
}

export default function compaction(pi: ExtensionAPI) {
	let previousPercent: number | null | undefined;
	let compacting = false;

	const maybeCompact = (ctx: ExtensionContext) => {
		const config = loadRatioConfig(ctx.cwd);
		const usage = ctx.getContextUsage();
		const percent = usage?.percent ?? null;

		ctx.ui.setStatus(STATUS_ID, statusLabel(ctx, config, compacting));

		if (!config.enabled || compacting || percent === null) {
			previousPercent = percent;
			return;
		}

		const thresholdPercent = config.ratio * 100;
		const crossed = previousPercent === undefined || previousPercent === null || previousPercent <= thresholdPercent;
		previousPercent = percent;

		if (!crossed || percent <= thresholdPercent) return;

		compacting = true;
		triggerCompaction(ctx, config, percent, () => {
			compacting = false;
			previousPercent = null;
		});
	};

	pi.on("session_start", (_event, ctx) => {
		previousPercent = ctx.getContextUsage()?.percent ?? null;
		updateStatus(ctx, false);
	});

	pi.on("model_select", (_event, ctx) => {
		previousPercent = ctx.getContextUsage()?.percent ?? null;
		updateStatus(ctx, compacting);
	});

	pi.on("turn_end", (_event, ctx) => {
		maybeCompact(ctx);
	});

	pi.on("agent_end", (_event, ctx) => {
		updateStatus(ctx, compacting);
	});

	pi.on("session_compact", (_event, ctx) => {
		compacting = false;
		previousPercent = null;
		updateStatus(ctx, false);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus(STATUS_ID, undefined);
	});

	pi.registerCommand("compact-ratio", {
		description: "Show ratio-based context compaction status; /compact-ratio now forces compaction",
		handler: async (args, ctx) => {
			const config = loadRatioConfig(ctx.cwd);
			const usage = ctx.getContextUsage();
			const message = config.enabled
				? `Context compaction ratio: ${ratioLabel(config.ratio)} (${config.source}); current ${usage?.percent == null ? "unknown" : `${usage.percent.toFixed(1)}%`} (${formatTokens(usage?.tokens ?? null)} / ${formatTokens(usage?.contextWindow ?? null)} tokens)`
				: "Context compaction is disabled by settings.";

			if (args.trim() === "now") {
				compacting = true;
				triggerCompaction(ctx, config, usage?.percent ?? Number.NaN, () => {
					compacting = false;
					previousPercent = null;
				}, true);
				return;
			}

			ctx.ui.notify(message, "info");
			updateStatus(ctx, compacting);
		},
	});
}
