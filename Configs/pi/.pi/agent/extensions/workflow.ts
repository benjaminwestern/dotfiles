import { existsSync, readFileSync, unlinkSync, writeFileSync, appendFileSync, accessSync, constants, statSync } from "node:fs";
import { createServer, type Server } from "node:http";
import { spawn } from "node:child_process";
import { join } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
	activeWorkflow,
	changeWorkflowStatus,
	clearWorkflow,
	currentWorkflowForStatusLine,
	isWorkflowStatus,
	latestWorkflow,
	renderWorkflowList,
	renderWorkflowSummary,
	sendWorkflowPrompt,
	startWorkflow,
	updateWorkflow,
	workflowStatusLineSpec,
	workflows,
	type WorkflowController,
	type WorkflowEvent,
	type WorkflowRecord,
} from "./workflow-core/core.js";
import { goalController } from "./workflow-core/controllers/goal.js";
import { reviewController } from "./workflow-core/controllers/review.js";
import { autoresearchController } from "./workflow-core/controllers/autoresearch.js";
import { loadExtensionConfig } from "./common-core/config.js";

const WORKFLOW_TOOL_NAMES = [
	"create_goal",
	"update_goal",
	"stop_goal",
	"clear_goal",
	"create_review",
	"update_review",
	"stop_review",
	"clear_review",
	"create_autoresearch",
	"update_autoresearch",
	"stop_autoresearch",
	"clear_autoresearch",
	"workflow_status",
	"workflow_update",
];
const AUTORESEARCH_TOOL_NAMES = ["init_experiment", "research_probe", "run_preflight", "run_experiment", "log_experiment", "finalize_autoresearch"];
const AUTO_CONTINUE_CONTROLLERS = new Set(["goal", "autoresearch"]);
const AUTO_CONTINUE_SETTLED_MS = 800;
const DEFAULT_MAX_AUTO_TURNS = 20;
const WORKFLOW_CONFIG_FILE = "workflow.json";
const EXPERIMENT_MAX_LINES = 20;
const EXPERIMENT_TIMEOUT_SECONDS = 600;
const HOOK_TIMEOUT_MS = 30_000;
const HOOK_STDOUT_MAX_BYTES = 8 * 1024;

type AutoRuntime = {
	turns: number;
	timer: ReturnType<typeof setTimeout> | null;
	lastWorkflowId?: string;
};

type WorkflowConfig = Record<string, unknown> & {
	maxAutoTurns?: number;
};

const DEFAULT_WORKFLOW_CONFIG: WorkflowConfig = {
	maxAutoTurns: DEFAULT_MAX_AUTO_TURNS,
};

const autoRuntimes = new Map<string, AutoRuntime>();
const lastExperimentBySession = new Map<string, { command: string; durationSeconds: number; exitCode: number | null; passed: boolean; output: string; parsedMetrics: Record<string, number> | null; checksPass: boolean | null; checksOutput: string; checksDuration: number }>();
let dashboardServer: Server | null = null;
let dashboardUrl: string | null = null;
const dashboardExpandedSessions = new Set<string>();
const WORKFLOW_STATUS_KEY = "workflow-core";
const STATUS_BG_BASE = "#111111";
const STATUS_BG_OPACITY = 0.2;

function parseHexColor(hex: string): { r: number; g: number; b: number } {
	const clean = hex.replace(/^#/, "");
	return {
		r: Number.parseInt(clean.slice(0, 2), 16),
		g: Number.parseInt(clean.slice(2, 4), 16),
		b: Number.parseInt(clean.slice(4, 6), 16),
	};
}

function blendHex(foreground: string, background = STATUS_BG_BASE, alpha = STATUS_BG_OPACITY): { r: number; g: number; b: number } {
	const fg = parseHexColor(foreground);
	const bg = parseHexColor(background);
	return {
		r: Math.round(fg.r * alpha + bg.r * (1 - alpha)),
		g: Math.round(fg.g * alpha + bg.g * (1 - alpha)),
		b: Math.round(fg.b * alpha + bg.b * (1 - alpha)),
	};
}

function workflowStatusLabel(workflow: WorkflowRecord): string {
	const label = workflowStatusLineSpec(workflow)?.label ?? workflow.controller;
	if (workflow.status === "active") return label;
	if (workflow.status === "waiting_for_user") return `${label}?`;
	if (workflow.status === "budget_limited") return `${label} limit`;
	if (workflow.status === "complete") return `${label} done`;
	return `${label} ${workflow.status}`;
}

function ansiWorkflowBadge(workflow: WorkflowRecord): string | undefined {
	const spec = workflowStatusLineSpec(workflow);
	if (!spec) return undefined;
	const bg = blendHex(spec.color);
	const bump = workflow.events.length % 2 === 0 ? spec.symbol : "●";
	const label = workflowStatusLabel(workflow);
	return `\x1b[38;2;255;255;255m\x1b[48;2;${bg.r};${bg.g};${bg.b}m ${bump} ${label} \x1b[39m\x1b[49m`;
}

function bumpWorkflowStatusLine(ctx: ExtensionContext | ExtensionCommandContext) {
	if (!ctx.hasUI) return;
	const workflow = currentWorkflowForStatusLine(ctx);
	ctx.ui.setStatus(WORKFLOW_STATUS_KEY, workflow ? ansiWorkflowBadge(workflow) : undefined);
}

function runtimeFor(ctx: ExtensionContext): AutoRuntime {
	const key = ctx.sessionManager.getSessionId();
	let runtime = autoRuntimes.get(key);
	if (!runtime) {
		runtime = { turns: 0, timer: null };
		autoRuntimes.set(key, runtime);
	}
	return runtime;
}

function positiveNumber(value: unknown): number | undefined {
	const number = Number(value);
	return Number.isFinite(number) && number > 0 ? Math.trunc(number) : undefined;
}

function workflowConfig(cwd: string): WorkflowConfig {
	return loadExtensionConfig<WorkflowConfig>(WORKFLOW_CONFIG_FILE, cwd, DEFAULT_WORKFLOW_CONFIG).config;
}

function maxAutoTurns(cwd: string): number {
	const envOverride = positiveNumber(process.env.PI_WORKFLOW_MAX_AUTO_TURNS);
	return envOverride ?? positiveNumber(workflowConfig(cwd).maxAutoTurns) ?? DEFAULT_MAX_AUTO_TURNS;
}

function ensureToolsActive(pi: ExtensionAPI, names: string[]) {
	const active = new Set(pi.getActiveTools?.() ?? []);
	let changed = false;
	for (const name of names) {
		if (!active.has(name)) {
			active.add(name);
			changed = true;
		}
	}
	if (changed) pi.setActiveTools?.([...active]);
}

function ensureWorkflowToolsActive(pi: ExtensionAPI) {
	ensureToolsActive(pi, WORKFLOW_TOOL_NAMES);
}

function ensureAutoresearchToolsActive(pi: ExtensionAPI) {
	ensureToolsActive(pi, [...WORKFLOW_TOOL_NAMES, ...AUTORESEARCH_TOOL_NAMES]);
}

function eventToWorkflow(event: WorkflowEvent): WorkflowRecord {
	const payload = event.payload;
	const title = typeof payload.title === "string" ? payload.title : event.controller;
	const objective = typeof payload.objective === "string" ? payload.objective : title;
	const status = isWorkflowStatus(payload.status) ? payload.status : "active";
	const data = payload.data && typeof payload.data === "object" && !Array.isArray(payload.data) ? payload.data : {};
	return {
		id: event.workflowId,
		controller: event.controller,
		title,
		objective,
		status,
		createdAt: event.timestamp,
		updatedAt: event.timestamp,
		data: data as Record<string, unknown>,
		events: [event],
	};
}

function oneLine(text: string, max = 72): string {
	const compact = text.replace(/\s+/g, " ").trim();
	return compact.length <= max ? compact : `${compact.slice(0, max - 1)}…`;
}

async function showText(ctx: ExtensionCommandContext, title: string, text: string) {
	if (!ctx.hasUI) {
		console.log(text);
		return;
	}
	await ctx.ui.editor(title, text);
}

function statusText(ctx: ExtensionContext | ExtensionCommandContext, controller: WorkflowController): string {
	const active = activeWorkflow(ctx, controller.name);
	const latest = latestWorkflow(ctx, controller.name);
	if (active) return controller.renderStatus?.(active) ?? renderWorkflowSummary(active);
	if (latest) return `${controller.renderStatus?.(latest) ?? renderWorkflowSummary(latest)}\n\nNo active ${controller.name}.`;
	return `No ${controller.name} workflow recorded on this session branch.`;
}

function workflowByIdOrActive(ctx: ExtensionContext, workflowId?: string): WorkflowRecord | undefined {
	if (workflowId) return workflows(ctx).find((workflow) => workflow.id === workflowId);
	return activeWorkflow(ctx);
}

function workflowForController(ctx: ExtensionContext, controller: string, workflowId?: string): WorkflowRecord | undefined {
	if (workflowId) return workflows(ctx).find((workflow) => workflow.id === workflowId && workflow.controller === controller);
	return activeWorkflow(ctx, controller) ?? latestWorkflow(ctx, controller);
}

function workflowStatusFromTool(value: unknown): "active" | "paused" | "waiting_for_user" | "budget_limited" | "complete" | "failed" | undefined {
	return value === "active" ||
		value === "paused" ||
		value === "waiting_for_user" ||
		value === "budget_limited" ||
		value === "complete" ||
		value === "failed"
		? value
		: undefined;
}

function stopStatusFromTool(value: unknown): "paused" | "complete" | "failed" | "budget_limited" {
	if (value === "complete" || value === "failed" || value === "budget_limited") return value;
	return "paused";
}

function updateControllerWorkflow(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	controller: "goal" | "review" | "autoresearch",
	workflowId: string | undefined,
	payload: Record<string, unknown>,
): { ok: true; workflow: WorkflowRecord; payload: Record<string, unknown> } | { ok: false; message: string } {
	const workflow = workflowForController(ctx, controller, workflowId);
	if (!workflow || workflow.status === "cleared") return { ok: false, message: `No ${controller} workflow found.` };
	if (Object.keys(payload).length === 0) return { ok: false, message: "No update fields supplied." };
	updateWorkflow(pi, workflow, payload);
	return { ok: true, workflow, payload };
}

function clearControllerWorkflow(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	controller: "goal" | "review" | "autoresearch",
	workflowId?: string,
	reason?: string,
): { ok: true; workflow: WorkflowRecord } | { ok: false; message: string } {
	const workflow = workflowForController(ctx, controller, workflowId);
	if (!workflow || workflow.status === "cleared") return { ok: false, message: `No ${controller} workflow found.` };
	clearWorkflow(pi, workflow, reason || `Cleared by ${controller} tool.`);
	return { ok: true, workflow };
}

function isLive(workflow: WorkflowRecord): boolean {
	return !["complete", "failed", "cleared"].includes(workflow.status);
}

function pauseOtherActiveWorkflows(pi: ExtensionAPI, ctx: ExtensionContext, controller: string, reason: string) {
	for (const workflow of workflows(ctx).filter((item) => isLive(item) && item.controller !== controller)) {
		changeWorkflowStatus(pi, workflow, "paused", reason);
	}
}

async function execText(pi: ExtensionAPI, cwd: string, command: string, timeout = 10_000): Promise<string | undefined> {
	try {
		const result = await pi.exec("bash", ["-lc", command], { cwd, timeout });
		if (result.code !== 0) return undefined;
		return (result.stdout || result.stderr || "").trim();
	} catch {
		return undefined;
	}
}

function tailLines(text: string, maxLines = EXPERIMENT_MAX_LINES): string {
	const lines = text.split("\n");
	return lines.length <= maxLines ? text : lines.slice(-maxLines).join("\n");
}

function parseMetricLines(output: string): Record<string, number> | null {
	const metrics: Record<string, number> = {};
	const regex = /^METRIC\s+([\w.µ-]+)=(\S+)\s*$/gm;
	let match: RegExpExecArray | null;
	while ((match = regex.exec(output)) !== null) {
		const value = Number(match[2]);
		if (Number.isFinite(value)) metrics[match[1]] = value;
	}
	return Object.keys(metrics).length ? metrics : null;
}

type AutoresearchConfig = {
	workingDir?: string;
	maxIterations?: number;
	maxWallClockSeconds?: number;
	maxExperimentSeconds?: number;
	maxConsecutiveFailures?: number;
	maxConsecutiveDiscards?: number;
	maxConsecutiveCrashes?: number;
	maxCommandRepeats?: number;
	requirePreflight?: boolean;
};

function positiveInteger(value: unknown): number | undefined {
	return typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.trunc(value) : undefined;
}

function autoresearchConfig(cwd: string): AutoresearchConfig {
	const configPath = join(cwd, "autoresearch.config.json");
	if (!existsSync(configPath)) return {};
	try {
		const parsed = JSON.parse(readFileSync(configPath, "utf8")) as Record<string, unknown>;
		const maxWallClockSeconds = positiveInteger(parsed.maxWallClockSeconds) ?? (positiveInteger(parsed.maxWallClockMinutes) ? positiveInteger(parsed.maxWallClockMinutes)! * 60 : undefined);
		return {
			workingDir: typeof parsed.workingDir === "string" && parsed.workingDir.trim() ? parsed.workingDir.trim() : undefined,
			maxIterations: positiveInteger(parsed.maxIterations),
			maxWallClockSeconds,
			maxExperimentSeconds: positiveInteger(parsed.maxExperimentSeconds),
			maxConsecutiveFailures: positiveInteger(parsed.maxConsecutiveFailures),
			maxConsecutiveDiscards: positiveInteger(parsed.maxConsecutiveDiscards),
			maxConsecutiveCrashes: positiveInteger(parsed.maxConsecutiveCrashes),
			maxCommandRepeats: positiveInteger(parsed.maxCommandRepeats),
			requirePreflight: parsed.requirePreflight === true,
		};
	} catch {
		return {};
	}
}

function autoresearchWorkDir(cwd: string): string {
	const configured = autoresearchConfig(cwd).workingDir;
	if (!configured) return cwd;
	return configured.startsWith("/") ? configured : join(cwd, configured);
}

function autoresearchJsonlPath(cwd: string): string {
	return join(autoresearchWorkDir(cwd), "autoresearch.jsonl");
}

function autoresearchScriptPath(cwd: string): string {
	return join(autoresearchWorkDir(cwd), "autoresearch.sh");
}

function autoresearchChecksPath(cwd: string): string {
	return join(autoresearchWorkDir(cwd), "autoresearch.checks.sh");
}

function autoresearchPreflightPath(cwd: string): string {
	return join(autoresearchWorkDir(cwd), "autoresearch.preflight.sh");
}

function isAutoresearchScriptCommand(command: string): boolean {
	const cmd = command.trim();
	return /^(?:(?:bash|sh|source)\s+(?:-\w+\s+)*)?(?:\.\/|\/?[\w/.-]*\/)?autoresearch\.sh(?:\s|$)/.test(cmd);
}

function appendAutoresearchEntry(cwd: string, entry: Record<string, unknown>) {
	appendFileSync(autoresearchJsonlPath(cwd), `${JSON.stringify({ ...entry, timestamp: new Date().toISOString() })}\n`, "utf8");
}

function readAutoresearchEntries(cwd: string): Record<string, unknown>[] {
	const file = autoresearchJsonlPath(cwd);
	if (!existsSync(file)) return [];
	return readFileSync(file, "utf8")
		.split("\n")
		.filter(Boolean)
		.map((line) => {
			try {
				return JSON.parse(line) as Record<string, unknown>;
			} catch {
				return { type: "parse_error", raw: line };
			}
		});
}

function bestMetricFromEntries(entries: Record<string, unknown>[], direction: "lower" | "higher"): number | undefined {
	const kept = entries
		.filter((entry) => entry.type === "run" && entry.status === "keep" && typeof entry.metric === "number")
		.map((entry) => entry.metric as number);
	if (!kept.length) return undefined;
	return direction === "lower" ? Math.min(...kept) : Math.max(...kept);
}

function isBetterMetric(value: number, baseline: number, direction: "lower" | "higher"): boolean {
	return direction === "lower" ? value < baseline : value > baseline;
}

function autoresearchSummary(cwd: string) {
	const entries = readAutoresearchEntries(cwd);
	const config = [...entries].reverse().find((entry) => entry.type === "config") ?? {};
	const runs = entries.filter((entry) => entry.type === "run");
	const direction = config.direction === "higher" ? "higher" : "lower";
	const metricName = typeof config.metric_name === "string" ? config.metric_name : typeof config.metricName === "string" ? config.metricName : "metric";
	const metricUnit = typeof config.metric_unit === "string" ? config.metric_unit : typeof config.metricUnit === "string" ? config.metricUnit : "";
	const name = typeof config.name === "string" ? config.name : undefined;
	const baseline = typeof runs[0]?.metric === "number" ? (runs[0].metric as number) : undefined;
	const kept = runs.filter((entry) => entry.status === "keep");
	const crashed = runs.filter((entry) => entry.status === "crash").length;
	const checksFailed = runs.filter((entry) => entry.status === "checks_failed").length;
	const best = bestMetricFromEntries(entries, direction);
	return { entries, runs, direction, metricName, metricUnit, name, baseline, kept: kept.length, crashed, checksFailed, best };
}

function median(values: number[]): number | null {
	if (!values.length) return null;
	const sorted = [...values].sort((a, b) => a - b);
	const mid = Math.floor(sorted.length / 2);
	return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function confidenceScore(values: number[], baseline: number | undefined, best: number | undefined): number | null {
	if (baseline === undefined || best === undefined || values.length < 3) return null;
	const med = median(values);
	if (med === null) return null;
	const mad = median(values.map((value) => Math.abs(value - med)));
	if (!mad || mad <= 0) return null;
	return Math.abs(best - baseline) / mad;
}

function formatMetric(value: number | undefined, unit: string): string {
	if (value === undefined) return "n/a";
	const formatted = Number.isInteger(value) ? value.toLocaleString() : value.toFixed(Math.abs(value) < 10 ? 4 : 2);
	return unit ? `${formatted}${unit}` : formatted;
}

function autoresearchMarkdown(cwd: string): string {
	const summary = autoresearchSummary(cwd);
	const values = summary.runs.map((run) => (typeof run.metric === "number" ? run.metric : Number.NaN)).filter(Number.isFinite);
	const conf = confidenceScore(values, summary.baseline, summary.best);
	const rows = summary.runs
		.map((run, index) => `| ${index + 1} | ${String(run.status ?? "")} | ${formatMetric(typeof run.metric === "number" ? run.metric : undefined, summary.metricUnit)} | ${String(run.description ?? "").replace(/\|/g, "\\|")} | ${String(run.command ?? "").replace(/\|/g, "\\|")} |`)
		.join("\n");
	return [`# Autoresearch${summary.name ? `: ${summary.name}` : ""}`, "", `- Runs: ${summary.runs.length}`, `- Kept: ${summary.kept}`, `- Crashes: ${summary.crashed}`, `- Checks failed: ${summary.checksFailed}`, `- Primary metric: ${summary.metricName} (${summary.metricUnit || "unitless"}, ${summary.direction} is better)`, `- Baseline: ${formatMetric(summary.baseline, summary.metricUnit)}`, `- Best: ${formatMetric(summary.best, summary.metricUnit)}`, `- Confidence: ${conf === null ? "n/a" : `${conf.toFixed(1)}×`}`, "", "| # | Status | Metric | Description | Command |", "| --- | --- | ---: | --- | --- |", rows || "| - | - | - | No runs yet | - |"].join("\n");
}

function renderAutoresearchWidget(ctx: ExtensionContext) {
	if (!ctx.hasUI) return;
	const workflow = activeWorkflow(ctx, "autoresearch");
	const summary = autoresearchSummary(ctx.cwd);
	if (!workflow && summary.runs.length === 0) {
		ctx.ui.setWidget("autoresearch", undefined);
		return;
	}
	ctx.ui.setWidget("autoresearch", () => ({
		render(width: number): string[] {
			const best = summary.best ?? summary.baseline;
			const values = summary.runs.map((run) => (typeof run.metric === "number" ? run.metric : Number.NaN)).filter(Number.isFinite);
			const conf = confidenceScore(values, summary.baseline, summary.best);
			let delta = "";
			if (summary.baseline !== undefined && summary.best !== undefined && summary.baseline !== 0 && summary.best !== summary.baseline) {
				const pct = ((summary.best - summary.baseline) / summary.baseline) * 100;
				const sign = pct > 0 ? "+" : "";
				delta = ` (${sign}${pct.toFixed(1)}%)`;
			}
			const status = workflow ? ` │ ${workflow.status}` : "";
			const failures = `${summary.crashed ? ` ${summary.crashed}💥` : ""}${summary.checksFailed ? ` ${summary.checksFailed}⚠` : ""}`;
			const text = `🔬 autoresearch ${summary.runs.length} runs ${summary.kept} kept${failures} │ ★ ${summary.metricName}: ${formatMetric(best, summary.metricUnit)}${delta}${conf === null ? "" : ` │ conf: ${conf.toFixed(1)}×`}${status}${summary.name ? ` │ ${summary.name}` : ""}`;
			if (!dashboardExpandedSessions.has(ctx.sessionManager.getSessionId())) return [text.length > width && width > 1 ? `${text.slice(0, width - 1)}…` : text];
			const table = summary.runs.slice(-6).map((run, index) => `#${summary.runs.length - Math.min(summary.runs.length, 6) + index + 1} ${String(run.status ?? "").padEnd(13)} ${formatMetric(typeof run.metric === "number" ? run.metric : undefined, summary.metricUnit).padStart(10)}  ${String(run.description ?? "").slice(0, Math.max(10, width - 34))}`);
			return [text.length > width && width > 1 ? `${text.slice(0, width - 1)}…` : text, ...table];
		},
		invalidate() {},
	}));
}

function hookScriptPath(cwd: string, stage: "before" | "after"): string {
	return join(autoresearchWorkDir(cwd), "autoresearch.hooks", `${stage}.sh`);
}

function isExecutableFile(filePath: string): boolean {
	try {
		accessSync(filePath, constants.X_OK);
		return statSync(filePath).isFile();
	} catch {
		return false;
	}
}

async function runAutoresearchHook(cwd: string, stage: "before" | "after", payload: Record<string, unknown>): Promise<{ fired: boolean; stdout: string; stderr: string; exitCode: number | null; timedOut: boolean; durationMs: number }> {
	const script = hookScriptPath(cwd, stage);
	if (!isExecutableFile(script)) return { fired: false, stdout: "", stderr: "", exitCode: null, timedOut: false, durationMs: 0 };
	const started = Date.now();
	return new Promise((resolve) => {
		const child = spawn("bash", [script], { cwd: autoresearchWorkDir(cwd), timeout: HOOK_TIMEOUT_MS });
		let stdout = "";
		let stderr = "";
		child.stdout.on("data", (chunk: Buffer) => {
			if (Buffer.byteLength(stdout, "utf8") < HOOK_STDOUT_MAX_BYTES) stdout += chunk.toString("utf8");
		});
		child.stderr.on("data", (chunk: Buffer) => (stderr += chunk.toString("utf8")));
		const finish = (exitCode: number | null, extra = "") =>
			resolve({ fired: true, stdout: stdout.slice(0, HOOK_STDOUT_MAX_BYTES), stderr: extra ? `${stderr}\n${extra}`.trim() : stderr, exitCode, timedOut: child.killed, durationMs: Date.now() - started });
		child.on("error", (error) => finish(null, error.message));
		child.on("close", (code) => finish(code));
		child.stdin.write(JSON.stringify({ ...payload, event: stage, cwd: autoresearchWorkDir(cwd) }));
		child.stdin.end();
	});
}

function hookSteer(stage: "before" | "after", result: { fired: boolean; stdout: string; stderr: string; exitCode: number | null; timedOut: boolean }): string | null {
	if (!result.fired) return null;
	if (result.timedOut) return `[${stage} hook timed out after ${HOOK_TIMEOUT_MS / 1000}s]`;
	if (result.exitCode !== 0) return [`[${stage} hook exited ${result.exitCode}]`, result.stderr.trim(), result.stdout.trim()].filter(Boolean).join("\n");
	return result.stdout.trim() || null;
}

function appendHookEntry(cwd: string, stage: "before" | "after", result: { fired: boolean; exitCode: number | null; durationMs: number; stdout: string; timedOut: boolean }) {
	if (!result.fired) return;
	appendAutoresearchEntry(cwd, { type: "hook", stage, exit_code: result.exitCode, duration_ms: result.durationMs, stdout_bytes: Buffer.byteLength(result.stdout, "utf8"), timed_out: result.timedOut });
}

function autoresearchSessionSnapshot(cwd: string, workflow?: WorkflowRecord) {
	const summary = autoresearchSummary(cwd);
	return {
		metric_name: summary.metricName,
		metric_unit: summary.metricUnit,
		direction: summary.direction,
		baseline_metric: summary.baseline ?? null,
		best_metric: summary.best ?? null,
		run_count: summary.runs.length,
		goal: workflow?.objective ?? summary.name ?? "",
	};
}

function lastAutoresearchRun(cwd: string): Record<string, unknown> | null {
	return [...readAutoresearchEntries(cwd)].reverse().find((entry) => entry.type === "run") ?? null;
}

function latestAutoresearchConfigEntry(entries: Record<string, unknown>[]): Record<string, unknown> | undefined {
	return [...entries].reverse().find((entry) => entry.type === "config");
}

function timestampMs(entry: Record<string, unknown> | undefined): number | undefined {
	const raw = entry?.timestamp;
	if (typeof raw !== "string") return undefined;
	const value = Date.parse(raw);
	return Number.isFinite(value) ? value : undefined;
}

function tailRunCount(entries: Record<string, unknown>[], predicate: (run: Record<string, unknown>) => boolean): number {
	let count = 0;
	for (const entry of [...entries].reverse()) {
		if (entry.type !== "run") continue;
		if (!predicate(entry)) break;
		count++;
	}
	return count;
}

function hasSuccessfulPreflight(entries: Record<string, unknown>[]): boolean {
	return entries.some((entry) => entry.type === "preflight" && entry.passed === true);
}

function commandRepeatCount(entries: Record<string, unknown>[], command: string): number {
	const normalized = command.trim();
	let count = 0;
	for (const entry of [...entries].reverse()) {
		if (entry.type !== "run") continue;
		if (String(entry.command ?? "").trim() !== normalized) break;
		count++;
	}
	return count;
}

function autoresearchBudgetViolation(cwd: string, timeoutSeconds?: number): string | null {
	const config = autoresearchConfig(cwd);
	const entries = readAutoresearchEntries(cwd);
	const runs = entries.filter((entry) => entry.type === "run");
	if (config.maxIterations && runs.length >= config.maxIterations) return `Maximum experiments reached (${config.maxIterations}).`;
	if (config.maxExperimentSeconds && timeoutSeconds && timeoutSeconds > config.maxExperimentSeconds) return `Requested experiment timeout ${timeoutSeconds}s exceeds maxExperimentSeconds ${config.maxExperimentSeconds}s.`;
	if (config.requirePreflight && !hasSuccessfulPreflight(entries)) return "requirePreflight is true but no successful preflight has been logged. Run run_preflight first.";
	const startedAt = timestampMs(latestAutoresearchConfigEntry(entries)) ?? timestampMs(entries[0]);
	if (config.maxWallClockSeconds && startedAt && Date.now() - startedAt >= config.maxWallClockSeconds * 1000) return `Wall-clock budget reached (${config.maxWallClockSeconds}s).`;
	if (config.maxConsecutiveFailures && tailRunCount(entries, (run) => run.status !== "keep") >= config.maxConsecutiveFailures) return `Consecutive non-keep budget reached (${config.maxConsecutiveFailures}).`;
	if (config.maxConsecutiveDiscards && tailRunCount(entries, (run) => run.status === "discard") >= config.maxConsecutiveDiscards) return `Consecutive discard budget reached (${config.maxConsecutiveDiscards}).`;
	if (config.maxConsecutiveCrashes && tailRunCount(entries, (run) => run.status === "crash" || run.status === "checks_failed") >= config.maxConsecutiveCrashes) return `Consecutive crash/check failure budget reached (${config.maxConsecutiveCrashes}).`;
	return null;
}

function normalizedTextSignal(value: unknown): string {
	return String(value ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim();
}

function asiText(entry: Record<string, unknown>, key: string): string {
	const asi = entry.asi && typeof entry.asi === "object" && !Array.isArray(entry.asi) ? (entry.asi as Record<string, unknown>) : undefined;
	return normalizedTextSignal(asi?.[key]);
}

function detectAutoresearchThrash(entries: Record<string, unknown>[], window = 3): string | null {
	const runs = entries.filter((entry) => entry.type === "run").slice(-window);
	if (runs.length < window) return null;
	if (runs.every((run) => run.status !== "keep")) return `${window} consecutive runs produced no kept improvement; stop retrying the same approach and choose a structurally different hypothesis.`;
	const descriptions = runs.map((run) => normalizedTextSignal(run.description)).filter(Boolean);
	if (descriptions.length === window && new Set(descriptions).size === 1) return `Repeated the same experiment description ${window} times: "${descriptions[0]}".`;
	const hypotheses = runs.map((run) => asiText(run, "hypothesis")).filter(Boolean);
	if (hypotheses.length === window && new Set(hypotheses).size === 1) return `Repeated the same ASI hypothesis ${window} times: "${hypotheses[0]}".`;
	return null;
}

function extractAssistantTextFromJsonMode(output: string): string | null {
	let latest = "";
	for (const line of output.split("\n")) {
		if (!line.trim()) continue;
		try {
			const event = JSON.parse(line) as { type?: string; message?: { role?: string; content?: Array<{ type?: string; text?: string }> } };
			if (event.type !== "message_end" || event.message?.role !== "assistant") continue;
			const text = (event.message.content ?? []).filter((block) => block.type === "text" && typeof block.text === "string").map((block) => block.text).join("\n").trim();
			if (text) latest = text;
		} catch {
			// Ignore non-JSON lines from child process startup or warnings.
		}
	}
	return latest || null;
}

function htmlEscape(value: unknown): string {
	return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!);
}

function dashboardHtml(cwd: string): string {
	const summary = autoresearchSummary(cwd);
	const values = summary.runs.map((run) => (typeof run.metric === "number" ? run.metric : Number.NaN)).filter(Number.isFinite);
	const conf = confidenceScore(values, summary.baseline, summary.best);
	const rows = summary.runs.map((run, index) => `<tr class="${htmlEscape(run.status)}"><td>${index + 1}</td><td>${htmlEscape(run.status)}</td><td>${htmlEscape(formatMetric(typeof run.metric === "number" ? run.metric : undefined, summary.metricUnit))}</td><td>${htmlEscape(run.description)}</td><td><code>${htmlEscape(run.command)}</code></td></tr>`).join("\n");
	return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="3"><title>Autoresearch</title><style>body{font-family:ui-sans-serif,system-ui;margin:24px;background:#111;color:#eee}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #333;padding:6px;text-align:left;vertical-align:top}th{color:#aaa}.best,.keep{color:#7ee787}.discard{color:#d29922}.crash,.checks_failed{color:#ff7b72}code{color:#a5d6ff}</style></head><body><h1>🔬 Autoresearch${summary.name ? `: ${htmlEscape(summary.name)}` : ""}</h1><p>${summary.runs.length} runs, ${summary.kept} kept, ${summary.crashed} crashes, ${summary.checksFailed} checks failed<br>best <span class="best">${htmlEscape(summary.metricName)}: ${htmlEscape(formatMetric(summary.best ?? summary.baseline, summary.metricUnit))}</span>${conf === null ? "" : ` · confidence ${conf.toFixed(1)}×`}</p><table><thead><tr><th>#</th><th>Status</th><th>${htmlEscape(summary.metricName)}</th><th>Description</th><th>Command</th></tr></thead><tbody>${rows}</tbody></table></body></html>`;
}

async function exportAutoresearchDashboard(pi: ExtensionAPI, ctx: ExtensionCommandContext) {
	if (dashboardServer) dashboardServer.close();
	dashboardServer = createServer((_req, res) => {
		res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
		res.end(dashboardHtml(ctx.cwd));
	});
	await new Promise<void>((resolve) => dashboardServer!.listen(0, "127.0.0.1", resolve));
	dashboardServer.unref();
	const address = dashboardServer.address();
	const port = typeof address === "object" && address ? address.port : 0;
	dashboardUrl = `http://127.0.0.1:${port}/`;
	if (ctx.hasUI) ctx.ui.notify(`Autoresearch dashboard: ${dashboardUrl}`, "info");
	else console.log(dashboardUrl);
	await pi.exec("bash", ["-lc", `open ${JSON.stringify(dashboardUrl)} 2>/dev/null || true`], { cwd: ctx.cwd, timeout: 5_000 }).catch(() => undefined);
}

function autoresearchCompactionSummary(cwd: string): string {
	const workDir = autoresearchWorkDir(cwd);
	const files = ["autoresearch.md", "autoresearch.ideas.md", "autoresearch.checks.sh"].map((name) => {
		const path = join(workDir, name);
		return existsSync(path) ? `\n## ${name}\n\n${readFileSync(path, "utf8").slice(-12_000)}` : "";
	}).join("\n");
	const summary = autoresearchMarkdown(cwd);
	return `Autoresearch workflow compaction summary. Use this as source-of-truth context after compaction, then continue the experiment loop from persisted files.\n\nWorking directory: ${workDir}\n\n${summary}\n${files}`;
}

function writeAutoresearchFinalize(cwd: string): string {
	const workDir = autoresearchWorkDir(cwd);
	const summary = autoresearchMarkdown(cwd);
	const kept = autoresearchSummary(cwd).runs.filter((run) => run.status === "keep");
	const path = join(workDir, "autoresearch.finalize.md");
	const body = [`# Autoresearch Finalize`, "", summary, "", "## Kept runs", "", ...kept.map((run, index) => `### Kept ${index + 1}: ${String(run.description ?? "") }\n\n- Metric: ${String(run.metric ?? "n/a")}\n- Command: ${String(run.command ?? "n/a")}\n- ASI: ${run.asi ? JSON.stringify(run.asi) : "n/a"}`), "", "## Next step", "", "Group kept runs into independent, reviewable changesets. Prefer one branch per logical change starting from the merge-base; groups should not share files."].join("\n");
	writeFileSync(path, body, "utf8");
	return path;
}

function registerWorkflowTools(pi: ExtensionAPI) {
	pi.registerTool({
		name: "create_goal",
		label: "Create Goal",
		description: "Create a durable main-session goal workflow that auto-continues until complete, paused, failed, cleared, or budget-limited.",
		promptSnippet: "Create a durable goal workflow from an objective",
		promptGuidelines: [
			"Use create_goal when the user asks to create, set, or start a durable goal, or asks you to make a prompt/objective to do a multi-step task.",
			"After create_goal returns, treat the returned workflow prompt as your active instructions and continue working in the same main workflow.",
		],
		parameters: Type.Object({
			objective: Type.String({ description: "The durable objective to pursue until complete." }),
			title: Type.Optional(Type.String({ description: "Short display title. Defaults to a shortened objective." })),
			initial_note: Type.Optional(Type.String({ description: "Optional note explaining why the goal was created or what to do first." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const objective = params.objective.trim();
			if (!objective) return { content: [{ type: "text", text: "Cannot create a goal with an empty objective." }], isError: true };
			pauseOtherActiveWorkflows(pi, ctx, "goal", `Paused because a goal workflow was created: ${objective}`);
			const existing = activeWorkflow(ctx, "goal");
			if (existing) changeWorkflowStatus(pi, existing, "paused", `Paused because a new goal was created: ${objective}`);
			const event = startWorkflow(pi, {
				controller: "goal",
				title: params.title?.trim() || oneLine(objective),
				objective,
				status: "active",
				data: params.initial_note ? { initialNote: params.initial_note.trim() } : {},
			});
			const workflow = eventToWorkflow(event);
			runtimeFor(ctx).turns = 0;
			ensureWorkflowToolsActive(pi);
			const prompt = goalController.renderStartPrompt(workflow);
			return {
				content: [{ type: "text", text: `Goal workflow created: ${workflow.id}\n\nFollow this workflow prompt now:\n\n${prompt}` }],
				details: { workflow, prompt },
			};
		},
	});

	pi.registerTool({
		name: "create_review",
		label: "Create Review",
		description: "Create a main-session review workflow for current changes, a base-branch diff, a commit, or custom review instructions.",
		promptSnippet: "Create a review workflow for code changes",
		promptGuidelines: [
			"Use create_review when the user asks to review code, inspect current changes, review a commit, or produce prioritized findings.",
			"After create_review returns, review the target in the main workflow; do not edit code unless the user asks to fix a finding.",
		],
		parameters: Type.Object({
			target: Type.Optional(Type.Union([Type.Literal("current"), Type.Literal("base"), Type.Literal("commit"), Type.Literal("custom")], { description: "Review target. Defaults to current changes." })),
			base: Type.Optional(Type.String({ description: "Base branch when target is base." })),
			commit: Type.Optional(Type.String({ description: "Commit SHA/ref when target is commit." })),
			instructions: Type.Optional(Type.String({ description: "Custom review instructions when target is custom, or extra reviewer guidance." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const target = params.target ?? (params.commit ? "commit" : params.base ? "base" : params.instructions ? "custom" : "current");
			const data: Record<string, unknown> = { target };
			let title = "review current changes";
			let objective = "Review current staged, unstaged, and untracked changes";
			if (target === "base") {
				const base = params.base?.trim() || "main";
				const mergeBase = await execText(pi, ctx.cwd, `git merge-base HEAD ${JSON.stringify(base)} 2>/dev/null`);
				Object.assign(data, { base, mergeBase });
				title = `review against ${base}`;
				objective = `Review changes against ${base}`;
			} else if (target === "commit") {
				const commit = params.commit?.trim() || "HEAD";
				Object.assign(data, { commit });
				title = `review commit ${commit}`;
				objective = `Review commit ${commit}`;
			} else if (target === "custom") {
				const instructions = params.instructions?.trim();
				if (!instructions) return { content: [{ type: "text", text: "Custom review requires instructions." }], isError: true };
				Object.assign(data, { instructions });
				title = oneLine(`review: ${instructions}`);
				objective = instructions;
			} else if (params.instructions?.trim()) {
				data.instructions = params.instructions.trim();
			}
			pauseOtherActiveWorkflows(pi, ctx, "review", `Paused because a review workflow was created: ${title}`);
			const existing = activeWorkflow(ctx, "review");
			if (existing) changeWorkflowStatus(pi, existing, "paused", `Paused because a new review was created: ${title}`);
			const event = startWorkflow(pi, { controller: "review", title, objective, status: "active", data });
			const workflow = eventToWorkflow(event);
			ensureWorkflowToolsActive(pi);
			const prompt = reviewController.renderStartPrompt(workflow);
			return {
				content: [{ type: "text", text: `Review workflow created: ${workflow.id}\n\nFollow this workflow prompt now:\n\n${prompt}` }],
				details: { workflow, prompt },
			};
		},
	});

	pi.registerTool({
		name: "create_autoresearch",
		label: "Create Autoresearch",
		description: "Create a main-session autoresearch workflow for measured optimisation experiments.",
		promptSnippet: "Create an autoresearch experiment workflow",
		promptGuidelines: [
			"Use create_autoresearch when the user asks to optimise through repeated measurement, benchmark experiments, or autonomous research loops.",
			"After create_autoresearch returns, initialize the experiment if needed, then run_experiment and log_experiment in the main workflow.",
		],
		parameters: Type.Object({
			objective: Type.String({ description: "Optimisation/research objective." }),
			metric_name: Type.Optional(Type.String({ description: "Known primary metric name, if already decided." })),
			metric_unit: Type.Optional(Type.String({ description: "Known metric unit, if any." })),
			direction: Type.Optional(Type.Union([Type.Literal("lower"), Type.Literal("higher")], { description: "Whether lower or higher is better." })),
			benchmark_hint: Type.Optional(Type.String({ description: "Known benchmark command or benchmark setup hint." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const objective = params.objective.trim();
			if (!objective) return { content: [{ type: "text", text: "Cannot create autoresearch with an empty objective." }], isError: true };
			pauseOtherActiveWorkflows(pi, ctx, "autoresearch", `Paused because autoresearch was created: ${objective}`);
			const existing = activeWorkflow(ctx, "autoresearch");
			if (existing) changeWorkflowStatus(pi, existing, "paused", `Paused because a new autoresearch workflow was created: ${objective}`);
			const data: Record<string, unknown> = { runCount: 0 };
			if (params.metric_name?.trim()) data.metricName = params.metric_name.trim();
			if (params.metric_unit?.trim()) data.metricUnit = params.metric_unit.trim();
			if (params.direction) data.direction = params.direction;
			if (params.benchmark_hint?.trim()) data.benchmarkHint = params.benchmark_hint.trim();
			const event = startWorkflow(pi, { controller: "autoresearch", title: oneLine(objective), objective, status: "active", data });
			const workflow = eventToWorkflow(event);
			runtimeFor(ctx).turns = 0;
			ensureAutoresearchToolsActive(pi);
			renderAutoresearchWidget(ctx);
			const prompt = autoresearchController.renderStartPrompt(workflow);
			return {
				content: [{ type: "text", text: `Autoresearch workflow created: ${workflow.id}\n\nFollow this workflow prompt now:\n\n${prompt}` }],
				details: { workflow, prompt },
			};
		},
	});


	pi.registerTool({
		name: "update_goal",
		label: "Update Goal",
		description: "Update the active durable goal workflow objective, status, note, or next action.",
		promptSnippet: "Update durable goal objective/status/progress",
		promptGuidelines: ["Use update_goal when the user's goal changes, when you need to record goal progress, or when the goal becomes complete/waiting/failed."],
		parameters: Type.Object({
			workflowId: Type.Optional(Type.String({ description: "Goal workflow id. Defaults to active/latest goal." })),
			objective: Type.Optional(Type.String({ description: "Updated goal objective." })),
			title: Type.Optional(Type.String({ description: "Updated display title." })),
			status: Type.Optional(Type.Union([Type.Literal("active"), Type.Literal("paused"), Type.Literal("waiting_for_user"), Type.Literal("budget_limited"), Type.Literal("complete"), Type.Literal("failed")])),
			note: Type.Optional(Type.String({ description: "Concise progress/completion note." })),
			nextAction: Type.Optional(Type.String({ description: "Next action if not complete." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const payload: Record<string, unknown> = {};
			if (params.objective?.trim()) {
				payload.objective = params.objective.trim();
				payload.title = params.title?.trim() || oneLine(params.objective);
			} else if (params.title?.trim()) payload.title = params.title.trim();
			const status = workflowStatusFromTool(params.status);
			if (status) payload.status = status;
			if (params.note?.trim()) payload.note = params.note.trim();
			if (params.nextAction?.trim()) payload.nextAction = params.nextAction.trim();
			const result = updateControllerWorkflow(pi, ctx, "goal", params.workflowId, payload);
			if (!result.ok) return { content: [{ type: "text", text: result.message }], isError: true };
			return { content: [{ type: "text", text: `Goal workflow updated: ${result.workflow.id}` }], details: result };
		},
	});

	pi.registerTool({
		name: "stop_goal",
		label: "Stop Goal",
		description: "Stop the active goal by pausing it by default, or marking it complete, failed, or budget-limited.",
		promptSnippet: "Pause/complete/fail/budget-limit a goal workflow",
		promptGuidelines: ["Use stop_goal when the user asks to stop, pause, finish, mark done, or abandon a goal. Default action is pause, not clear."],
		parameters: Type.Object({
			workflowId: Type.Optional(Type.String()),
			mode: Type.Optional(Type.Union([Type.Literal("pause"), Type.Literal("complete"), Type.Literal("failed"), Type.Literal("budget_limited")])),
			reason: Type.Optional(Type.String()),
			nextAction: Type.Optional(Type.String()),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const workflow = workflowForController(ctx, "goal", params.workflowId);
			if (!workflow || workflow.status === "cleared") return { content: [{ type: "text", text: "No goal workflow found." }], isError: true };
			const status = stopStatusFromTool(params.mode);
			changeWorkflowStatus(pi, workflow, status, params.reason?.trim() || `Goal ${status}.`, params.nextAction?.trim());
			return { content: [{ type: "text", text: `Goal workflow ${status}: ${workflow.id}` }], details: { workflowId: workflow.id, status } };
		},
	});

	pi.registerTool({
		name: "clear_goal",
		label: "Clear Goal",
		description: "Clear a goal workflow from the active branch state.",
		promptSnippet: "Clear a goal workflow",
		promptGuidelines: ["Use clear_goal only when the user explicitly asks to clear/remove the goal; otherwise use stop_goal to pause it."],
		parameters: Type.Object({ workflowId: Type.Optional(Type.String()), reason: Type.Optional(Type.String()) }),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const result = clearControllerWorkflow(pi, ctx, "goal", params.workflowId, params.reason?.trim());
			if (!result.ok) return { content: [{ type: "text", text: result.message }], isError: true };
			return { content: [{ type: "text", text: `Goal workflow cleared: ${result.workflow.id}` }], details: result };
		},
	});

	pi.registerTool({
		name: "update_review",
		label: "Update Review",
		description: "Update the active review workflow target, status, note, or next action.",
		promptSnippet: "Update review workflow state or target",
		promptGuidelines: ["Use update_review when review findings are ready, when code changed and review should run again, or when the review target/instructions change."],
		parameters: Type.Object({
			workflowId: Type.Optional(Type.String()),
			status: Type.Optional(Type.Union([Type.Literal("active"), Type.Literal("paused"), Type.Literal("waiting_for_user"), Type.Literal("budget_limited"), Type.Literal("complete"), Type.Literal("failed")])),
			note: Type.Optional(Type.String()),
			nextAction: Type.Optional(Type.String()),
			target: Type.Optional(Type.Union([Type.Literal("current"), Type.Literal("base"), Type.Literal("commit"), Type.Literal("custom")])),
			base: Type.Optional(Type.String()),
			commit: Type.Optional(Type.String()),
			instructions: Type.Optional(Type.String()),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const payload: Record<string, unknown> = {};
			const status = workflowStatusFromTool(params.status);
			if (status) payload.status = status;
			if (params.note?.trim()) payload.note = params.note.trim();
			if (params.nextAction?.trim()) payload.nextAction = params.nextAction.trim();
			const data: Record<string, unknown> = {};
			if (params.target) data.target = params.target;
			if (params.base?.trim()) data.base = params.base.trim();
			if (params.commit?.trim()) data.commit = params.commit.trim();
			if (params.instructions?.trim()) data.instructions = params.instructions.trim();
			if (Object.keys(data).length) payload.data = data;
			const result = updateControllerWorkflow(pi, ctx, "review", params.workflowId, payload);
			if (!result.ok) return { content: [{ type: "text", text: result.message }], isError: true };
			return { content: [{ type: "text", text: `Review workflow updated: ${result.workflow.id}` }], details: result };
		},
	});

	pi.registerTool({
		name: "stop_review",
		label: "Stop Review",
		description: "Stop the active review by pausing it by default, or marking it complete, failed, or budget-limited.",
		promptSnippet: "Pause/complete/fail/budget-limit a review workflow",
		promptGuidelines: ["Use stop_review when the user asks to stop/pause/end a review. Default action is pause, not clear."],
		parameters: Type.Object({
			workflowId: Type.Optional(Type.String()),
			mode: Type.Optional(Type.Union([Type.Literal("pause"), Type.Literal("complete"), Type.Literal("failed"), Type.Literal("budget_limited")])),
			reason: Type.Optional(Type.String()),
			nextAction: Type.Optional(Type.String()),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const workflow = workflowForController(ctx, "review", params.workflowId);
			if (!workflow || workflow.status === "cleared") return { content: [{ type: "text", text: "No review workflow found." }], isError: true };
			const status = stopStatusFromTool(params.mode);
			changeWorkflowStatus(pi, workflow, status, params.reason?.trim() || `Review ${status}.`, params.nextAction?.trim());
			return { content: [{ type: "text", text: `Review workflow ${status}: ${workflow.id}` }], details: { workflowId: workflow.id, status } };
		},
	});

	pi.registerTool({
		name: "clear_review",
		label: "Clear Review",
		description: "Clear a review workflow from the active branch state.",
		promptSnippet: "Clear a review workflow",
		promptGuidelines: ["Use clear_review only when the user explicitly asks to clear/remove the review workflow."],
		parameters: Type.Object({ workflowId: Type.Optional(Type.String()), reason: Type.Optional(Type.String()) }),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const result = clearControllerWorkflow(pi, ctx, "review", params.workflowId, params.reason?.trim());
			if (!result.ok) return { content: [{ type: "text", text: result.message }], isError: true };
			return { content: [{ type: "text", text: `Review workflow cleared: ${result.workflow.id}` }], details: result };
		},
	});

	pi.registerTool({
		name: "update_autoresearch",
		label: "Update Autoresearch",
		description: "Update the active autoresearch workflow objective, metric, status, note, or next action.",
		promptSnippet: "Update autoresearch workflow state/metric/objective",
		promptGuidelines: ["Use update_autoresearch when the experiment objective, metric, benchmark direction, progress note, or next action changes."],
		parameters: Type.Object({
			workflowId: Type.Optional(Type.String()),
			objective: Type.Optional(Type.String()),
			status: Type.Optional(Type.Union([Type.Literal("active"), Type.Literal("paused"), Type.Literal("waiting_for_user"), Type.Literal("budget_limited"), Type.Literal("complete"), Type.Literal("failed")])),
			note: Type.Optional(Type.String()),
			nextAction: Type.Optional(Type.String()),
			metric_name: Type.Optional(Type.String()),
			metric_unit: Type.Optional(Type.String()),
			direction: Type.Optional(Type.Union([Type.Literal("lower"), Type.Literal("higher")])),
			benchmark_hint: Type.Optional(Type.String()),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const payload: Record<string, unknown> = {};
			if (params.objective?.trim()) {
				payload.objective = params.objective.trim();
				payload.title = oneLine(params.objective);
			}
			const status = workflowStatusFromTool(params.status);
			if (status) payload.status = status;
			if (params.note?.trim()) payload.note = params.note.trim();
			if (params.nextAction?.trim()) payload.nextAction = params.nextAction.trim();
			const data: Record<string, unknown> = {};
			if (params.metric_name?.trim()) data.metricName = params.metric_name.trim();
			if (params.metric_unit?.trim()) data.metricUnit = params.metric_unit.trim();
			if (params.direction) data.direction = params.direction;
			if (params.benchmark_hint?.trim()) data.benchmarkHint = params.benchmark_hint.trim();
			if (Object.keys(data).length) payload.data = data;
			const result = updateControllerWorkflow(pi, ctx, "autoresearch", params.workflowId, payload);
			if (!result.ok) return { content: [{ type: "text", text: result.message }], isError: true };
			return { content: [{ type: "text", text: `Autoresearch workflow updated: ${result.workflow.id}` }], details: result };
		},
	});

	pi.registerTool({
		name: "stop_autoresearch",
		label: "Stop Autoresearch",
		description: "Stop the active autoresearch loop by pausing it by default, or marking it complete, failed, or budget-limited.",
		promptSnippet: "Pause/complete/fail/budget-limit autoresearch",
		promptGuidelines: ["Use stop_autoresearch when the user asks to stop/pause/end autoresearch. Default action is pause, preserving logs and files."],
		parameters: Type.Object({
			workflowId: Type.Optional(Type.String()),
			mode: Type.Optional(Type.Union([Type.Literal("pause"), Type.Literal("complete"), Type.Literal("failed"), Type.Literal("budget_limited")])),
			reason: Type.Optional(Type.String()),
			nextAction: Type.Optional(Type.String()),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const workflow = workflowForController(ctx, "autoresearch", params.workflowId);
			if (!workflow || workflow.status === "cleared") return { content: [{ type: "text", text: "No autoresearch workflow found." }], isError: true };
			const status = stopStatusFromTool(params.mode);
			changeWorkflowStatus(pi, workflow, status, params.reason?.trim() || `Autoresearch ${status}.`, params.nextAction?.trim());
			return { content: [{ type: "text", text: `Autoresearch workflow ${status}: ${workflow.id}` }], details: { workflowId: workflow.id, status } };
		},
	});

	pi.registerTool({
		name: "clear_autoresearch",
		label: "Clear Autoresearch",
		description: "Clear an autoresearch workflow, optionally deleting autoresearch.jsonl.",
		promptSnippet: "Clear autoresearch workflow",
		promptGuidelines: ["Use clear_autoresearch only when the user explicitly asks to clear/remove autoresearch. Use stop_autoresearch to pause while preserving state."],
		parameters: Type.Object({ workflowId: Type.Optional(Type.String()), reason: Type.Optional(Type.String()), delete_jsonl: Type.Optional(Type.Boolean()) }),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const result = clearControllerWorkflow(pi, ctx, "autoresearch", params.workflowId, params.reason?.trim());
			if (!result.ok) return { content: [{ type: "text", text: result.message }], isError: true };
			if (params.delete_jsonl) {
				const jsonl = autoresearchJsonlPath(ctx.cwd);
				if (existsSync(jsonl)) unlinkSync(jsonl);
			}
			return { content: [{ type: "text", text: `Autoresearch workflow cleared: ${result.workflow.id}` }], details: { ...result, deletedJsonl: !!params.delete_jsonl } };
		},
	});
	pi.registerTool({
		name: "workflow_status",
		label: "Workflow Status",
		description: "Read the active Pi workflow state for the current session branch.",
		promptSnippet: "Read active workflow state and objective",
		promptGuidelines: [
			"Use workflow_status when a durable Pi workflow is active and you need to re-check its objective, status, or next action.",
		],
		parameters: Type.Object({
			controller: Type.Optional(Type.String({ description: "Optional controller filter, e.g. goal, review, autoresearch." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const controller = typeof params.controller === "string" && params.controller.trim() ? params.controller.trim() : undefined;
			const workflow = activeWorkflow(ctx, controller);
			const text = workflow ? renderWorkflowSummary(workflow) : "No active workflow.";
			return { content: [{ type: "text", text }], details: { workflow } };
		},
	});

	pi.registerTool({
		name: "workflow_update",
		label: "Workflow Update",
		description: "Record progress, waiting state, completion, or failure for the active Pi workflow.",
		promptSnippet: "Record durable workflow progress or completion",
		promptGuidelines: [
			"Use workflow_update to record meaningful progress for durable Pi workflows, especially when the workflow becomes waiting_for_user, complete, failed, or has a clear next action.",
			"Before using workflow_update with status complete, audit the actual state against the workflow objective and include concise evidence in note.",
		],
		parameters: Type.Object({
			workflowId: Type.Optional(Type.String({ description: "Workflow id. Defaults to the active workflow." })),
			status: Type.Optional(
				Type.Union([
					Type.Literal("active"),
					Type.Literal("paused"),
					Type.Literal("waiting_for_user"),
					Type.Literal("budget_limited"),
					Type.Literal("complete"),
					Type.Literal("failed"),
				]),
			),
			note: Type.Optional(Type.String({ description: "Concise progress note or completion evidence." })),
			nextAction: Type.Optional(Type.String({ description: "Recommended next action if the workflow is not complete." })),
			objective: Type.Optional(Type.String({ description: "Updated objective, only when the user changed the goal." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const workflow = workflowByIdOrActive(ctx, params.workflowId);
			if (!workflow) {
				return { content: [{ type: "text", text: "No active workflow to update." }], isError: true };
			}

			const payload: Record<string, unknown> = {};
			if (params.status && isWorkflowStatus(params.status)) payload.status = params.status;
			if (typeof params.note === "string") payload.note = params.note.trim();
			if (typeof params.nextAction === "string") payload.nextAction = params.nextAction.trim();
			if (typeof params.objective === "string" && params.objective.trim()) payload.objective = params.objective.trim();

			if (Object.keys(payload).length === 0) {
				return { content: [{ type: "text", text: "No workflow update fields supplied." }], isError: true };
			}

			updateWorkflow(pi, workflow, payload);
			return { content: [{ type: "text", text: `Workflow ${workflow.id} updated.` }], details: { workflowId: workflow.id, update: payload } };
		},
	});
}

function registerAutoresearchTools(pi: ExtensionAPI) {
	pi.registerTool({
		name: "finalize_autoresearch",
		label: "Finalize Autoresearch",
		description: "Write an autoresearch finalization report grouping kept runs for reviewable follow-up branches.",
		promptSnippet: "Finalize autoresearch into reviewable summary",
		promptGuidelines: ["Use finalize_autoresearch when the user asks to finalize, summarize, or prepare autoresearch results for review."],
		parameters: Type.Object({}),
		async execute(_toolCallId, _params, _signal, _onUpdate, ctx) {
			const path = writeAutoresearchFinalize(ctx.cwd);
			const content = readFileSync(path, "utf8");
			return { content: [{ type: "text", text: `Wrote ${path}\n\n${content}` }], details: { path } };
		},
	});

	pi.registerTool({ 
		name: "init_experiment",
		label: "Init Experiment",
		description: "Initialize an autoresearch experiment session and primary metric.",
		promptSnippet: "Initialize autoresearch metric/session before experiments",
		promptGuidelines: ["Call init_experiment once before the first run_experiment in an autoresearch workflow."],
		parameters: Type.Object({
			name: Type.String({ description: "Human-readable experiment session name." }),
			metric_name: Type.String({ description: "Primary metric name, matching METRIC name=value output when possible." }),
			metric_unit: Type.Optional(Type.String({ description: "Metric unit, e.g. ms, s, %, kb." })),
			direction: Type.Optional(Type.Union([Type.Literal("lower"), Type.Literal("higher")], { description: "Whether lower or higher is better." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const workflow = activeWorkflow(ctx, "autoresearch");
			if (!workflow) return { content: [{ type: "text", text: "No active autoresearch workflow." }], isError: true };
			const direction = params.direction === "higher" ? "higher" : "lower";
			const workDir = autoresearchWorkDir(ctx.cwd);
			const config = autoresearchConfig(ctx.cwd);
			const maxIterations = config.maxIterations;
			appendAutoresearchEntry(ctx.cwd, {
				type: "config",
				name: params.name,
				metric_name: params.metric_name,
				metric_unit: params.metric_unit ?? "",
				direction,
				workflowId: workflow.id,
				maxIterations,
				budget: {
					maxWallClockSeconds: config.maxWallClockSeconds,
					maxExperimentSeconds: config.maxExperimentSeconds,
					maxConsecutiveFailures: config.maxConsecutiveFailures,
					maxConsecutiveDiscards: config.maxConsecutiveDiscards,
					maxConsecutiveCrashes: config.maxConsecutiveCrashes,
					maxCommandRepeats: config.maxCommandRepeats,
					requirePreflight: config.requirePreflight,
				},
			});
			if (!existsSync(join(workDir, "autoresearch.md"))) {
				writeFileSync(
					join(workDir, "autoresearch.md"),
					`# Autoresearch: ${params.name}\n\n## Objective\n${workflow.objective}\n\n## Metrics\n- **Primary**: ${params.metric_name} (${params.metric_unit ?? "unitless"}, ${direction} is better)\n- **Secondary**: add independent tradeoff monitors as they become useful.\n\n## How to Run\n\`./autoresearch.sh\` — outputs \`METRIC name=number\` lines.\n\n## Preflight / Smoke\n- Optional: create \`autoresearch.preflight.sh\` for a cheap representative smoke test before expensive or batch experiments.\n\n## Files in Scope\nTBD — inspect and fill before broad edits.\n\n## Off Limits\nTBD.\n\n## Evidence / Recipes\n- Add current docs, examples, papers, issue links, benchmark sources, and any result-backed recipes worth trying.\n\n## Benchmark / Data Audit\n- Describe what the metric really measures, representative inputs, seeds/warmups/sample counts, noise risks, and known ways it could be gamed.\n\n## Resource Budget\n- Max iterations/time/cost/hardware/network limits and required approval gates: TBD.\n\n## Constraints\n- Do not overfit or cheat the benchmark.\n- Do not silently substitute datasets, models, workloads, dependencies, or task definitions.\n\n## What's Been Tried\n- Baseline pending.\n`,
					"utf8",
				);
			}
			updateWorkflow(pi, workflow, {
				status: "active",
				note: `Initialized experiment '${params.name}' with metric ${params.metric_name}.`,
				data: { name: params.name, metricName: params.metric_name, metricUnit: params.metric_unit ?? "", direction, runCount: 0, maxIterations, workingDir: workDir },
			});
			renderAutoresearchWidget(ctx);
			const limitNote = maxIterations ? ` Max iterations: ${maxIterations}.` : "";
			return { content: [{ type: "text", text: `Experiment initialized. Metric: ${params.metric_name} (${direction} is better). Working directory: ${workDir}.${limitNote}` }] };
		},
	});

	pi.registerTool({
		name: "research_probe",
		label: "Research Probe",
		description: "Spawn a throwaway pi --no-session scout for compact source-grounded research without polluting the main autoresearch context.",
		promptSnippet: "Run a throwaway read-only Pi scout for evidence gathering",
		promptGuidelines: [
			"Use research_probe during autoresearch when current docs, examples, prior art, papers, issue history, or broad codebase exploration would pollute the main context.",
			"research_probe launches pi --mode json -p --no-session with read/grep/find/ls/bash plus local research tools when available; treat its output as evidence to cite in autoresearch.md or ASI.",
		],
		parameters: Type.Object({
			task: Type.String({ description: "Focused research task for the throwaway scout." }),
			context: Type.Optional(Type.String({ description: "Optional concise context from the current autoresearch state." })),
			timeout_seconds: Type.Optional(Type.Number({ description: "Timeout in seconds. Default 180." })),
		}),
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const workflow = activeWorkflow(ctx, "autoresearch");
			if (!workflow) return { content: [{ type: "text", text: "No active autoresearch workflow." }], isError: true };
			const task = params.task.trim();
			if (!task) return { content: [{ type: "text", text: "research_probe requires a non-empty task." }], isError: true };
			const workDir = autoresearchWorkDir(ctx.cwd);
			const timeoutSeconds = Number.isFinite(params.timeout_seconds) && params.timeout_seconds > 0 ? Math.trunc(params.timeout_seconds) : 180;
			const childPrompt = [params.context?.trim() ? `Context: ${params.context.trim()}` : "", `Task: ${task}`].filter(Boolean).join("\n\n");
			onUpdate?.({ content: [{ type: "text", text: `Research probe: ${oneLine(task, 80)}` }] });
			const result = await pi.exec(
				"pi",
				[
					"--mode",
					"json",
					"-p",
					"--no-session",
					"--tools",
					"read,grep,find,ls,bash,websearch,webfetch,mcp_search,mcp_inspect",
					"--append-system-prompt",
					"You are a scout. Return compact findings only: answer, evidence paths/URLs, commands run, confidence, next action. Do not edit files. Use bash only for read-only inspection commands.",
					childPrompt,
				],
				{ cwd: workDir, timeout: timeoutSeconds * 1000, signal },
			);
			const rawOutput = `${result.stdout ?? ""}${result.stderr ? `\n${result.stderr}` : ""}`;
			const summary = extractAssistantTextFromJsonMode(rawOutput) ?? tailLines(rawOutput, 40);
			appendAutoresearchEntry(ctx.cwd, { type: "research_probe", task, exit_code: result.code, timed_out: !!result.killed, summary });
			return {
				content: [{ type: "text", text: [`Research probe: ${result.code === 0 && !result.killed ? "complete" : "ended with errors"}`, "", summary].join("\n") }],
				details: { task, exitCode: result.code, timedOut: !!result.killed, summary },
				isError: result.code !== 0 || !!result.killed,
			};
		},
	});

	pi.registerTool({
		name: "run_preflight",
		label: "Run Preflight",
		description: "Run a smoke/preflight command for an autoresearch session without counting it as a full experiment.",
		promptSnippet: "Run smoke/preflight checks before expensive or batch experiments",
		promptGuidelines: [
			"Use run_preflight before expensive, long-running, GPU/cloud, training, or batch autoresearch experiments.",
			"If autoresearch.preflight.sh exists, prefer run_preflight with no command so that script owns the smoke-test contract.",
		],
		parameters: Type.Object({
			command: Type.Optional(Type.String({ description: "Smoke/preflight command. Defaults to bash autoresearch.preflight.sh when that file exists." })),
			timeout_seconds: Type.Optional(Type.Number({ description: "Timeout in seconds. Default 300." })),
		}),
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const workflow = activeWorkflow(ctx, "autoresearch");
			if (!workflow) return { content: [{ type: "text", text: "No active autoresearch workflow." }], isError: true };
			const workDir = autoresearchWorkDir(ctx.cwd);
			const preflightPath = autoresearchPreflightPath(ctx.cwd);
			const command = params.command?.trim() || (existsSync(preflightPath) ? "bash autoresearch.preflight.sh" : "");
			if (!command) return { content: [{ type: "text", text: "No preflight command supplied and no autoresearch.preflight.sh exists." }], isError: true };
			const timeoutSeconds = Number.isFinite(params.timeout_seconds) && params.timeout_seconds > 0 ? Math.trunc(params.timeout_seconds) : 300;
			onUpdate?.({ content: [{ type: "text", text: `Preflight: ${command}` }] });
			const started = Date.now();
			const result = await pi.exec("bash", ["-lc", command], { cwd: workDir, timeout: timeoutSeconds * 1000, signal });
			const durationSeconds = (Date.now() - started) / 1000;
			const output = `${result.stdout ?? ""}${result.stderr ? `\n${result.stderr}` : ""}`;
			const parsedMetrics = parseMetricLines(output);
			const passed = result.code === 0 && !result.killed;
			appendAutoresearchEntry(ctx.cwd, { type: "preflight", command, duration_seconds: durationSeconds, exit_code: result.code, timed_out: !!result.killed, passed, parsed_metrics: parsedMetrics, output_tail: tailLines(output) });
			return {
				content: [{ type: "text", text: [`Preflight: ${passed ? "passed" : "failed"}`, `Command: ${command}`, `Duration: ${durationSeconds.toFixed(2)}s`, parsedMetrics ? `Parsed metrics: ${JSON.stringify(parsedMetrics)}` : "Parsed metrics: none", "", "Output tail:", tailLines(output)].join("\n") }],
				details: { command, durationSeconds, exitCode: result.code, passed, parsedMetrics, output },
				isError: !passed,
			};
		},
	});

	pi.registerTool({
		name: "run_experiment",
		label: "Run Experiment",
		description: "Run a shell command as an autoresearch experiment, time it, and parse METRIC lines.",
		promptSnippet: "Run benchmark experiment and parse METRIC lines",
		promptGuidelines: ["Use run_experiment for each measured autoresearch run, then call log_experiment exactly once for the outcome."],
		parameters: Type.Object({
			command: Type.String({ description: "Shell command to run." }),
			timeout_seconds: Type.Optional(Type.Number({ description: "Timeout in seconds. Default 600." })),
			checks_timeout_seconds: Type.Optional(Type.Number({ description: "Timeout for autoresearch.checks.sh when present. Default 300." })),
		}),
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const workflow = activeWorkflow(ctx, "autoresearch");
			if (!workflow) return { content: [{ type: "text", text: "No active autoresearch workflow." }], isError: true };
			const workDir = autoresearchWorkDir(ctx.cwd);
			const config = autoresearchConfig(ctx.cwd);
			const entries = readAutoresearchEntries(ctx.cwd);
			const runCount = entries.filter((entry) => entry.type === "run").length;
			const timeoutSeconds = Number.isFinite(params.timeout_seconds) && params.timeout_seconds > 0 ? Math.trunc(params.timeout_seconds) : EXPERIMENT_TIMEOUT_SECONDS;
			const budgetReason = autoresearchBudgetViolation(ctx.cwd, timeoutSeconds);
			if (budgetReason) {
				changeWorkflowStatus(pi, workflow, "budget_limited", budgetReason, "Adjust autoresearch.config.json, call init_experiment to start a new segment, or stop_autoresearch to pause.");
				renderAutoresearchWidget(ctx);
				return { content: [{ type: "text", text: `${budgetReason} The loop is budget-limited.` }], isError: true };
			}
			if (config.maxCommandRepeats && commandRepeatCount(entries, params.command) >= config.maxCommandRepeats) {
				const reason = `Command repeat budget reached (${config.maxCommandRepeats}) for: ${params.command}`;
				changeWorkflowStatus(pi, workflow, "budget_limited", reason, "Change the experiment strategy or adjust maxCommandRepeats.");
				renderAutoresearchWidget(ctx);
				return { content: [{ type: "text", text: reason }], isError: true };
			}
			const beforeHook = await runAutoresearchHook(ctx.cwd, "before", { next_run: runCount + 1, last_run: lastAutoresearchRun(ctx.cwd), session: autoresearchSessionSnapshot(ctx.cwd, workflow) });
			appendHookEntry(ctx.cwd, "before", beforeHook);
			const beforeSteer = hookSteer("before", beforeHook);
			const scriptPath = autoresearchScriptPath(ctx.cwd);
			if (existsSync(scriptPath) && !isAutoresearchScriptCommand(params.command)) {
				return { content: [{ type: "text", text: `autoresearch.sh exists at ${scriptPath}; run it instead of a custom command. Use run_experiment({ command: "./autoresearch.sh" }) or bash autoresearch.sh.` }], isError: true };
			}
			onUpdate?.({ content: [{ type: "text", text: `Running: ${params.command}` }] });
			const started = Date.now();
			const result = await pi.exec("bash", ["-lc", params.command], { cwd: workDir, timeout: timeoutSeconds * 1000, signal });
			const durationSeconds = (Date.now() - started) / 1000;
			const output = `${result.stdout ?? ""}${result.stderr ? `\n${result.stderr}` : ""}`;
			const parsedMetrics = parseMetricLines(output);
			const passed = result.code === 0 && !result.killed;
			let checksPass: boolean | null = null;
			let checksOutput = "";
			let checksDuration = 0;
			const checksPath = autoresearchChecksPath(ctx.cwd);
			if (passed && existsSync(checksPath)) {
				const checksTimeout = Number.isFinite(params.checks_timeout_seconds) && params.checks_timeout_seconds > 0 ? Math.trunc(params.checks_timeout_seconds) : 300;
				const checksStarted = Date.now();
				const checks = await pi.exec("bash", ["-lc", "bash autoresearch.checks.sh"], { cwd: workDir, timeout: checksTimeout * 1000, signal });
				checksDuration = (Date.now() - checksStarted) / 1000;
				checksOutput = `${checks.stdout ?? ""}${checks.stderr ? `\n${checks.stderr}` : ""}`;
				checksPass = checks.code === 0 && !checks.killed;
			}
			const details = { command: params.command, durationSeconds, exitCode: result.code, passed, output, parsedMetrics, checksPass, checksOutput, checksDuration };
			lastExperimentBySession.set(ctx.sessionManager.getSessionId(), details);
			const text = [
				beforeSteer ? `Before hook:\n${beforeSteer}\n` : "",
				`Command: ${params.command}`,
				`Working directory: ${workDir}`,
				`Exit code: ${result.code ?? "null"}${result.killed ? " (timed out/killed)" : ""}`,
				`Duration: ${durationSeconds.toFixed(2)}s`,
				parsedMetrics ? `Parsed metrics: ${JSON.stringify(parsedMetrics)}` : "Parsed metrics: none",
				checksPass === null ? "Checks: not run" : `Checks: ${checksPass ? "passed" : "failed"} in ${checksDuration.toFixed(2)}s`,
				checksOutput ? `\nChecks output tail:\n${tailLines(checksOutput, 20)}` : "",
				"",
				"Output tail:",
				tailLines(output),
			].filter(Boolean).join("\n");
			return { content: [{ type: "text", text }], details };
		},
	});

	pi.registerTool({
		name: "log_experiment",
		label: "Log Experiment",
		description: "Log an autoresearch experiment outcome, commit kept changes, and revert losers/crashes while preserving autoresearch files.",
		promptSnippet: "Log autoresearch outcome and keep/revert code changes",
		promptGuidelines: ["Call log_experiment after every run_experiment. Use keep only for evidence-backed improvements."],
		parameters: Type.Object({
			metric: Type.Number({ description: "Primary metric value. Use parsed METRIC value when available; use 0 for crashes without a metric." }),
			status: Type.Union([Type.Literal("keep"), Type.Literal("discard"), Type.Literal("crash"), Type.Literal("checks_failed")]),
			description: Type.String({ description: "Short description of the hypothesis/change." }),
			metrics: Type.Optional(Type.Object({}, { additionalProperties: Type.Number() })),
			asi: Type.Optional(Type.Object({
				hypothesis: Type.Optional(Type.String({ description: "What this run tried to prove." })),
				evidence: Type.Optional(Type.String({ description: "Docs, code paths, papers, prior run ids, or observations that motivated the run." })),
				changed: Type.Optional(Type.String({ description: "Concise summary of what changed." })),
				learned: Type.Optional(Type.String({ description: "What the run taught, including negative results." })),
				next_focus: Type.Optional(Type.String({ description: "Most promising next move." })),
				risk: Type.Optional(Type.String({ description: "Correctness, benchmark, cost, or overfitting risk to watch." })),
			}, { additionalProperties: Type.Any(), description: "Actionable side information for future iterations. Prefer hypothesis, evidence, changed, learned, next_focus, and risk." })),
			
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const workflow = activeWorkflow(ctx, "autoresearch");
			if (!workflow) return { content: [{ type: "text", text: "No active autoresearch workflow." }], isError: true };
			const workDir = autoresearchWorkDir(ctx.cwd);
			const entries = readAutoresearchEntries(ctx.cwd);
			const config = [...entries].reverse().find((entry) => entry.type === "config") ?? {};
			const direction = config.direction === "higher" ? "higher" : "lower";
			const runCount = entries.filter((entry) => entry.type === "run").length + 1;
			const lastRun = lastExperimentBySession.get(ctx.sessionManager.getSessionId());
			if (params.status === "keep" && lastRun?.checksPass === false) {
				return { content: [{ type: "text", text: `Cannot keep: autoresearch.checks.sh failed. Log this run as checks_failed.\n\n${tailLines(lastRun.checksOutput, 20)}` }], isError: true };
			}
			const metricName = typeof config.metric_name === "string" ? config.metric_name : "metric";
			const metrics = { ...(lastRun?.parsedMetrics ?? {}), ...(params.metrics ?? {}) };
			const asi = params.asi && typeof params.asi === "object" && !Array.isArray(params.asi) ? params.asi : undefined;
			appendAutoresearchEntry(ctx.cwd, {
				type: "run",
				workflowId: workflow.id,
				run: runCount,
				metric: params.metric,
				metric_name: metricName,
				metrics,
				status: params.status,
				description: params.description,
				asi,
				command: lastRun?.command,
				duration_seconds: lastRun?.durationSeconds,
				exit_code: lastRun?.exitCode,
				checks_pass: lastRun?.checksPass,
				checks_duration: lastRun?.checksDuration,
			});

			let gitText = "";
			if ((await execText(pi, workDir, "git rev-parse --is-inside-work-tree 2>/dev/null")) === "true") {
				if (params.status === "keep") {
					await pi.exec("bash", ["-lc", `git add -A && git commit -m ${JSON.stringify(`autoresearch: ${oneLine(params.description, 48)}`)}`], { cwd: workDir, timeout: 120_000 });
					gitText = "\nGit: kept changes and attempted commit.";
				} else {
					await pi.exec(
						"bash",
						["-lc", "git checkout -- . ':(exclude,glob)**/autoresearch.*' 2>/dev/null; git clean -fd -e 'autoresearch.*' -e '**/autoresearch.*/**' 2>/dev/null"],
						{ cwd: workDir, timeout: 120_000 },
					);
					gitText = "\nGit: reverted code changes, preserving autoresearch files.";
				}
			}

			const updatedEntries = readAutoresearchEntries(ctx.cwd);
			const runEntry = updatedEntries.filter((entry) => entry.type === "run").at(-1) ?? {};
			const thrashReason = detectAutoresearchThrash(updatedEntries);
			if (thrashReason) {
				appendAutoresearchEntry(ctx.cwd, { type: "guard", guard: "anti_thrash", reason: thrashReason, run: runCount });
				pi.sendUserMessage(`[autoresearch anti-thrash] ${thrashReason} Do not repeat the same approach. Use research_probe or inspect the benchmark/source, then choose a structurally different hypothesis.`, { deliverAs: "steer" });
			}
			const afterHook = await runAutoresearchHook(ctx.cwd, "after", { run_entry: runEntry, session: autoresearchSessionSnapshot(ctx.cwd, workflow) });
			appendHookEntry(ctx.cwd, "after", afterHook);
			const afterSteer = hookSteer("after", afterHook);
			if (afterSteer) pi.sendUserMessage(afterSteer, { deliverAs: "steer" });
			const bestMetric = bestMetricFromEntries(updatedEntries, direction);
			updateWorkflow(pi, workflow, {
				status: "active",
				note: `Run ${runCount}: ${params.status}, ${metricName}=${params.metric}. ${params.description}`,
				nextAction: thrashReason ? "Break the repeated pattern: gather evidence or pick a structurally different hypothesis before the next experiment." : "Run the next experiment.",
				data: { runCount, bestMetric, direction, metricName },
			});
			renderAutoresearchWidget(ctx);
			return { content: [{ type: "text", text: `Logged run ${runCount}: ${params.status}, ${metricName}=${params.metric}.${gitText}${thrashReason ? `\nAnti-thrash guard queued: ${thrashReason}` : ""}${afterSteer ? "\nAfter hook output queued as steer." : ""}` }] };
		},
	});
}

async function startGoal(pi: ExtensionAPI, ctx: ExtensionCommandContext, objective: string) {
	pauseOtherActiveWorkflows(pi, ctx, "goal", `Paused because a new goal was started: ${objective}`);
	const existing = activeWorkflow(ctx, "goal");
	if (existing) changeWorkflowStatus(pi, existing, "paused", `Paused because a new goal was started: ${objective}`);
	const event = startWorkflow(pi, { controller: "goal", title: oneLine(objective), objective, status: "active" });
	const workflow = eventToWorkflow(event);
	runtimeFor(ctx).turns = 0;
	ensureWorkflowToolsActive(pi);
	if (ctx.hasUI) ctx.ui.notify(`Goal started: ${oneLine(objective)}`, "info");
	sendWorkflowPrompt(pi, goalController, workflow, "start");
}

async function continueWorkflow(pi: ExtensionAPI, ctx: ExtensionCommandContext, controller: WorkflowController, workflow: WorkflowRecord) {
	if (workflow.status === "paused") return ctx.ui.notify(`${controller.label} is paused.`, "warning");
	if (["complete", "failed", "cleared"].includes(workflow.status)) return ctx.ui.notify(`${controller.label} is ${workflow.status}.`, "warning");
	controller.name === "autoresearch" ? ensureAutoresearchToolsActive(pi) : ensureWorkflowToolsActive(pi);
	sendWorkflowPrompt(pi, controller, workflow, "continue");
}

async function handleGoalCommand(pi: ExtensionAPI, args: string, ctx: ExtensionCommandContext) {
	const raw = args.trim();
	const [verb = "", ...restParts] = raw.split(/\s+/);
	const rest = restParts.join(" ").trim();
	if (!raw || verb === "status" || verb === "show" || verb === "view") return showText(ctx, "Goal status", statusText(ctx, goalController));
	const current = activeWorkflow(ctx, "goal") ?? latestWorkflow(ctx, "goal");
	if (verb === "pause") {
		if (!current || current.status === "complete" || current.status === "cleared") return ctx.ui.notify("No active goal to pause.", "warning");
		changeWorkflowStatus(pi, current, "paused", rest || "Paused by user.");
		return ctx.ui.notify("Goal paused.", "info");
	}
	if (verb === "resume") {
		if (!current || current.status === "complete" || current.status === "cleared") return ctx.ui.notify("No paused goal to resume.", "warning");
		changeWorkflowStatus(pi, current, "active", rest || "Resumed by user.");
		runtimeFor(ctx).turns = 0;
		return continueWorkflow(pi, ctx, goalController, { ...current, status: "active", lastNote: rest || "Resumed by user." });
	}
	if (verb === "continue" || verb === "next") {
		const active = activeWorkflow(ctx, "goal");
		if (!active) return ctx.ui.notify("No active goal. Start one with /goal <objective>.", "warning");
		return continueWorkflow(pi, ctx, goalController, active);
	}
	if (verb === "clear") {
		if (!current || current.status === "cleared") return ctx.ui.notify("No goal to clear.", "warning");
		clearWorkflow(pi, current, rest || "Cleared by user.");
		return ctx.ui.notify("Goal cleared.", "info");
	}
	if (verb === "complete" || verb === "done") {
		if (!current || current.status === "complete" || current.status === "cleared") return ctx.ui.notify("No active goal to complete.", "warning");
		changeWorkflowStatus(pi, current, "complete", rest || "Marked complete by user.");
		return ctx.ui.notify("Goal marked complete.", "info");
	}
	if (verb === "edit" || verb === "set") {
		if (!rest) return ctx.ui.notify("Usage: /goal edit <new objective>", "warning");
		if (!current || current.status === "complete" || current.status === "cleared") return startGoal(pi, ctx, rest);
		updateWorkflow(pi, current, { objective: rest, title: oneLine(rest), status: "active", note: "Objective updated by user." });
		runtimeFor(ctx).turns = 0;
		return continueWorkflow(pi, ctx, goalController, { ...current, objective: rest, title: oneLine(rest), status: "active", lastNote: "Objective updated by user." });
	}
	return startGoal(pi, ctx, raw);
}

async function startReview(pi: ExtensionAPI, ctx: ExtensionCommandContext, data: Record<string, unknown>, title: string, objective: string) {
	pauseOtherActiveWorkflows(pi, ctx, "review", `Paused because a review workflow was started: ${title}`);
	const existing = activeWorkflow(ctx, "review");
	if (existing) changeWorkflowStatus(pi, existing, "paused", `Paused because a new review was started: ${title}`);
	const event = startWorkflow(pi, { controller: "review", title, objective, status: "active", data });
	const workflow = eventToWorkflow(event);
	ensureWorkflowToolsActive(pi);
	if (ctx.hasUI) ctx.ui.notify(`Review started: ${title}`, "info");
	sendWorkflowPrompt(pi, reviewController, workflow, "start");
}

async function handleReviewCommand(pi: ExtensionAPI, args: string, ctx: ExtensionCommandContext) {
	const raw = args.trim();
	const [verb = "", ...restParts] = raw.split(/\s+/);
	const rest = restParts.join(" ").trim();
	const current = activeWorkflow(ctx, "review") ?? latestWorkflow(ctx, "review");
	if (verb === "status" || verb === "show" || verb === "view") return showText(ctx, "Review status", statusText(ctx, reviewController));
	if (verb === "clear") {
		if (!current || current.status === "cleared") return ctx.ui.notify("No review to clear.", "warning");
		clearWorkflow(pi, current, rest || "Cleared by user.");
		return ctx.ui.notify("Review cleared.", "info");
	}
	if (verb === "continue" || verb === "again") {
		const active = activeWorkflow(ctx, "review");
		if (!active) return ctx.ui.notify("No active review. Start one with /review.", "warning");
		return continueWorkflow(pi, ctx, reviewController, active);
	}
	if (verb === "--base" || verb === "base") {
		const base = rest || "main";
		const mergeBase = await execText(pi, ctx.cwd, `git merge-base HEAD ${JSON.stringify(base)} 2>/dev/null`);
		return startReview(pi, ctx, { target: "base", base, mergeBase }, `review against ${base}`, `Review changes against ${base}`);
	}
	if (verb === "--commit" || verb === "commit") {
		const commit = rest || "HEAD";
		return startReview(pi, ctx, { target: "commit", commit }, `review commit ${commit}`, `Review commit ${commit}`);
	}
	if (raw) return startReview(pi, ctx, { target: "custom", instructions: raw }, oneLine(`review: ${raw}`), raw);
	return startReview(pi, ctx, { target: "current" }, "review current changes", "Review current staged, unstaged, and untracked changes");
}

async function startAutoresearch(pi: ExtensionAPI, ctx: ExtensionCommandContext, objective: string) {
	pauseOtherActiveWorkflows(pi, ctx, "autoresearch", `Paused because autoresearch was started: ${objective}`);
	const existing = activeWorkflow(ctx, "autoresearch");
	if (existing) changeWorkflowStatus(pi, existing, "paused", `Paused because a new autoresearch workflow was started: ${objective}`);
	const event = startWorkflow(pi, { controller: "autoresearch", title: oneLine(objective), objective, status: "active", data: { runCount: 0 } });
	const workflow = eventToWorkflow(event);
	runtimeFor(ctx).turns = 0;
	ensureAutoresearchToolsActive(pi);
	renderAutoresearchWidget(ctx);
	if (ctx.hasUI) ctx.ui.notify(`Autoresearch started: ${oneLine(objective)}`, "info");
	sendWorkflowPrompt(pi, autoresearchController, workflow, "start");
}

async function handleAutoresearchCommand(pi: ExtensionAPI, args: string, ctx: ExtensionCommandContext) {
	const raw = args.trim();
	const [verb = "", ...restParts] = raw.split(/\s+/);
	const rest = restParts.join(" ").trim();
	const current = activeWorkflow(ctx, "autoresearch") ?? latestWorkflow(ctx, "autoresearch");
	if (!raw || verb === "status" || verb === "show" || verb === "view") return showText(ctx, "Autoresearch status", `${statusText(ctx, autoresearchController)}\n\n${autoresearchMarkdown(ctx.cwd)}`);
	if (verb === "export" || verb === "dashboard") return exportAutoresearchDashboard(pi, ctx);
	if (verb === "expand") {
		dashboardExpandedSessions.add(ctx.sessionManager.getSessionId());
		renderAutoresearchWidget(ctx);
		return ctx.ui.notify("Autoresearch dashboard expanded", "info");
	}
	if (verb === "collapse") {
		dashboardExpandedSessions.delete(ctx.sessionManager.getSessionId());
		renderAutoresearchWidget(ctx);
		return ctx.ui.notify("Autoresearch dashboard collapsed", "info");
	}
	if (verb === "fullscreen") return showText(ctx, "Autoresearch dashboard", autoresearchMarkdown(ctx.cwd));
	if (verb === "finalize" || verb === "finalise") {
		const path = writeAutoresearchFinalize(ctx.cwd);
		return showText(ctx, "Autoresearch finalize", `Wrote ${path}\n\n${readFileSync(path, "utf8")}`);
	}
	if (verb === "off" || verb === "pause") {
		if (!current || current.status === "complete" || current.status === "cleared") return ctx.ui.notify("No active autoresearch workflow to pause.", "warning");
		changeWorkflowStatus(pi, current, "paused", rest || "Paused by user.");
		renderAutoresearchWidget(ctx);
		return ctx.ui.notify("Autoresearch paused.", "info");
	}
	if (verb === "resume" || verb === "continue" || verb === "next") {
		if (!current || current.status === "complete" || current.status === "cleared") return ctx.ui.notify("No autoresearch workflow to resume.", "warning");
		changeWorkflowStatus(pi, current, "active", rest || "Resumed by user.");
		runtimeFor(ctx).turns = 0;
		return continueWorkflow(pi, ctx, autoresearchController, { ...current, status: "active", lastNote: rest || "Resumed by user." });
	}
	if (verb === "clear") {
		if (current && current.status !== "cleared") clearWorkflow(pi, current, rest || "Cleared by user.");
		const jsonl = autoresearchJsonlPath(ctx.cwd);
		if (existsSync(jsonl)) unlinkSync(jsonl);
		renderAutoresearchWidget(ctx);
		return ctx.ui.notify("Autoresearch cleared.", "info");
	}
	return startAutoresearch(pi, ctx, raw);
}

async function handleWorkflowCommand(pi: ExtensionAPI, args: string, ctx: ExtensionCommandContext) {
	const raw = args.trim();
	const [verb = "status", ...restParts] = raw.split(/\s+/);
	const rest = restParts.join(" ").trim();
	if (verb === "status" || verb === "list" || verb === "show") return showText(ctx, "Workflow status", renderWorkflowList(ctx));
	if (verb === "clear") {
		const active = activeWorkflow(ctx, rest || undefined);
		if (!active) return ctx.ui.notify(rest ? `No active ${rest} workflow.` : "No active workflow.", "warning");
		clearWorkflow(pi, active, "Cleared by user via /workflow clear.");
		return ctx.ui.notify("Workflow cleared.", "info");
	}
	ctx.ui.notify("Usage: /workflow [status|list|clear [controller]]", "warning");
}

function controllerFor(workflow: WorkflowRecord): WorkflowController | undefined {
	if (workflow.controller === "goal") return goalController;
	if (workflow.controller === "autoresearch") return autoresearchController;
	if (workflow.controller === "review") return reviewController;
	return undefined;
}

function scheduleAutoContinue(pi: ExtensionAPI, ctx: ExtensionContext) {
	const workflow = workflows(ctx).findLast((item) => AUTO_CONTINUE_CONTROLLERS.has(item.controller) && item.status === "active");
	if (!workflow) return;
	const controller = controllerFor(workflow);
	if (!controller) return;
	const runtime = runtimeFor(ctx);
	if (runtime.lastWorkflowId !== workflow.id) {
		runtime.lastWorkflowId = workflow.id;
		runtime.turns = 0;
	}
	const maxTurns = maxAutoTurns(ctx.cwd);
	if (runtime.turns >= maxTurns) {
		changeWorkflowStatus(pi, workflow, "budget_limited", `Auto-continue limit reached (${maxTurns} turns).`, "Use /goal resume or /autoresearch resume to continue.");
		ctx.ui.notify(`Workflow auto-continue limit reached (${maxTurns} turns).`, "info");
		return;
	}
	if (runtime.timer) clearTimeout(runtime.timer);
	runtime.timer = setTimeout(() => {
		runtime.timer = null;
		if (!ctx.isIdle() || ctx.hasPendingMessages()) return;
		const fresh = activeWorkflow(ctx, workflow.controller);
		if (!fresh || fresh.id !== workflow.id || fresh.status !== "active") return;
		runtime.turns += 1;
		workflow.controller === "autoresearch" ? ensureAutoresearchToolsActive(pi) : ensureWorkflowToolsActive(pi);
		sendWorkflowPrompt(pi, controller, fresh, "continue");
	}, AUTO_CONTINUE_SETTLED_MS);
}

export default function workflowExtension(pi: ExtensionAPI) {
	registerWorkflowTools(pi);
	registerAutoresearchTools(pi);

	pi.registerShortcut("ctrl+shift+t", {
		description: "Toggle autoresearch dashboard widget expansion",
		handler: async (ctx) => {
			const key = ctx.sessionManager.getSessionId();
			if (dashboardExpandedSessions.has(key)) dashboardExpandedSessions.delete(key);
			else dashboardExpandedSessions.add(key);
			renderAutoresearchWidget(ctx);
		},
	});

	pi.registerShortcut("ctrl+shift+f", {
		description: "Open autoresearch dashboard",
		handler: async (ctx) => {
			if (!ctx.hasUI) return;
			await ctx.ui.editor("Autoresearch dashboard", autoresearchMarkdown(ctx.cwd));
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		ensureWorkflowToolsActive(pi);
		if (activeWorkflow(ctx, "autoresearch")) ensureAutoresearchToolsActive(pi);
		bumpWorkflowStatusLine(ctx);
		renderAutoresearchWidget(ctx);
	});

	pi.on("session_tree", async (_event, ctx) => {
		bumpWorkflowStatusLine(ctx);
		renderAutoresearchWidget(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.hasUI) {
			ctx.ui.setWidget("autoresearch", undefined);
			ctx.ui.setStatus(WORKFLOW_STATUS_KEY, undefined);
		}
		if (dashboardServer) dashboardServer.close();
		dashboardServer = null;
		dashboardUrl = null;
	});

	pi.on("session_before_compact", async (event, ctx) => {
		if (!activeWorkflow(ctx, "autoresearch") && autoresearchSummary(ctx.cwd).runs.length === 0) return undefined;
		return {
			compaction: {
				summary: autoresearchCompactionSummary(ctx.cwd),
				firstKeptEntryId: event.preparation.firstKeptEntryId,
				tokensBefore: event.preparation.tokensBefore,
			},
		};
	});

	pi.on("session_compact", async (_event, ctx) => {
		bumpWorkflowStatusLine(ctx);
		renderAutoresearchWidget(ctx);
		const workflow = activeWorkflow(ctx, "autoresearch");
		if (workflow?.status === "active") pi.sendUserMessage("Continue autoresearch after compaction. Use persisted autoresearch state and run the next experiment now.", { deliverAs: "followUp" });
	});

	pi.on("agent_start", async (_event, ctx) => {
		bumpWorkflowStatusLine(ctx);
	});

	pi.on("turn_start", async (_event, ctx) => {
		bumpWorkflowStatusLine(ctx);
	});

	pi.on("turn_end", async (_event, ctx) => {
		bumpWorkflowStatusLine(ctx);
	});

	pi.on("agent_end", async (_event, ctx) => {
		bumpWorkflowStatusLine(ctx);
		renderAutoresearchWidget(ctx);
		scheduleAutoContinue(pi, ctx);
	});

	pi.registerCommand("goal", {
		description: "Start, continue, pause, resume, or inspect a durable goal workflow",
		handler: async (args, ctx) => {
			try { return await handleGoalCommand(pi, args, ctx); }
			finally { bumpWorkflowStatusLine(ctx); }
		},
	});

	pi.registerCommand("review", {
		description: "Review current changes, a base-branch diff, or a commit using workflow core",
		handler: async (args, ctx) => {
			try { return await handleReviewCommand(pi, args, ctx); }
			finally { bumpWorkflowStatusLine(ctx); }
		},
	});

	pi.registerCommand("autoresearch", {
		description: "Start, pause, resume, or inspect an autoresearch workflow",
		handler: async (args, ctx) => {
			try { return await handleAutoresearchCommand(pi, args, ctx); }
			finally { bumpWorkflowStatusLine(ctx); }
		},
	});

	pi.registerCommand("workflow", {
		description: "Inspect or clear Pi workflow-core state",
		handler: async (args, ctx) => {
			try { return await handleWorkflowCommand(pi, args, ctx); }
			finally { bumpWorkflowStatusLine(ctx); }
		},
	});
}
