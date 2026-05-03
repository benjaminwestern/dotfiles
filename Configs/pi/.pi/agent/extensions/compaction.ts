import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

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

function sanitizeStatusText(text: string): string {
	return text
		.replace(/[\r\n\t]/g, " ")
		.replace(/ +/g, " ")
		.trim();
}

function statusLabel(ctx: ExtensionContext, config: RatioConfig, compacting: boolean): string {
	if (!config.enabled) return "ctx off";
	const usage = ctx.getContextUsage();
	const current = usage?.percent == null ? "--" : `${Math.round(usage.percent)}%`;
	return `ctx ${current}/${ratioLabel(config.ratio)}${compacting ? " compacting" : ""}`;
}

function installFooter(pi: ExtensionAPI, ctx: ExtensionContext, isCompacting: () => boolean) {
	ctx.ui.setStatus(STATUS_ID, undefined);
	ctx.ui.setFooter((tui, theme, footerData) => {
		const unsubscribeBranch = footerData.onBranchChange(() => tui.requestRender());

		return {
			dispose: unsubscribeBranch,
			invalidate() {},
			render(width: number): string[] {
				let totalInput = 0;
				let totalOutput = 0;
				let totalCacheRead = 0;
				let totalCacheWrite = 0;
				let totalCost = 0;

				for (const entry of ctx.sessionManager.getEntries()) {
					if (entry.type === "message" && entry.message.role === "assistant") {
						totalInput += entry.message.usage.input;
						totalOutput += entry.message.usage.output;
						totalCacheRead += entry.message.usage.cacheRead;
						totalCacheWrite += entry.message.usage.cacheWrite;
						totalCost += entry.message.usage.cost.total;
					}
				}

				const model = ctx.model;
				const usage = ctx.getContextUsage();
				const contextWindow = usage?.contextWindow ?? model?.contextWindow ?? 0;
				const contextPercentValue = usage?.percent ?? 0;
				const contextPercent = usage?.percent !== null ? contextPercentValue.toFixed(1) : "?";

				let pwd = ctx.sessionManager.getCwd();
				const home = process.env.HOME || process.env.USERPROFILE;
				if (home && pwd.startsWith(home)) {
					pwd = `~${pwd.slice(home.length)}`;
				}

				const branch = footerData.getGitBranch();
				if (branch) pwd = `${pwd} (${branch})`;

				const sessionName = ctx.sessionManager.getSessionName();
				if (sessionName) pwd = `${pwd} • ${sessionName}`;

				const statsParts: string[] = [];
				if (totalInput) statsParts.push(`↑${formatTokens(totalInput)}`);
				if (totalOutput) statsParts.push(`↓${formatTokens(totalOutput)}`);
				if (totalCacheRead) statsParts.push(`R${formatTokens(totalCacheRead)}`);
				if (totalCacheWrite) statsParts.push(`W${formatTokens(totalCacheWrite)}`);

				const usingSubscription = model ? ctx.modelRegistry.isUsingOAuth(model) : false;
				if (totalCost || usingSubscription) {
					statsParts.push(`$${totalCost.toFixed(3)}${usingSubscription ? " (sub)" : ""}`);
				}

				const contextPercentDisplay =
					contextPercent === "?" ? `?/${formatTokens(contextWindow)} (auto)` : `${contextPercent}%/${formatTokens(contextWindow)} (auto)`;
				let contextPercentStr: string;
				if (contextPercentValue > 90) {
					contextPercentStr = theme.fg("error", contextPercentDisplay);
				} else if (contextPercentValue > 70) {
					contextPercentStr = theme.fg("warning", contextPercentDisplay);
				} else {
					contextPercentStr = contextPercentDisplay;
				}
				statsParts.push(contextPercentStr);

				const config = loadRatioConfig(ctx.cwd);
				statsParts.push(statusLabel(ctx, config, isCompacting()));

				const extensionStatuses = footerData.getExtensionStatuses();
				if (extensionStatuses.size > 0) {
					const sortedStatuses = Array.from(extensionStatuses.entries())
						.filter(([key]) => key !== STATUS_ID)
						.sort(([a], [b]) => a.localeCompare(b))
						.map(([, text]) => sanitizeStatusText(text))
						.filter(Boolean);
					statsParts.push(...sortedStatuses);
				}

				let statsLeft = statsParts.join(" ");
				let statsLeftWidth = visibleWidth(statsLeft);
				if (statsLeftWidth > width) {
					statsLeft = truncateToWidth(statsLeft, width, "...");
					statsLeftWidth = visibleWidth(statsLeft);
				}

				const modelName = model?.id || "no-model";
				let rightSideWithoutProvider = modelName;
				if (model?.reasoning) {
					const thinkingLevel = pi.getThinkingLevel() || "off";
					rightSideWithoutProvider = thinkingLevel === "off" ? `${modelName} • thinking off` : `${modelName} • ${thinkingLevel}`;
				}

				const minPadding = 2;
				let rightSide = rightSideWithoutProvider;
				if (footerData.getAvailableProviderCount() > 1 && model) {
					rightSide = `(${model.provider}) ${rightSideWithoutProvider}`;
					if (statsLeftWidth + minPadding + visibleWidth(rightSide) > width) {
						rightSide = rightSideWithoutProvider;
					}
				}

				const rightSideWidth = visibleWidth(rightSide);
				let statsLine: string;
				if (statsLeftWidth + minPadding + rightSideWidth <= width) {
					statsLine = statsLeft + " ".repeat(width - statsLeftWidth - rightSideWidth) + rightSide;
				} else {
					const availableForRight = width - statsLeftWidth - minPadding;
					if (availableForRight > 0) {
						const truncatedRight = truncateToWidth(rightSide, availableForRight, "");
						const truncatedRightWidth = visibleWidth(truncatedRight);
						statsLine = statsLeft + " ".repeat(Math.max(0, width - statsLeftWidth - truncatedRightWidth)) + truncatedRight;
					} else {
						statsLine = statsLeft;
					}
				}

				const dimStatsLeft = theme.fg("dim", statsLeft);
				const dimRemainder = theme.fg("dim", statsLine.slice(statsLeft.length));
				const pwdLine = truncateToWidth(theme.fg("dim", pwd), width, theme.fg("dim", "..."));
				return [pwdLine, dimStatsLeft + dimRemainder];
			},
		};
	});
}

function updateStatus(ctx: ExtensionContext) {
	ctx.ui.setStatus(STATUS_ID, undefined);
}

function triggerCompaction(
	ctx: ExtensionContext,
	config: RatioConfig,
	currentPercent: number,
	onDone?: () => void,
	manual = false,
) {
	const currentLabel = Number.isFinite(currentPercent) ? `${Math.round(currentPercent)}%` : "unknown";
	updateStatus(ctx);
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
			updateStatus(ctx);
		},
		onError: (error) => {
			onDone?.();
			if (ctx.hasUI) ctx.ui.notify(`Context compaction failed: ${error.message}`, "error");
			updateStatus(ctx);
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

		updateStatus(ctx);

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
		installFooter(pi, ctx, () => compacting);
		updateStatus(ctx);
	});

	pi.on("model_select", (_event, ctx) => {
		previousPercent = ctx.getContextUsage()?.percent ?? null;
		updateStatus(ctx);
	});

	pi.on("turn_end", (_event, ctx) => {
		maybeCompact(ctx);
	});

	pi.on("agent_end", (_event, ctx) => {
		updateStatus(ctx);
	});

	pi.on("session_compact", (_event, ctx) => {
		compacting = false;
		previousPercent = null;
		updateStatus(ctx);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus(STATUS_ID, undefined);
		ctx.ui.setFooter(undefined);
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
			updateStatus(ctx);
		},
	});
}
