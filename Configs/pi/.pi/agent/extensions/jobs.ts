import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { StringEnum, Type } from "@mariozechner/pi-ai";
import { defineTool, type ExtensionAPI, type ExtensionCommandContext, type ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Box, Text } from "@mariozechner/pi-tui";

const TOOL_NAME = "pi_job";
const MESSAGE_TYPE = "pi-job-result";
const STATUS_ID = "jobs";
const CHILD_ENV = "PI_JOB_CHILD";
const DEFAULT_SYNC_TIMEOUT_SECONDS = 120;
const MAX_SYNC_TIMEOUT_SECONDS = 600;
const DEFAULT_MAX_CHARS = 18_000;
const MAX_TOOL_CHARS = 100_000;
const AUTO_EMIT_MAX_CHARS = 18_000;
const MAX_INTERNAL_TEXT_CHARS = 200_000;
const MAX_STDERR_CHARS = 64_000;
const MAX_NON_JSON_CHARS = 64_000;
const MAX_PROGRESS_LINES = 80;
const MAX_RETAINED_JOBS = 50;

const CHILD_SYSTEM_PROMPT = `You are a headless child Pi process spawned by a parent Pi session.
Return compact, directly useful findings for the parent session.
Include the answer, evidence paths or commands run, confidence, and the recommended next action when relevant.
Do not start background jobs or nested orchestration. If a pi_job tool is available, do not use action=start.`;

type JobStatus = "running" | "done" | "failed" | "cancelled";

type PiJobEvent = {
	jobId: string;
	status: JobStatus;
	exitCode: number | null;
	exitSignal: string | null;
	elapsedSeconds: number;
	cwd: string;
	model: string;
	tools: string;
	prompt: string;
	output: string;
	stderr?: string;
	timedOut?: boolean;
	cancelled?: boolean;
};

type UsageStats = {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
	contextTokens: number;
	turns: number;
};

type LaunchOptions = {
	prompt: string;
	cwd?: string;
	model?: string;
	tools?: unknown;
	appendSystemPrompt?: string;
	autoEmit: boolean;
	defaultTools: string[];
	modelLabel: string;
	thinkingLevel?: string;
};

type PiJob = {
	id: string;
	proc: ReturnType<typeof spawn>;
	prompt: string;
	cwd: string;
	modelLabel: string;
	toolsLabel: string;
	startedAt: number;
	completedAt?: number;
	exitCode: number | null;
	exitSignal: string | null;
	autoEmit: boolean;
	emitted: boolean;
	cancelled: boolean;
	timedOut: boolean;
	errorMessage?: string;
	tempDir?: string;
	stdoutRemainder: string;
	currentText: string;
	finalText: string;
	stderr: string;
	nonJsonStdout: string;
	progress: string[];
	eventCount: number;
	usage: UsageStats;
	done: Promise<PiJob>;
	resolveDone: (job: PiJob) => void;
};

let jobCounter = 0;
let sessionAlive = false;
let lastContext: ExtensionContext | undefined;
const jobs = new Map<string, PiJob>();

function textResult(text: string, details: Record<string, unknown> = {}) {
	return {
		content: [{ type: "text" as const, text }],
		details,
	};
}

function nextJobId(): string {
	jobCounter += 1;
	return `pi-${jobCounter}`;
}

function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
	const numeric = typeof value === "string" ? Number(value) : typeof value === "number" ? value : Number.NaN;
	if (!Number.isFinite(numeric)) return fallback;
	return Math.max(min, Math.min(max, Math.trunc(numeric)));
}

function coerceBoolean(value: unknown, fallback: boolean): boolean {
	if (typeof value === "boolean") return value;
	if (typeof value === "string") {
		const normalised = value.trim().toLowerCase();
		if (["1", "true", "yes", "y", "on"].includes(normalised)) return true;
		if (["0", "false", "no", "n", "off"].includes(normalised)) return false;
	}
	return fallback;
}

function truncateMiddle(text: string, maxChars: number, label = "output truncated"): string {
	if (text.length <= maxChars) return text;
	if (maxChars <= 120) return text.slice(0, maxChars);
	const omitted = text.length - maxChars;
	const marker = `\n\n[${label}: ${omitted} characters omitted]\n\n`;
	const remaining = Math.max(1, maxChars - marker.length);
	const head = Math.max(1, Math.floor(remaining * 0.65));
	const tail = Math.max(1, remaining - head);
	return `${text.slice(0, head)}${marker}${text.slice(text.length - tail)}`;
}

function appendBounded(current: string, addition: string, maxChars: number, label: string): string {
	const next = current + addition;
	if (next.length <= maxChars) return next;
	const marker = `\n[${label}: kept last ${maxChars} characters]\n`;
	return marker + next.slice(Math.max(0, next.length - maxChars + marker.length));
}

function boundedText(text: string, maxChars: number, label: string): string {
	return truncateMiddle(text, maxChars, label);
}

function shortJson(value: unknown, maxChars = 180): string {
	try {
		return truncateMiddle(JSON.stringify(value), maxChars, "json truncated").replace(/\s+/g, " ");
	} catch {
		return String(value).slice(0, maxChars);
	}
}

function formatTokens(count: number): string {
	if (!count) return "0";
	if (count < 1000) return String(count);
	if (count < 1_000_000) return `${Math.round(count / 1000)}k`;
	return `${(count / 1_000_000).toFixed(1)}M`;
}

function formatUsage(usage: UsageStats): string {
	const parts: string[] = [];
	if (usage.turns) parts.push(`${usage.turns} turn${usage.turns === 1 ? "" : "s"}`);
	if (usage.input) parts.push(`↑${formatTokens(usage.input)}`);
	if (usage.output) parts.push(`↓${formatTokens(usage.output)}`);
	if (usage.cacheRead) parts.push(`R${formatTokens(usage.cacheRead)}`);
	if (usage.cacheWrite) parts.push(`W${formatTokens(usage.cacheWrite)}`);
	if (usage.cost) parts.push(`$${usage.cost.toFixed(4)}`);
	if (usage.contextTokens) parts.push(`ctx:${formatTokens(usage.contextTokens)}`);
	return parts.join(" ");
}

function expandHome(path: string): string {
	return path === "~" ? homedir() : path.startsWith("~/") ? join(homedir(), path.slice(2)) : path;
}

function resolveCwd(cwd: string | undefined, baseCwd: string): string {
	if (!cwd?.trim()) return baseCwd;
	const expanded = expandHome(cwd.trim());
	return resolve(baseCwd, expanded);
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}

	const execName = basename(process.execPath).toLowerCase();
	const isGenericRuntime = /^(node|bun)(\.exe)?$/.test(execName);
	if (!isGenericRuntime) return { command: process.execPath, args };
	return { command: "pi", args };
}

function defaultToolNames(pi: ExtensionAPI): string[] {
	const byName = new Map(pi.getAllTools().map((tool) => [tool.name, tool]));
	return pi.getActiveTools().filter((name) => {
		if (name === TOOL_NAME) return false;
		const source = byName.get(name)?.sourceInfo?.source;
		return source !== "sdk";
	});
}

function parseToolNames(value: unknown, defaults: string[]): string[] {
	if (value === undefined || value === null || value === "") return [...defaults];

	let names: string[];
	if (Array.isArray(value)) {
		names = value.map((item) => String(item));
	} else {
		const raw = String(value).trim();
		const lowered = raw.toLowerCase();
		if (["none", "no", "false", "0"].includes(lowered)) return [];
		if (["default", "parent", "all", "*", "core", "pi", "safe", "readonly"].includes(lowered)) return [...defaults];
		names = raw.split(",");
	}

	return names.map((name) => name.trim()).filter((name) => name && name !== TOOL_NAME);
}

function toolsLabel(names: string[]): string {
	return names.length === 0 ? "none" : names.join(",");
}

function modelPattern(ctx: ExtensionContext, explicitModel: string | undefined): string | undefined {
	if (explicitModel?.trim()) return explicitModel.trim();
	return ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined;
}

function modelDisplay(ctx: ExtensionContext, explicitModel: string | undefined): string {
	return modelPattern(ctx, explicitModel) ?? "default";
}

async function buildLaunchSpec(ctx: ExtensionContext, options: LaunchOptions) {
	const args = ["--mode", "json", "-p", "--no-session"];
	const toolNames = parseToolNames(options.tools, options.defaultTools);
	args.push("--tools", toolNames.length ? toolNames.join(",") : "none");

	if (options.model?.trim()) {
		args.push("--model", options.model.trim());
	} else if (options.modelLabel !== "default") {
		args.push("--model", options.modelLabel);
	}

	if (!options.model?.trim() && options.thinkingLevel && options.thinkingLevel !== "off") {
		args.push("--thinking", options.thinkingLevel);
	}

	const promptParts = [CHILD_SYSTEM_PROMPT];
	if (options.appendSystemPrompt?.trim()) promptParts.push(options.appendSystemPrompt.trim());

	let tempDir: string | undefined;
	if (promptParts.length > 0) {
		tempDir = await mkdtemp(join(tmpdir(), "pi-job-"));
		const promptPath = join(tempDir, "system.md");
		await writeFile(promptPath, promptParts.join("\n\n"), { encoding: "utf-8", mode: 0o600 });
		args.push("--append-system-prompt", promptPath);
	}

	args.push(`Task: ${options.prompt}`);

	const cwd = resolveCwd(options.cwd, ctx.cwd);
	if (!existsSync(cwd)) throw new Error(`Pi job cwd does not exist: ${cwd}`);

	return {
		...getPiInvocation(args),
		cwd,
		env: {
			...process.env,
			[CHILD_ENV]: "1",
			PI_JOB_PARENT_PID: String(process.pid),
		},
		tempDir,
		toolsLabel: toolsLabel(toolNames),
	};
}

function extractTextFromContent(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.map((part) => {
			if (part && typeof part === "object" && (part as { type?: unknown }).type === "text") {
				return String((part as { text?: unknown }).text ?? "");
			}
			return "";
		})
		.filter(Boolean)
		.join("\n");
}

function extractAssistantText(message: unknown): string {
	if (!message || typeof message !== "object") return "";
	const role = (message as { role?: unknown }).role;
	if (role !== "assistant") return "";
	return extractTextFromContent((message as { content?: unknown }).content);
}

function finalAssistantText(messages: unknown): string {
	if (!Array.isArray(messages)) return "";
	for (let i = messages.length - 1; i >= 0; i -= 1) {
		const text = extractAssistantText(messages[i]);
		if (text.trim()) return text;
	}
	return "";
}

function appendUsage(job: PiJob, message: unknown) {
	if (!message || typeof message !== "object") return;
	if ((message as { role?: unknown }).role !== "assistant") return;
	const usage = (message as { usage?: any }).usage;
	if (!usage) return;

	job.usage.turns += 1;
	job.usage.input += usage.input || 0;
	job.usage.output += usage.output || 0;
	job.usage.cacheRead += usage.cacheRead || 0;
	job.usage.cacheWrite += usage.cacheWrite || 0;
	job.usage.cost += usage.cost?.total || 0;
	job.usage.contextTokens = usage.totalTokens || job.usage.contextTokens;
}

function addProgress(job: PiJob, line: string) {
	job.progress.push(line);
	if (job.progress.length > MAX_PROGRESS_LINES) {
		job.progress.splice(0, job.progress.length - MAX_PROGRESS_LINES);
	}
}

function toolResultPreview(result: unknown): string {
	if (result && typeof result === "object") {
		const content = (result as { content?: unknown }).content;
		const text = extractTextFromContent(content);
		if (text.trim()) return truncateMiddle(text.trim().split("\n", 1)[0], 180, "result truncated");
	}
	return shortJson(result, 180);
}

function processJsonEvent(job: PiJob, event: any) {
	job.eventCount += 1;

	if (event.type === "tool_execution_start") {
		addProgress(job, `→ ${event.toolName || "tool"}(${shortJson(event.args ?? {}, 160)})`);
		return;
	}

	if (event.type === "tool_execution_end") {
		const prefix = event.isError ? "✗" : "✓";
		addProgress(job, `${prefix} ${event.toolName || "tool"}: ${toolResultPreview(event.result)}`);
		return;
	}

	if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
		job.currentText = appendBounded(
			job.currentText,
			String(event.assistantMessageEvent.delta ?? ""),
			MAX_INTERNAL_TEXT_CHARS,
			"partial assistant output truncated",
		);
		return;
	}

	if (event.type === "message_end") {
		const text = extractAssistantText(event.message);
		if (text.trim()) {
			job.finalText = boundedText(text, MAX_INTERNAL_TEXT_CHARS, "assistant output truncated");
			job.currentText = "";
		} else if ((event.message as { role?: unknown } | undefined)?.role === "assistant" && job.currentText.trim()) {
			job.finalText = boundedText(job.currentText, MAX_INTERNAL_TEXT_CHARS, "assistant output truncated");
			job.currentText = "";
		}
		appendUsage(job, event.message);
		return;
	}

	if (event.type === "agent_end") {
		const text = finalAssistantText(event.messages);
		if (text.trim()) job.finalText = boundedText(text, MAX_INTERNAL_TEXT_CHARS, "assistant output truncated");
	}
}

function processStdoutLine(job: PiJob, line: string) {
	if (!line.trim()) return;
	try {
		processJsonEvent(job, JSON.parse(line));
	} catch {
		job.nonJsonStdout = appendBounded(job.nonJsonStdout, `${line}\n`, MAX_NON_JSON_CHARS, "stdout truncated");
	}
}

function jobStatus(job: PiJob): JobStatus {
	if (!job.completedAt) return "running";
	if (job.cancelled) return "cancelled";
	return job.exitCode === 0 ? "done" : "failed";
}

function elapsedSeconds(job: PiJob): number {
	return Math.max(0, Math.round(((job.completedAt ?? Date.now()) - job.startedAt) / 1000));
}

function jobOutput(job: PiJob, maxChars: number): string {
	const progress = job.progress.length ? job.progress.join("\n") : "";
	const text = (job.finalText || job.currentText || job.nonJsonStdout || progress || job.errorMessage || "").trim();
	return boundedText(text || "(no output yet)", maxChars, "job output truncated");
}

function stderrText(job: PiJob, maxChars: number): string {
	return boundedText(job.stderr.trim(), maxChars, "stderr truncated");
}

function buildJobEvent(job: PiJob, maxChars = AUTO_EMIT_MAX_CHARS): PiJobEvent {
	const stderr = stderrText(job, 4_000);
	let output = jobOutput(job, maxChars);
	if (stderr && jobStatus(job) === "failed") {
		output = `${output}\n\nstderr:\n${stderr}`.trim();
	}

	return {
		jobId: job.id,
		status: jobStatus(job),
		exitCode: job.exitCode,
		exitSignal: job.exitSignal,
		elapsedSeconds: elapsedSeconds(job),
		cwd: job.cwd,
		model: job.modelLabel,
		tools: job.toolsLabel,
		prompt: job.prompt,
		output,
		stderr: stderr || undefined,
		timedOut: job.timedOut || undefined,
		cancelled: job.cancelled || undefined,
	};
}

function formatJobEventContent(event: PiJobEvent): string {
	return `Automatic background Pi job output. This message was emitted by the ${TOOL_NAME} extension, not typed by the user. Use it as context for the current task.

<pi_job_result id=${JSON.stringify(event.jobId)} status=${JSON.stringify(event.status)} exitCode=${JSON.stringify(event.exitCode)} elapsedSeconds=${JSON.stringify(event.elapsedSeconds)}>
<prompt>
${event.prompt}
</prompt>
<output>
${event.output || "(no output)"}
</output>
</pi_job_result>`;
}

function formatJobEventDisplay(event: PiJobEvent, maxOutput = 1200): string {
	const exit = event.exitCode ?? event.exitSignal ?? "unknown";
	const lines = [
		`Pi job ${event.jobId} ${event.status} (exit ${exit}, ${event.elapsedSeconds}s)`,
		`cwd: ${event.cwd}`,
		`model: ${event.model}`,
		`tools: ${event.tools}`,
		`prompt: ${truncateMiddle(event.prompt, 300, "prompt truncated")}`,
		"",
		boundedText(event.output || "(no output)", maxOutput, "display output truncated"),
	];
	return lines.join("\n");
}

function formatJobList(): string {
	if (jobs.size === 0) return "No Pi jobs.";
	const lines: string[] = [];
	for (const job of [...jobs.values()].sort((a, b) => a.startedAt - b.startedAt)) {
		const exit = job.completedAt ? (job.exitCode ?? job.exitSignal ?? "unknown") : "running";
		lines.push(
			`${job.id}: ${jobStatus(job)}, pid=${job.proc.pid ?? "unknown"}, exit=${exit}, elapsed=${elapsedSeconds(job)}s, prompt=${truncateMiddle(job.prompt, 100, "prompt truncated").replace(/\s+/g, " ")}`,
		);
	}
	return lines.join("\n");
}

function formatJobStatus(job: PiJob, includeOutput = false, maxChars = DEFAULT_MAX_CHARS): string {
	const status = jobStatus(job);
	const exit = job.completedAt ? (job.exitCode ?? job.exitSignal ?? "unknown") : "running";
	const usage = formatUsage(job.usage);
	const lines = [
		`job ${job.id}: ${status}`,
		`pid: ${job.proc.pid ?? "unknown"}`,
		`exitCode: ${exit}`,
		`elapsedSeconds: ${elapsedSeconds(job)}`,
		`events: ${job.eventCount}`,
		`cwd: ${job.cwd}`,
		`model: ${job.modelLabel}`,
		`tools: ${job.toolsLabel}`,
		`autoEmit: ${job.autoEmit}`,
		`emitted: ${job.emitted}`,
		`prompt: ${truncateMiddle(job.prompt, 500, "prompt truncated")}`,
	];
	if (usage) lines.push(`usage: ${usage}`);
	if (job.progress.length) lines.push("", "recent progress:", ...job.progress.slice(-12));

	const stderr = stderrText(job, maxChars);
	if (stderr && (includeOutput || status === "failed")) lines.push("", "stderr:", stderr);
	if (includeOutput || status !== "running") lines.push("", status === "running" ? "partial output:" : "output:", jobOutput(job, maxChars));
	return lines.join("\n");
}

function updateStatus(ctx = lastContext) {
	if (!ctx?.hasUI || !sessionAlive) return;
	const running = [...jobs.values()].filter((job) => jobStatus(job) === "running").length;
	ctx.ui.setStatus(STATUS_ID, running > 0 ? `jobs ${running}` : undefined);
}

async function cleanupJob(job: PiJob) {
	if (!job.tempDir) return;
	const dir = job.tempDir;
	job.tempDir = undefined;
	await rm(dir, { recursive: true, force: true }).catch(() => undefined);
}

function pruneJobs() {
	if (jobs.size <= MAX_RETAINED_JOBS) return;
	const completed = [...jobs.values()]
		.filter((job) => job.completedAt)
		.sort((a, b) => (a.completedAt ?? 0) - (b.completedAt ?? 0));
	for (const job of completed) {
		if (jobs.size <= MAX_RETAINED_JOBS) break;
		jobs.delete(job.id);
	}
}

function maybeAutoEmit(pi: ExtensionAPI, job: PiJob) {
	if (!sessionAlive || !job.autoEmit || job.emitted || job.cancelled) return;
	job.emitted = true;
	const event = buildJobEvent(job);
	pi.sendMessage<PiJobEvent>(
		{
			customType: MESSAGE_TYPE,
			content: formatJobEventContent(event),
			display: true,
			details: event,
		},
		// Do not use followUp+triggerTurn here. That starts the parent agent as soon
		// as a background job finishes, which steals focus and snaps the TUI back to
		// the bottom while the user may be reading scrollback. nextTurn keeps the
		// result silent until the user's next prompt, where it is included as context.
		{ deliverAs: "nextTurn" },
	);
}

function finalizeJob(pi: ExtensionAPI, job: PiJob, code: number | null, signal: NodeJS.Signals | null) {
	if (job.completedAt) return;
	if (job.stdoutRemainder.trim()) {
		processStdoutLine(job, job.stdoutRemainder);
		job.stdoutRemainder = "";
	}
	job.exitCode = code;
	job.exitSignal = signal;
	job.completedAt = Date.now();
	void cleanupJob(job);
	updateStatus();
	job.resolveDone(job);
	maybeAutoEmit(pi, job);
	pruneJobs();
}

function killJobProcess(job: PiJob) {
	if (job.completedAt) return;
	try {
		job.proc.kill("SIGTERM");
	} catch {
		// Ignore stale process errors.
	}
	const timer = setTimeout(() => {
		if (job.completedAt) return;
		try {
			job.proc.kill("SIGKILL");
		} catch {
			// Ignore stale process errors.
		}
	}, 5000);
	timer.unref?.();
}

async function launchJob(pi: ExtensionAPI, ctx: ExtensionContext, options: LaunchOptions): Promise<PiJob> {
	const spec = await buildLaunchSpec(ctx, options);
	let resolveDone!: (job: PiJob) => void;
	const done = new Promise<PiJob>((resolveDoneCallback) => {
		resolveDone = resolveDoneCallback;
	});

	const proc = spawn(spec.command, spec.args, {
		cwd: spec.cwd,
		env: spec.env,
		shell: false,
		stdio: ["ignore", "pipe", "pipe"],
	});

	const job: PiJob = {
		id: nextJobId(),
		proc,
		prompt: options.prompt,
		cwd: spec.cwd,
		modelLabel: options.modelLabel,
		toolsLabel: spec.toolsLabel,
		startedAt: Date.now(),
		exitCode: null,
		exitSignal: null,
		autoEmit: options.autoEmit,
		emitted: false,
		cancelled: false,
		timedOut: false,
		tempDir: spec.tempDir,
		stdoutRemainder: "",
		currentText: "",
		finalText: "",
		stderr: "",
		nonJsonStdout: "",
		progress: [],
		eventCount: 0,
		usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
		done,
		resolveDone,
	};

	proc.stdout?.on("data", (chunk: Buffer) => {
		job.stdoutRemainder += chunk.toString("utf8");
		const lines = job.stdoutRemainder.split("\n");
		job.stdoutRemainder = lines.pop() ?? "";
		for (const line of lines) processStdoutLine(job, line);
	});

	proc.stderr?.on("data", (chunk: Buffer) => {
		job.stderr = appendBounded(job.stderr, chunk.toString("utf8"), MAX_STDERR_CHARS, "stderr truncated");
	});

	proc.on("error", (error) => {
		job.errorMessage = error instanceof Error ? error.message : String(error);
		finalizeJob(pi, job, 1, null);
	});

	proc.on("close", (code, signal) => {
		finalizeJob(pi, job, code, signal);
	});

	return job;
}

function launchOptions(pi: ExtensionAPI, ctx: ExtensionContext, params: any, autoEmit: boolean): LaunchOptions {
	const model = typeof params.model === "string" ? params.model : undefined;
	return {
		prompt: String(params.prompt ?? ""),
		cwd: typeof params.cwd === "string" ? params.cwd : undefined,
		model,
		tools: params.tools,
		appendSystemPrompt: typeof params.appendSystemPrompt === "string" ? params.appendSystemPrompt : undefined,
		autoEmit,
		defaultTools: defaultToolNames(pi),
		modelLabel: modelDisplay(ctx, model),
		thinkingLevel: pi.getThinkingLevel(),
	};
}

async function runSynchronousJob(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	params: any,
	signal: AbortSignal | undefined,
	_onUpdate: ((result: ReturnType<typeof textResult>) => void) | undefined,
): Promise<ReturnType<typeof textResult>> {
	const timeoutSeconds = clampNumber(params.timeoutSeconds, DEFAULT_SYNC_TIMEOUT_SECONDS, 1, MAX_SYNC_TIMEOUT_SECONDS);
	const maxChars = clampNumber(params.maxCharacters, DEFAULT_MAX_CHARS, 1_000, MAX_TOOL_CHARS);
	const job = await launchJob(pi, ctx, launchOptions(pi, ctx, params, false));

	const timeout = setTimeout(() => {
		job.timedOut = true;
		job.errorMessage = `Timed out after ${timeoutSeconds}s`;
		killJobProcess(job);
	}, timeoutSeconds * 1000);
	timeout.unref?.();

	const abort = () => {
		job.cancelled = true;
		job.errorMessage = "Aborted by parent Pi session";
		killJobProcess(job);
	};
	if (signal?.aborted) abort();
	else signal?.addEventListener("abort", abort, { once: true });

	try {
		await job.done;
	} finally {
		clearTimeout(timeout);
		signal?.removeEventListener("abort", abort);
	}

	let output = jobOutput(job, maxChars);
	if (job.timedOut) output = `Pi child timed out after ${timeoutSeconds}s.\n\n${output}`;
	else if (job.cancelled) output = `Pi child was cancelled.\n\n${output}`;
	else if (job.exitCode !== 0) output = `Pi child exited ${job.exitCode ?? job.exitSignal ?? "unknown"}.\n\n${output}`;

	const stderr = stderrText(job, 4_000);
	if (stderr && job.exitCode !== 0) output = `${output}\n\nstderr:\n${stderr}`.trim();
	return textResult(boundedText(output, maxChars, "child output truncated"), {
		action: "run",
		jobId: job.id,
		status: jobStatus(job),
		exitCode: job.exitCode,
		elapsedSeconds: elapsedSeconds(job),
	});
}

async function startBackgroundJob(pi: ExtensionAPI, ctx: ExtensionContext, params: any): Promise<PiJob> {
	const autoEmit = coerceBoolean(params.autoEmit, true);
	const job = await launchJob(pi, ctx, launchOptions(pi, ctx, params, autoEmit));
	jobs.set(job.id, job);
	updateStatus(ctx);
	pruneJobs();
	return job;
}

function sleep(ms: number) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

async function cancelJob(job: PiJob): Promise<string> {
	if (job.completedAt) {
		await cleanupJob(job);
		return `job ${job.id} already finished with status ${jobStatus(job)} and exitCode ${job.exitCode ?? job.exitSignal ?? "unknown"}`;
	}

	job.autoEmit = false;
	job.cancelled = true;
	killJobProcess(job);
	await Promise.race([job.done, sleep(6500)]);
	if (!job.completedAt) {
		try {
			job.proc.kill("SIGKILL");
		} catch {
			// Ignore stale process errors.
		}
		await Promise.race([job.done, sleep(2000)]);
	}
	updateStatus();
	return job.completedAt
		? `job ${job.id} cancelled with exitCode ${job.exitCode ?? job.exitSignal ?? "unknown"}`
		: `job ${job.id} cancellation requested`;
}

function jobById(jobId: unknown): PiJob | undefined {
	if (typeof jobId !== "string" || !jobId.trim()) return undefined;
	return jobs.get(jobId.trim());
}

function usage(command = "jobs"): string {
	return `Usage:
/${command}                         list jobs
/${command} status <jobId>          show job status
/${command} read <jobId>            show job output
/${command} cancel <jobId>          cancel a running job
/${command} start <prompt>          start a background Pi job`;
}

async function handleJobsCommand(pi: ExtensionAPI, args: string, ctx: ExtensionCommandContext) {
	lastContext = ctx;
	const trimmed = args.trim();
	if (!trimmed || trimmed === "list") {
		ctx.ui.notify(formatJobList(), "info");
		return;
	}

	const [first, second, ...rest] = trimmed.split(/\s+/);
	const action = first.toLowerCase();
	if (action === "help") {
		ctx.ui.notify(usage(), "info");
		return;
	}

	if (action === "start") {
		const prompt = [second, ...rest].filter(Boolean).join(" ").trim();
		if (!prompt) {
			ctx.ui.notify("Usage: /jobs start <prompt>", "warning");
			return;
		}
		if (process.env[CHILD_ENV] === "1") {
			ctx.ui.notify("Refusing to start a background job from a child Pi process.", "warning");
			return;
		}
		const job = await startBackgroundJob(pi, ctx, { prompt, autoEmit: true });
		ctx.ui.notify(`Started Pi job ${job.id} (pid ${job.proc.pid ?? "unknown"}). Its result will be queued silently for your next prompt.`, "info");
		return;
	}

	if (!["status", "read", "cancel"].includes(action)) {
		// Convenience: /jobs pi-1 behaves like /jobs status pi-1.
		const job = jobs.get(first);
		if (job) {
			ctx.ui.notify(formatJobStatus(job, false, DEFAULT_MAX_CHARS), "info");
			return;
		}
		ctx.ui.notify(usage(), "warning");
		return;
	}

	const job = jobs.get(second ?? "");
	if (!job) {
		ctx.ui.notify(second ? `Unknown Pi job ${second}` : `Missing job id.\n${usage()}`, "warning");
		return;
	}

	if (action === "cancel") {
		ctx.ui.notify(await cancelJob(job), "info");
		return;
	}

	ctx.ui.notify(formatJobStatus(job, action === "read", action === "read" ? 30_000 : DEFAULT_MAX_CHARS), "info");
}

function createPiJobTool(pi: ExtensionAPI) {
	return defineTool({
		name: TOOL_NAME,
		label: "Pi Job",
		description:
			"Run an isolated headless Pi process, or manage explicit background Pi jobs. Outputs are bounded; completed background jobs can queue a result message for the parent's next prompt without interrupting scrollback.",
		promptSnippet:
			"pi_job: run an isolated headless Pi process; use action=start only when the user explicitly wants background side-work.",
		promptGuidelines: [
			"Use pi_job for isolated exploration or side work that would add noise to the parent context.",
			"Default to pi_job action=run so the user gets one clean result; use action=start only when the user asks to keep working while it runs.",
			"After starting a pi_job background job, report the job id and stop polling unless the user explicitly asks you to wait or inspect it.",
			"Do not start nested pi_job background jobs from child or one-shot contexts; child Pi processes force background requests to run synchronously.",
		],
		parameters: Type.Object({
			action: Type.Optional(
				StringEnum(["run", "start", "list", "status", "read", "cancel"] as const, {
					description:
						"Action. Defaults to run when prompt is present, otherwise list. Use start for explicit background jobs.",
				}),
			),
			prompt: Type.Optional(Type.String({ description: "Task for a headless child Pi process" })),
			jobId: Type.Optional(Type.String({ description: "Job id for status/read/cancel" })),
			background: Type.Optional(
				Type.Boolean({ description: "When action is omitted, true starts a background job; otherwise prompt defaults to synchronous run." }),
			),
			autoEmit: Type.Optional(
				Type.Boolean({ description: "For action=start, queue the completed job result into the parent session on the next user prompt. Default: true." }),
			),
			tools: Type.Optional(
				Type.String({ description: "Advanced override: none, all/default, or comma-separated tool names. Omitted uses parent active tools minus pi_job." }),
			),
			appendSystemPrompt: Type.Optional(Type.String({ description: "Extra system prompt for the child process" })),
			cwd: Type.Optional(Type.String({ description: "Working directory for the child process" })),
			model: Type.Optional(Type.String({ description: "Optional model override for the child process" })),
			timeoutSeconds: Type.Optional(Type.Number({ description: "Synchronous child timeout, max 600 seconds" })),
			maxCharacters: Type.Optional(Type.Number({ description: "Maximum job output returned for run/read/status" })),
		}),
		prepareArguments(args) {
			if (!args || typeof args !== "object") return args as any;
			const input = args as { prompt?: unknown; task?: unknown };
			if (input.prompt === undefined && typeof input.task === "string") {
				return { ...input, prompt: input.task } as any;
			}
			return args as any;
		},
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			lastContext = ctx;
			const prompt = String(params.prompt ?? "");
			const background = coerceBoolean(params.background, false);
			let action = params.action ?? (prompt.trim() ? (background ? "start" : "run") : "list");
			action = action.toLowerCase() as typeof action;
			const maxChars = clampNumber(params.maxCharacters, DEFAULT_MAX_CHARS, 1_000, MAX_TOOL_CHARS);

			if (action === "list") return textResult(formatJobList(), { action });

			if (["status", "read", "cancel"].includes(action)) {
				const job = jobById(params.jobId);
				if (!job) return textResult(`error: unknown or missing Pi job ${params.jobId ?? ""}`.trim(), { action, ok: false });
				if (action === "cancel") return textResult(await cancelJob(job), { action, jobId: job.id, status: jobStatus(job) });
				return textResult(formatJobStatus(job, action === "read", maxChars), { action, jobId: job.id, status: jobStatus(job) });
			}

			if (action !== "run" && action !== "start") {
				return textResult("error: action must be run, start, list, status, read, or cancel", { action, ok: false });
			}

			if (!prompt.trim()) return textResult("error: prompt is required", { action, ok: false });

			if (action === "run" || process.env[CHILD_ENV] === "1") {
				const result = await runSynchronousJob(pi, ctx, { ...params, prompt }, signal, onUpdate as any);
				if (action === "start" && process.env[CHILD_ENV] === "1") {
					const prefix = "Nested/background Pi jobs are disabled inside child Pi processes; ran synchronously instead.\n\n";
					return textResult(prefix + result.content[0].text, { ...result.details, forcedSynchronous: true });
				}
				return result;
			}

			const job = await startBackgroundJob(pi, ctx, { ...params, prompt });
			return textResult(
				`Started Pi job ${job.id} (pid ${job.proc.pid ?? "unknown"}).\nIt will ${job.autoEmit ? "queue its result silently for the user's next prompt" : "not auto-emit"} when it finishes. Tell the user the job id. Later use action=status jobId=${job.id}, action=read, or action=cancel if needed. Do not poll repeatedly in the same response unless the user asked you to wait.`,
				{ action, jobId: job.id, pid: job.proc.pid, status: jobStatus(job), autoEmit: job.autoEmit },
			);
		},
	});
}

export default function jobsExtension(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		sessionAlive = true;
		lastContext = ctx;
		updateStatus(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		sessionAlive = false;
		ctx.ui.setStatus(STATUS_ID, undefined);
		for (const job of jobs.values()) {
			if (!job.completedAt) {
				job.autoEmit = false;
				job.cancelled = true;
				killJobProcess(job);
			}
		}
	});

	pi.registerMessageRenderer<PiJobEvent>(MESSAGE_TYPE, (message, { expanded }, theme) => {
		const event = message.details as PiJobEvent | undefined;
		if (!event) return undefined;
		const color = event.status === "done" ? "success" : event.status === "failed" ? "error" : "warning";
		const text = `${theme.fg(color, `◌ Pi job ${event.jobId} ${event.status}`)} ${theme.fg("dim", `(${event.elapsedSeconds}s)`)}\n${formatJobEventDisplay(event, expanded ? 8_000 : 900)}`;
		const box = new Box(1, 1, (value) => theme.bg("customMessageBg", value));
		box.addChild(new Text(text, 0, 0));
		return box;
	});

	pi.registerCommand("jobs", {
		description: "List, read, start, or cancel background Pi jobs",
		handler: async (args, ctx) => handleJobsCommand(pi, args, ctx),
	});

	pi.registerTool(createPiJobTool(pi));
}
