import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { visibleWidth } from "@earendil-works/pi-tui";
import {
	addUsage,
	basename,
	compactNumber,
	entryTimestamp,
	formatCost,
	formatNumber,
	increment,
	messageRole,
	modelBucket,
	numberValue,
	parseTimestamp,
	roleLabel,
	toolCallBlocks,
	toolName,
	type EntryLike,
	type MessageLike,
	type ModelBucket,
} from "./usage-core/core.js";
import {
	color,
	columnize,
	fill,
	fitText,
	gridColumnCount,
	gridLine,
	padRight,
	panelBlank,
	panelContentLine,
	panelRule,
	panelTopRule,
	showHud,
	strong,
	withPanelShadow,
	wrapItems,
	type ThemeLike,
} from "./ui-core/core.js";
import { activeWorkflow, workflows } from "./workflow-core/core.js";

const GIT_TIMEOUT_MS = 5_000;

type GitStatus = {
	branch: string;
	upstream?: string;
	changedFiles: number;
	shortStatus: string;
};

type TimedEntry = EntryLike & { ms: number };

type ToolBucket = {
	requested: number;
	results: number;
	succeeded: number;
	failed: number;
};

type SessionMetrics = {
	sessionId?: string;
	startedAt?: number;
	firstActivityAt?: number;
	lastActivityAt?: number;
	totalElapsedMs: number;
	activitySpanMs: number;
	activeMs: number;
	idleMs: number;
	apiMs: number;
	toolMs: number;
	entryCount: number;
	messageCount: number;
	turns: number;
	assistantMessages: number;
	toolRequests: number;
	toolResults: number;
	toolSucceeded: number;
	toolFailed: number;
	roleCounts: Map<string, number>;
	toolBuckets: Map<string, ToolBucket>;
	modelBuckets: Map<string, ModelBucket>;
};

function formatPercent(value: number | null | undefined): string {
	return typeof value === "number" && Number.isFinite(value) ? `${value.toFixed(1)}%` : "unknown";
}

function formatDate(value: number | undefined): string | undefined {
	if (!value || !Number.isFinite(value)) return undefined;
	return new Date(value).toLocaleString();
}

function formatDuration(ms: number | undefined): string {
	if (typeof ms !== "number" || !Number.isFinite(ms) || ms < 0) return "unknown";
	if (ms < 1_000) return `${Math.round(ms)}ms`;
	const totalSeconds = Math.round(ms / 1000);
	const days = Math.floor(totalSeconds / 86_400);
	const hours = Math.floor((totalSeconds % 86_400) / 3_600);
	const minutes = Math.floor((totalSeconds % 3_600) / 60);
	const seconds = totalSeconds % 60;
	const parts: string[] = [];
	if (days) parts.push(`${days}d`);
	if (hours) parts.push(`${hours}h`);
	if (minutes) parts.push(`${minutes}m`);
	if (seconds || parts.length === 0) parts.push(`${seconds}s`);
	return parts.slice(0, 3).join(" ");
}

function commandLine(name: string, value: string | undefined): string {
	return `- ${name}: ${value && value.trim() ? value : "none"}`;
}

function toolBucket(map: Map<string, ToolBucket>, name: string): ToolBucket {
	let bucket = map.get(name);
	if (!bucket) {
		bucket = { requested: 0, results: 0, succeeded: 0, failed: 0 };
		map.set(name, bucket);
	}
	return bucket;
}

function toolResultFailed(message: MessageLike): boolean {
	if (message.isError === true) return true;
	const details = (message as { details?: { ok?: unknown } }).details;
	return details?.ok === false;
}

function toolResultSucceeded(message: MessageLike): boolean {
	return !toolResultFailed(message);
}

function computeActiveMs(entries: TimedEntry[]): number {
	let activeMs = 0;
	let activeStart: number | undefined;
	let activeEnd: number | undefined;

	for (const entry of entries) {
		const role = messageRole(entry);
		if (role === "user") {
			if (activeStart !== undefined && activeEnd !== undefined && activeEnd > activeStart) {
				activeMs += activeEnd - activeStart;
			}
			activeStart = entry.ms;
			activeEnd = undefined;
			continue;
		}

		if (activeStart !== undefined) activeEnd = entry.ms;
	}

	if (activeStart !== undefined && activeEnd !== undefined && activeEnd > activeStart) {
		activeMs += activeEnd - activeStart;
	}

	return activeMs;
}

function computeApiMs(entries: TimedEntry[]): number {
	let apiMs = 0;
	for (let index = 0; index < entries.length; index += 1) {
		const entry = entries[index];
		if (messageRole(entry) !== "assistant") continue;
		const previous = entries[index - 1];
		if (!previous) continue;
		const delta = entry.ms - previous.ms;
		if (delta >= 0) apiMs += delta;
	}
	return apiMs;
}

function computeToolMs(entries: TimedEntry[]): number {
	let toolMs = 0;
	for (let index = 0; index < entries.length; index += 1) {
		const entry = entries[index];
		if (messageRole(entry) !== "assistant" || toolCallBlocks(entry.message).length === 0) continue;

		let groupEnd = entry.ms;
		for (const next of entries.slice(index + 1)) {
			const role = messageRole(next);
			if (role === "assistant" || role === "user") break;
			if (role === "toolResult" || role === "bashExecution") groupEnd = Math.max(groupEnd, next.ms);
		}
		if (groupEnd > entry.ms) toolMs += groupEnd - entry.ms;
	}
	return toolMs;
}

function buildMetrics(ctx: ExtensionCommandContext): SessionMetrics {
	const header = ctx.sessionManager.getHeader() as { id?: string; timestamp?: string } | undefined;
	const branch = ctx.sessionManager.getBranch() as EntryLike[];
	const entries = branch
		.map((entry) => ({ ...entry, ms: entryTimestamp(entry) }))
		.filter((entry): entry is TimedEntry => typeof entry.ms === "number" && Number.isFinite(entry.ms))
		.sort((left, right) => left.ms - right.ms);

	const now = Date.now();
	const startedAt = parseTimestamp(header?.timestamp) ?? entries[0]?.ms ?? now;
	const firstActivityAt = entries[0]?.ms;
	const lastActivityAt = entries.at(-1)?.ms;
	const totalElapsedMs = Math.max(0, now - startedAt);
	const activitySpanMs = firstActivityAt && lastActivityAt ? Math.max(0, lastActivityAt - firstActivityAt) : 0;
	const activeMs = computeActiveMs(entries);
	const apiMs = computeApiMs(entries);
	const toolMs = computeToolMs(entries);
	const roleCounts = new Map<string, number>();
	const toolBuckets = new Map<string, ToolBucket>();
	const modelBuckets = new Map<string, ModelBucket>();

	let messageCount = 0;
	let turns = 0;
	let assistantMessages = 0;
	let toolRequests = 0;
	let toolResults = 0;
	let toolSucceeded = 0;
	let toolFailed = 0;

	for (const entry of branch) {
		const role = messageRole(entry);
		increment(roleCounts, roleLabel(entry));
		if (entry.type === "message") messageCount += 1;
		if (role === "user") turns += 1;

		if (role === "assistant") {
			assistantMessages += 1;
			for (const block of toolCallBlocks(entry.message)) {
				const name = block.name ?? "unknown";
				toolBucket(toolBuckets, name).requested += 1;
				toolRequests += 1;
			}

			const usage = entry.message?.usage;
			if (usage) {
				const source = entry.message?.provider || "unknown";
				const model = entry.message?.model || "unknown";
				addUsage(modelBucket(modelBuckets, source, model), usage);
			}
		}

		if (role === "toolResult") {
			const name = entry.message?.toolName || "unknown";
			const bucket = toolBucket(toolBuckets, name);
			bucket.results += 1;
			toolResults += 1;
			if (entry.message && toolResultSucceeded(entry.message)) {
				bucket.succeeded += 1;
				toolSucceeded += 1;
			} else {
				bucket.failed += 1;
				toolFailed += 1;
			}
		}

		if (role === "bashExecution") {
			const bucket = toolBucket(toolBuckets, "user_bash");
			bucket.results += 1;
			toolResults += 1;
			if (entry.message?.cancelled || (typeof entry.message?.exitCode === "number" && entry.message.exitCode !== 0)) {
				bucket.failed += 1;
				toolFailed += 1;
			} else {
				bucket.succeeded += 1;
				toolSucceeded += 1;
			}
		}
	}

	return {
		sessionId: header?.id,
		startedAt,
		firstActivityAt,
		lastActivityAt,
		totalElapsedMs,
		activitySpanMs,
		activeMs,
		idleMs: Math.max(0, totalElapsedMs - activeMs),
		apiMs,
		toolMs,
		entryCount: branch.length,
		messageCount,
		turns,
		assistantMessages,
		toolRequests,
		toolResults,
		toolSucceeded,
		toolFailed,
		roleCounts,
		toolBuckets,
		modelBuckets,
	};
}

async function execText(pi: ExtensionAPI, cwd: string, command: string): Promise<string | undefined> {
	try {
		const result = await pi.exec("bash", ["-lc", command], { cwd, timeout: GIT_TIMEOUT_MS });
		if (result.code !== 0) return undefined;
		return (result.stdout || result.stderr || "").trim();
	} catch {
		return undefined;
	}
}

async function readGitStatus(pi: ExtensionAPI, cwd: string): Promise<GitStatus | undefined> {
	const inside = await execText(pi, cwd, "git rev-parse --is-inside-work-tree 2>/dev/null");
	if (inside !== "true") return undefined;

	const branch =
		(await execText(pi, cwd, "git branch --show-current 2>/dev/null")) ||
		(await execText(pi, cwd, "git rev-parse --short HEAD 2>/dev/null")) ||
		"unknown";
	const upstream = await execText(pi, cwd, "git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null");
	const shortStatus = (await execText(pi, cwd, "git status --short 2>/dev/null")) || "";
	const changedFiles = shortStatus.split("\n").filter((line) => line.trim()).length;

	return { branch, upstream, changedFiles, shortStatus };
}

function sessionSummary(ctx: ExtensionCommandContext, metrics: SessionMetrics): string[] {
	const header = ctx.sessionManager.getHeader();
	const sessionFile = ctx.sessionManager.getSessionFile();
	const sessionName = ctx.sessionManager.getSessionName();
	const leaf = ctx.sessionManager.getLeafId();

	return [
		commandLine("Name", sessionName),
		commandLine("Session ID", metrics.sessionId ?? header?.id),
		commandLine("Session", basename(sessionFile)),
		commandLine("Session file", sessionFile ?? "ephemeral / not persisted"),
		commandLine("Parent session", header?.parentSession),
		commandLine("Leaf", leaf ?? "none"),
		commandLine("Started", formatDate(metrics.startedAt)),
		commandLine("First activity", formatDate(metrics.firstActivityAt)),
		commandLine("Last activity", formatDate(metrics.lastActivityAt)),
		commandLine("Branch entries", String(metrics.entryCount)),
		commandLine("Messages", String(metrics.messageCount)),
		commandLine("Turns", String(metrics.turns)),
	];
}

function performanceSummary(metrics: SessionMetrics): string[] {
	const activeRatio = metrics.totalElapsedMs > 0 ? (metrics.activeMs / metrics.totalElapsedMs) * 100 : 0;
	const apiRatio = metrics.activeMs > 0 ? (metrics.apiMs / metrics.activeMs) * 100 : 0;
	const toolRatio = metrics.activeMs > 0 ? (metrics.toolMs / metrics.activeMs) * 100 : 0;
	return [
		commandLine("Total session time", formatDuration(metrics.totalElapsedMs)),
		commandLine("Activity span", formatDuration(metrics.activitySpanMs)),
		commandLine("Idle / wall gap time", `${formatDuration(metrics.idleMs)} (${formatPercent(100 - activeRatio)})`),
		commandLine("Agent active time", `${formatDuration(metrics.activeMs)} (${formatPercent(activeRatio)})`),
		commandLine("API time", `${formatDuration(metrics.apiMs)} (${formatPercent(apiRatio)} of active)`),
		commandLine("Tool time", `${formatDuration(metrics.toolMs)} (${formatPercent(toolRatio)} of active)`),
	];
}

function interactionSummary(metrics: SessionMetrics): string[] {
	const successRate = metrics.toolResults > 0 ? (metrics.toolSucceeded / metrics.toolResults) * 100 : 0;
	const roleSummary = [...metrics.roleCounts.entries()]
		.sort(([left], [right]) => left.localeCompare(right))
		.map(([role, count]) => `${role}:${count}`)
		.join(", ");
	return [
		commandLine("Assistant responses", String(metrics.assistantMessages)),
		commandLine("Tool calls requested", String(metrics.toolRequests)),
		commandLine("Tool results", `${metrics.toolResults} (✓ ${metrics.toolSucceeded} × ${metrics.toolFailed})`),
		commandLine("Tool success rate", formatPercent(successRate)),
		commandLine("Roles", roleSummary || "none"),
	];
}

function modelSummary(pi: ExtensionAPI, ctx: ExtensionCommandContext): string[] {
	const model = ctx.model;
	const thinking = pi.getThinkingLevel?.();
	return [
		commandLine("Model", model ? `${model.provider}/${model.id}` : undefined),
		commandLine("Thinking", thinking),
	];
}

function toolSummary(pi: ExtensionAPI): string[] {
	const activeTools = pi.getActiveTools?.() ?? [];
	const allTools = pi.getAllTools?.() ?? [];
	const activeNames = activeTools.map(toolName).sort();
	return [
		commandLine("Active tools", activeNames.length ? activeNames.join(", ") : "none"),
		commandLine("Tool count", `${activeTools.length} active / ${allTools.length} registered`),
	];
}

function contextSummary(ctx: ExtensionCommandContext): string[] {
	const usage = ctx.getContextUsage();
	if (!usage) {
		return [commandLine("Context", "unknown")];
	}
	return [
		commandLine("Context tokens", `${formatNumber(usage.tokens)} / ${formatNumber(usage.contextWindow)}`),
		commandLine("Context used", formatPercent(usage.percent)),
	];
}

function commandSummary(pi: ExtensionAPI): string[] {
	const commands = pi.getCommands?.() ?? [];
	const extensionCommands = commands.filter((command) => command.source === "extension").length;
	const promptCommands = commands.filter((command) => command.source === "prompt").length;
	const skillCommands = commands.filter((command) => command.source === "skill").length;
	return [
		commandLine("Commands", `${commands.length} total (${extensionCommands} extension, ${promptCommands} prompt, ${skillCommands} skill)`),
	];
}

function workflowSummary(ctx: ExtensionCommandContext): string[] {
	const active = activeWorkflow(ctx);
	const count = workflows(ctx).length;
	if (!active) return [commandLine("Active workflow", "none"), commandLine("Workflow count", String(count))];
	return [
		commandLine("Active workflow", `${active.controller}: ${active.title}`),
		commandLine("Workflow status", active.status),
		commandLine("Workflow objective", active.objective),
		commandLine("Workflow count", String(count)),
	];
}

function gitSummary(git: GitStatus | undefined): string[] {
	if (!git) return [commandLine("Git", "not a git repository")];
	const state = git.changedFiles === 0 ? "clean" : `${git.changedFiles} changed file${git.changedFiles === 1 ? "" : "s"}`;
	const lines = [
		commandLine("Branch", git.branch),
		commandLine("Upstream", git.upstream),
		commandLine("Working tree", state),
	];
	if (git.shortStatus) {
		const preview = git.shortStatus.split("\n").slice(0, 12).join("\n");
		lines.push("", "```text", preview, git.changedFiles > 12 ? `... ${git.changedFiles - 12} more` : "", "```");
	}
	return lines;
}

type Pair = [label: string, value: string];

type StatusSnapshot = {
	metrics: SessionMetrics;
	git?: GitStatus;
	version?: string;
	generatedAt: number;
	cwd: string;
	sessionName?: string;
	sessionFile?: string;
	parentSession?: string;
	leaf?: string;
	model?: string;
	thinking?: string;
	context?: ReturnType<ExtensionCommandContext["getContextUsage"]>;
	activeTools: string[];
	allToolCount: number;
	commandCount: number;
	extensionCommandCount: number;
	promptCommandCount: number;
	skillCommandCount: number;
	workflowActive?: ReturnType<typeof activeWorkflow>;
	workflowCount: number;
};

function itemPart(_theme: ThemeLike | undefined, label: string, value: string | number): string {
	return `${label} ${String(value)}`;
}

function compactDate(value: number | undefined): string {
	if (!value || !Number.isFinite(value)) return "unknown";
	return new Date(value).toLocaleString(undefined, {
		month: "short",
		day: "numeric",
		hour: "2-digit",
		minute: "2-digit",
	});
}

function ageFrom(value: number | undefined): string {
	if (!value || !Number.isFinite(value)) return "unknown";
	return `${formatDuration(Date.now() - value)} ago`;
}

function shortMiddle(text: string, width: number): string {
	if (visibleWidth(text) <= width) return text;
	if (width <= 1) return "…";
	if (width <= 12) return fitText(text, width);
	const left = Math.max(4, Math.floor((width - 1) * 0.65));
	const right = Math.max(4, width - left - 1);
	return `${text.slice(0, left)}…${text.slice(-right)}`;
}

function tightDuration(ms: number | undefined): string {
	return formatDuration(ms).replace(/ /g, "");
}

function panelGridRows(theme: ThemeLike | undefined, width: number, rows: Array<[string, string[]]>, columns = 3): string[] {
	const inner = Math.max(1, width - 4);
	const keyWidth = 9;
	const labelGap = 3;
	const valueWidth = Math.max(1, inner - keyWidth - labelGap);
	const lines: string[] = [];
	for (const [key, parts] of rows) {
		const values = parts.length ? parts : ["none"];
		for (let index = 0; index < values.length; index += columns) {
			const label = index === 0 ? padRight(key, keyWidth) : fill(keyWidth);
			lines.push(panelContentLine(theme, `${label}${fill(labelGap)}${gridLine(values.slice(index, index + columns), valueWidth, columns)}`, width));
		}
	}
	return lines;
}

function panelKeyRows(theme: ThemeLike | undefined, width: number, rows: Array<[string, string[]]>) {
	const inner = Math.max(1, width - 4);
	const keyWidth = Math.min(11, Math.max(5, ...rows.map(([key]) => visibleWidth(key))));
	const labelGap = 4;
	const valueWidth = Math.max(1, inner - keyWidth - labelGap);
	const columns = gridColumnCount(valueWidth);
	const lines: string[] = [];
	for (const [key, parts] of rows) {
		const values = parts.length ? parts : ["none"];
		for (let index = 0; index < values.length; index += columns) {
			const label = index === 0 ? padRight(key, keyWidth) : fill(keyWidth);
			lines.push(panelContentLine(theme, `${label}${fill(labelGap)}${gridLine(values.slice(index, index + columns), valueWidth, columns)}`, width));
		}
	}
	return lines;
}

function pairRowsPlain(pairs: Pair[], width: number): string[] {
	const labelWidth = Math.min(13, Math.max(7, ...pairs.map(([label]) => label.length)));
	return pairs.map(([label, value]) => `${padRight(label, labelWidth)} ${fitText(value, Math.max(1, width - labelWidth - 1))}`);
}

function twoColumns(theme: ThemeLike | undefined, width: number, leftTitle: string, left: Pair[], rightTitle: string, right: Pair[]): string[] {
	const gap = 3;
	const colWidth = Math.max(30, Math.floor((width - gap) / 2));
	const leftRows = pairRowsPlain(left, colWidth);
	const rightRows = pairRowsPlain(right, colWidth);
	const rowCount = Math.max(leftRows.length, rightRows.length);
	const lines = [`${color(theme, "accent", strong(theme, padRight(leftTitle, colWidth)))}${" ".repeat(gap)}${color(theme, "accent", strong(theme, rightTitle))}`];
	for (let index = 0; index < rowCount; index += 1) {
		lines.push(`${padRight(leftRows[index] ?? "", colWidth)}${" ".repeat(gap)}${rightRows[index] ?? ""}`);
	}
	return lines;
}

function pairLines(theme: ThemeLike | undefined, width: number, title: string, pairs: Pair[]): string[] {
	const rows = pairRowsPlain(pairs, Math.max(20, width - 2));
	return [color(theme, "accent", strong(theme, title)), ...rows.map((row) => `  ${fitText(row, Math.max(1, width - 2))}`)];
}

function wrapParts(theme: ThemeLike | undefined, width: number, title: string, parts: string[]): string[] {
	const prefix = `${title}  `;
	const continuation = " ".repeat(prefix.length);
	const rawParts = parts.length ? parts : ["none"];
	const lines: string[] = [];
	let current = prefix;
	for (const part of rawParts) {
		const candidate = current === prefix || current === continuation ? current + part : `${current}   ${part}`;
		if (candidate.length <= width) {
			current = candidate;
			continue;
		}
		if (current.trim()) lines.push(current);
		current = continuation + fitText(part, Math.max(1, width - continuation.length));
	}
	if (current.trim()) lines.push(current);
	return lines.map((line, index) => {
		if (index === 0 && line.startsWith(prefix)) {
			return `${color(theme, "accent", strong(theme, title))}  ${fitText(line.slice(prefix.length), Math.max(1, width - prefix.length))}`;
		}
		return fitText(line, width);
	});
}

function modelTotals(metrics: SessionMetrics): ModelBucket {
	return [...metrics.modelBuckets.values()].reduce(
		(total, bucket) => ({
			source: "",
			model: "total",
			requests: total.requests + bucket.requests,
			input: total.input + bucket.input,
			output: total.output + bucket.output,
			cacheRead: total.cacheRead + bucket.cacheRead,
			cacheWrite: total.cacheWrite + bucket.cacheWrite,
			totalTokens: total.totalTokens + bucket.totalTokens,
			cost: total.cost + bucket.cost,
		}),
		{ source: "", model: "total", requests: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: 0 },
	);
}

function modelParts(metrics: SessionMetrics): string[] {
	const buckets = [...metrics.modelBuckets.values()].sort((left, right) => `${left.source}/${left.model}`.localeCompare(`${right.source}/${right.model}`));
	if (buckets.length === 0) return ["no model usage recorded"];
	return buckets.map((bucket) => `${bucket.source}/${bucket.model} req ${bucket.requests} in ${compactNumber(bucket.input)} cache ${compactNumber(bucket.cacheRead + bucket.cacheWrite)} out ${compactNumber(bucket.output)} total ${compactNumber(bucket.totalTokens)} cost ${formatCost(bucket.cost)}`);
}

function tableRow(cells: string[], widths: number[], gap = 3): string {
	return cells.map((cell, index) => padRight(fitText(cell, widths[index] ?? 8), widths[index] ?? 8)).join(fill(gap)).trimEnd();
}

function modelTableLines(theme: ThemeLike | undefined, width: number, metrics: SessionMetrics): string[] {
	const buckets = [...metrics.modelBuckets.values()].sort((left, right) => `${left.source}/${left.model}`.localeCompare(`${right.source}/${right.model}`));
	if (buckets.length === 0) return [panelContentLine(theme, "no model usage recorded", width)];

	const inner = Math.max(1, width - 4);
	const fixed = [5, 8, 8, 8, 8, 9];
	const gap = 3;
	const modelWidth = Math.max(18, inner - fixed.reduce((sum, next) => sum + next, 0) - gap * fixed.length);
	const widths = [modelWidth, ...fixed];
	const lines = [panelContentLine(theme, tableRow(["model", "req", "input", "cache", "output", "total", "cost"], widths, gap), width, "muted")];
	for (const bucket of buckets) {
		lines.push(panelContentLine(theme, tableRow([
			shortMiddle(`${bucket.source}/${bucket.model}`, modelWidth),
			String(bucket.requests),
			compactNumber(bucket.input),
			compactNumber(bucket.cacheRead + bucket.cacheWrite),
			compactNumber(bucket.output),
			compactNumber(bucket.totalTokens),
			formatCost(bucket.cost),
		], widths, gap), width));
	}
	return lines;
}

function toolParts(metrics: SessionMetrics): string[] {
	const buckets = [...metrics.toolBuckets.entries()].sort(([left], [right]) => left.localeCompare(right));
	if (buckets.length === 0) return ["no tool calls recorded"];
	return buckets.map(([name, bucket]) => {
		const health = bucket.failed ? `ok ${bucket.succeeded}/fail ${bucket.failed}` : `ok ${bucket.succeeded}`;
		return `${name} req ${bucket.requested} res ${bucket.results} ${health}`;
	});
}

function gitParts(git: GitStatus | undefined): string[] {
	if (!git) return ["not a git repository"];
	const state = git.changedFiles === 0 ? "clean" : `${git.changedFiles} changed`;
	const head = [`${git.branch}`, git.upstream ? `→ ${git.upstream}` : "no upstream", state];
	const changed = git.shortStatus
		.split("\n")
		.map((line) => line.trim())
		.filter(Boolean)
		.slice(0, 12);
	if (git.changedFiles > 12) changed.push(`+${git.changedFiles - 12} more`);
	return [...head, ...changed];
}

function roleParts(metrics: SessionMetrics): string[] {
	const roles = [...metrics.roleCounts.entries()].sort(([left], [right]) => left.localeCompare(right));
	return roles.length ? roles.map(([role, count]) => `${role} ${count}`) : ["none"];
}

function commandBreakdown(snapshot: StatusSnapshot): string {
	return `${snapshot.commandCount} total (${snapshot.extensionCommandCount} ext, ${snapshot.promptCommandCount} prompt, ${snapshot.skillCommandCount} skill)`;
}

function contextValue(snapshot: StatusSnapshot): string {
	const usage = snapshot.context;
	if (!usage) return "unknown";
	return `${compactNumber(usage.tokens)} / ${compactNumber(usage.contextWindow)} (${formatPercent(usage.percent)})`;
}

function workflowParts(snapshot: StatusSnapshot): string[] {
	const active = snapshot.workflowActive;
	if (!active) return [`none (${snapshot.workflowCount} stored)`];
	return [`${active.controller}:${active.status}`, active.title, active.objective, `${snapshot.workflowCount} stored`];
}

function buildSnapshot(pi: ExtensionAPI, ctx: ExtensionCommandContext, metrics: SessionMetrics, git: GitStatus | undefined, version: string | undefined): StatusSnapshot {
	const commands = pi.getCommands?.() ?? [];
	const activeTools = (pi.getActiveTools?.() ?? []).map(toolName).sort();
	const allTools = pi.getAllTools?.() ?? [];
	const active = activeWorkflow(ctx);
	const header = ctx.sessionManager.getHeader();
	const model = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined;
	return {
		metrics,
		git,
		version,
		generatedAt: Date.now(),
		cwd: ctx.cwd,
		sessionName: ctx.sessionManager.getSessionName(),
		sessionFile: ctx.sessionManager.getSessionFile(),
		parentSession: header?.parentSession,
		leaf: ctx.sessionManager.getLeafId(),
		model,
		thinking: pi.getThinkingLevel?.(),
		context: ctx.getContextUsage(),
		activeTools,
		allToolCount: allTools.length,
		commandCount: commands.length,
		extensionCommandCount: commands.filter((command) => command.source === "extension").length,
		promptCommandCount: commands.filter((command) => command.source === "prompt").length,
		skillCommandCount: commands.filter((command) => command.source === "skill").length,
		workflowActive: active,
		workflowCount: workflows(ctx).length,
	};
}

function renderStatusHud(snapshot: StatusSnapshot, width: number, theme?: ThemeLike): string[] {
	const panelWidth = Math.max(64, width - 2);
	const inner = Math.max(1, panelWidth - 4);
	const metrics = snapshot.metrics;
	const totals = modelTotals(metrics);
	const activeRatio = metrics.totalElapsedMs > 0 ? (metrics.activeMs / metrics.totalElapsedMs) * 100 : 0;
	const apiRatio = metrics.activeMs > 0 ? (metrics.apiMs / metrics.activeMs) * 100 : 0;
	const toolRatio = metrics.activeMs > 0 ? (metrics.toolMs / metrics.activeMs) * 100 : 0;
	const successRate = metrics.toolResults > 0 ? (metrics.toolSucceeded / metrics.toolResults) * 100 : 0;
	const title = `Pi status  ${snapshot.model ?? "unknown model"}`;
	const help = "esc/q close · m markdown";
	const lines: string[] = [panelTopRule(theme, panelWidth, title, help)];

	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelContentLine(theme, gridLine([itemPart(theme, "thinking", snapshot.thinking ?? "?"), itemPart(theme, "ctx", snapshot.context ? formatPercent(snapshot.context.percent) : "unknown"), itemPart(theme, "tokens", compactNumber(totals.totalTokens)), itemPart(theme, "cost", formatCost(totals.cost))], inner, gridColumnCount(inner)), panelWidth, "accent"));
	lines.push(panelBlank(theme, panelWidth));

	lines.push(panelRule(theme, panelWidth, "Session"));
	lines.push(...panelGridRows(theme, panelWidth, [
		["session", [shortMiddle(snapshot.sessionName ?? basename(snapshot.sessionFile) ?? "unnamed", Math.max(24, inner - 14))]],
		["time", [`started ${compactDate(metrics.startedAt)}`, `last ${ageFrom(metrics.lastActivityAt)}`, `elapsed ${tightDuration(metrics.totalElapsedMs)}`]],
		["activity", [`active ${tightDuration(metrics.activeMs)} (${formatPercent(activeRatio)})`, `idle ${tightDuration(metrics.idleMs)}`, `span ${tightDuration(metrics.activitySpanMs)}`]],
		["branch", [`leaf ${snapshot.leaf ?? "none"}`, `parent ${snapshot.parentSession ? shortMiddle(basename(snapshot.parentSession) ?? snapshot.parentSession, 32) : "none"}`]],
	], 3));

	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, "Work and usage"));
	lines.push(...panelGridRows(theme, panelWidth, [
		["turns", [`user ${metrics.turns}`, `assistant ${metrics.assistantMessages}`, `entries ${metrics.entryCount}`, `messages ${metrics.messageCount}`]],
		["tools", [`requested ${metrics.toolRequests}`, `results ${metrics.toolResults}`, `success ${formatPercent(successRate)}`, `ok ${metrics.toolSucceeded}`, `fail ${metrics.toolFailed}`]],
		["time", [`api ${tightDuration(metrics.apiMs)} / ${formatPercent(apiRatio)}`, `tool ${tightDuration(metrics.toolMs)} / ${formatPercent(toolRatio)}`]],
		["context", [contextValue(snapshot), `model ${shortMiddle(snapshot.model ?? "unknown", 34)}`]],
		["tokens", [`requests ${totals.requests}`, `input ${compactNumber(totals.input)}`, `cache ${compactNumber(totals.cacheRead + totals.cacheWrite)}`, `output ${compactNumber(totals.output)}`, `total ${compactNumber(totals.totalTokens)}`, `cost ${formatCost(totals.cost)}`]],
	].map(([key, values]) => [key, values] as [string, string[]]), 3));

	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, "Roles"));
	for (const line of columnize(roleParts(metrics), inner)) lines.push(panelContentLine(theme, line, panelWidth));

	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, "Models"));
	lines.push(...modelTableLines(theme, panelWidth, metrics));

	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, "Tool usage"));
	for (const part of toolParts(metrics)) lines.push(panelContentLine(theme, part, panelWidth, part.includes("fail") && !part.endsWith("fail 0") ? "warning" : "normal"));

	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, "Active tools"));
	lines.push(panelContentLine(theme, `${snapshot.activeTools.length} active / ${snapshot.allToolCount} registered`, panelWidth));
	for (const line of columnize(snapshot.activeTools, inner)) lines.push(panelContentLine(theme, line, panelWidth));

	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, "Commands, workflow, git"));
	lines.push(panelContentLine(theme, `commands ${commandBreakdown(snapshot)}`, panelWidth));
	for (const line of wrapItems(workflowParts(snapshot), inner, "      ")) lines.push(panelContentLine(theme, `workflow    ${line}`, panelWidth));
	for (const line of wrapItems(gitParts(snapshot.git), inner, "      ")) lines.push(panelContentLine(theme, `git         ${line}`, panelWidth));
	lines.push(panelContentLine(theme, `cwd ${snapshot.cwd}`, panelWidth, "muted"));
	lines.push(panelContentLine(theme, `generated ${compactDate(snapshot.generatedAt)}   pi ${snapshot.version || "unknown"}`, panelWidth, "muted"));
	lines.push(panelBlank(theme, panelWidth));
	lines.push(panelRule(theme, panelWidth, undefined, false, true));

	return withPanelShadow(lines, panelWidth, theme);
}

function buildCompactStatusText(snapshot: StatusSnapshot): string {
	return renderStatusHud(snapshot, 120).join("\n");
}

async function showStatusHud(pi: ExtensionAPI, ctx: ExtensionCommandContext): Promise<void> {
	const metrics = buildMetrics(ctx);
	const git = await readGitStatus(pi, ctx.cwd);
	const version = await execText(pi, ctx.cwd, "pi --version 2>/dev/null");
	const snapshot = buildSnapshot(pi, ctx, metrics, git, version);

	if (!ctx.hasUI) {
		console.log(buildCompactStatusText(snapshot));
		return;
	}

	const result = await showHud(ctx, {
		render: (width, theme) => renderStatusHud(snapshot, width, theme),
	});
	if (result === "markdown") {
		await ctx.ui.editor("Pi status", await buildStatus(pi, ctx));
	}
}

function modelUsageTable(metrics: SessionMetrics): string[] {
	const buckets = [...metrics.modelBuckets.values()].sort((left, right) => `${left.source}/${left.model}`.localeCompare(`${right.source}/${right.model}`));
	if (buckets.length === 0) return ["No model usage recorded yet."];

	const totals = buckets.reduce(
		(total, bucket) => ({
			source: "",
			model: "Total",
			requests: total.requests + bucket.requests,
			input: total.input + bucket.input,
			output: total.output + bucket.output,
			cacheRead: total.cacheRead + bucket.cacheRead,
			cacheWrite: total.cacheWrite + bucket.cacheWrite,
			totalTokens: total.totalTokens + bucket.totalTokens,
			cost: total.cost + bucket.cost,
		}),
		{ source: "", model: "Total", requests: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: 0 },
	);

	return [
		"| Source | Model | Reqs | Input | Cache Read | Cache Write | Output | Total | Cost |",
		"| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
		...buckets.map((bucket) => `| ${bucket.source} | ${bucket.model} | ${bucket.requests} | ${formatNumber(bucket.input)} | ${formatNumber(bucket.cacheRead)} | ${formatNumber(bucket.cacheWrite)} | ${formatNumber(bucket.output)} | ${formatNumber(bucket.totalTokens)} | ${formatCost(bucket.cost)} |`),
		`|  | **Total** | **${totals.requests}** | **${formatNumber(totals.input)}** | **${formatNumber(totals.cacheRead)}** | **${formatNumber(totals.cacheWrite)}** | **${formatNumber(totals.output)}** | **${formatNumber(totals.totalTokens)}** | **${formatCost(totals.cost)}** |`,
	];
}

function toolUsageTable(metrics: SessionMetrics): string[] {
	const buckets = [...metrics.toolBuckets.entries()].sort(([left], [right]) => left.localeCompare(right));
	if (buckets.length === 0) return ["No tool calls recorded yet."];
	return [
		"| Tool | Requested | Results | Succeeded | Failed | Success rate |",
		"| --- | ---: | ---: | ---: | ---: | ---: |",
		...buckets.map(([name, bucket]) => {
			const rate = bucket.results > 0 ? (bucket.succeeded / bucket.results) * 100 : 0;
			return `| ${name} | ${bucket.requested} | ${bucket.results} | ${bucket.succeeded} | ${bucket.failed} | ${formatPercent(rate)} |`;
		}),
	];
}

async function buildStatus(pi: ExtensionAPI, ctx: ExtensionCommandContext): Promise<string> {
	const metrics = buildMetrics(ctx);
	const git = await readGitStatus(pi, ctx.cwd);
	const version = await execText(pi, ctx.cwd, "pi --version 2>/dev/null");
	const now = new Date().toLocaleString();

	return [
		"# Pi Status",
		"",
		commandLine("Generated", now),
		commandLine("Pi", version || "unknown"),
		commandLine("Directory", ctx.cwd),
		"",
		"## Session",
		...sessionSummary(ctx, metrics),
		"",
		"## Interaction Summary",
		...interactionSummary(metrics),
		"",
		"## Performance",
		...performanceSummary(metrics),
		"",
		"## Model",
		...modelSummary(pi, ctx),
		"",
		"## Model Usage",
		...modelUsageTable(metrics),
		"",
		"## Tool Usage",
		...toolUsageTable(metrics),
		"",
		"## Context",
		...contextSummary(ctx),
		"",
		"## Tools and commands",
		...toolSummary(pi),
		...commandSummary(pi),
		"",
		"## Workflow",
		...workflowSummary(ctx),
		"",
		"## Git",
		...gitSummary(git),
	]
		.filter((line, index, lines) => !(line === "" && lines[index - 1] === ""))
		.join("\n");
}

export default function statusExtension(pi: ExtensionAPI) {
	pi.registerCommand("status", {
		description: "Show a compact Pi session HUD with model, context, workflow, tools, timing, usage, and git status",
		handler: async (_args, ctx) => {
			await showStatusHud(pi, ctx);
		},
	});
}
