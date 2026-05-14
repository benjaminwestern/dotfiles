import { randomUUID } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { complete, type Message, type Transport, type UserMessage } from "@earendil-works/pi-ai";
import {
	BorderedLoader,
	CURRENT_SESSION_VERSION,
	convertToLlm,
	type ExtensionAPI,
	type ExtensionCommandContext,
	type FileEntry,
	type SessionHeader,
} from "@earendil-works/pi-coding-agent";
import { loadExtensionConfig } from "./common-core/config.js";

const SIDE_CONFIG_FILE = "side.json";
const DEFAULT_SIDE_CAR_TOOLS = ["read", "grep", "find", "ls", "websearch", "webfetch", "mcp_search", "mcp_inspect"];
const DEFAULT_TIMEOUT_MS = 60_000;
const DEFAULT_MAX_OUTPUT_CHARS = 18_000;
const DEFAULT_TRANSPORT: Transport = "sse";

type TemporarySessionSnapshot = {
	path: string;
	dir: string;
};

type SideRequest = {
	question: string;
	useTools: boolean;
};

type SideConfig = Record<string, unknown> & {
	timeoutMs?: number;
	maxOutputChars?: number;
	tools?: string[];
	transport?: Transport;
};

const DEFAULT_SIDE_CONFIG: SideConfig = {
	timeoutMs: DEFAULT_TIMEOUT_MS,
	maxOutputChars: DEFAULT_MAX_OUTPUT_CHARS,
	tools: DEFAULT_SIDE_CAR_TOOLS,
};

function sideConfig(cwd: string): SideConfig {
	return loadExtensionConfig<SideConfig>(SIDE_CONFIG_FILE, cwd, DEFAULT_SIDE_CONFIG).config;
}

function positiveNumber(value: unknown): number | undefined {
	const number = Number(value);
	return Number.isFinite(number) && number > 0 ? Math.trunc(number) : undefined;
}

function timeoutMs(config: SideConfig): number {
	const envOverride = positiveNumber(process.env.PI_SIDE_TIMEOUT_MS);
	return envOverride ?? positiveNumber(config.timeoutMs) ?? DEFAULT_TIMEOUT_MS;
}

function maxOutputChars(config: SideConfig): number {
	return positiveNumber(config.maxOutputChars) ?? DEFAULT_MAX_OUTPUT_CHARS;
}

function sideCarTools(config: SideConfig): string {
	const tools = Array.isArray(config.tools) ? config.tools.filter((tool): tool is string => typeof tool === "string" && tool.trim().length > 0) : DEFAULT_SIDE_CAR_TOOLS;
	return tools.length ? tools.join(",") : DEFAULT_SIDE_CAR_TOOLS.join(",");
}

function modelArg(ctxModel: { provider: string; id: string } | undefined): string | undefined {
	if (!ctxModel) return undefined;
	return `${ctxModel.provider}/${ctxModel.id}`;
}

function truncateMiddle(text: string, maxChars: number): string {
	if (text.length <= maxChars) return text;
	const head = Math.floor(maxChars * 0.65);
	const tail = Math.max(0, maxChars - head - 120);
	return `${text.slice(0, head)}\n\n[side truncated ${text.length - head - tail} chars from the middle]\n\n${text.slice(text.length - tail)}`;
}

function isTransport(value: unknown): value is Transport {
	return value === "sse" || value === "websocket" || value === "websocket-cached" || value === "auto";
}

function readTransport(path: string): Transport | undefined {
	try {
		if (!existsSync(path)) return undefined;
		const settings = JSON.parse(readFileSync(path, "utf8")) as { transport?: unknown };
		return isTransport(settings.transport) ? settings.transport : undefined;
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

function configuredTransport(cwd: string, config: SideConfig): Transport {
	return isTransport(config.transport) ? config.transport : readTransport(join(cwd, ".pi", "settings.json")) ?? readTransport(join(agentDir(), "settings.json")) ?? DEFAULT_TRANSPORT;
}

function parseRequest(args: string): SideRequest {
	const raw = args.trim();
	if (raw.startsWith("--tools ")) return { useTools: true, question: raw.slice("--tools ".length).trim() };
	if (raw.startsWith("-t ")) return { useTools: true, question: raw.slice("-t ".length).trim() };
	return { useTools: false, question: raw };
}

function buildPrompt(request: SideRequest): string {
	const toolLine = request.useTools
		? "You may use the provided read-only tools if they materially help."
		: "Do not use tools. Answer from the supplied session context only.";

	return `You are a throw-away side channel in the same workspace as the parent Pi session.

Answer the user's side question directly and briefly. ${toolLine}

Context:
- The previous messages are a snapshot of the parent Pi session's current context.
- The final user message is the side question.
- Use the parent session context to answer status questions like "what are we doing?".

Rules:
- Do not modify files.
- Do not run shell commands.
- Do not attempt session changes.
- Keep the final answer compact and useful.

Side question:
${request.question}`;
}

function parentContextMessages(ctx: ExtensionCommandContext): Message[] {
	return convertToLlm(ctx.sessionManager.buildSessionContext().messages);
}

async function createTemporarySessionSnapshot(ctx: ExtensionCommandContext): Promise<TemporarySessionSnapshot> {
	const dir = await mkdtemp(join(tmpdir(), "pi-side-"));
	const path = join(dir, "session.jsonl");
	const parentHeader = ctx.sessionManager.getHeader();
	const header: SessionHeader = {
		type: "session",
		version: CURRENT_SESSION_VERSION,
		id: randomUUID(),
		timestamp: new Date().toISOString(),
		cwd: parentHeader?.cwd ?? ctx.cwd,
		parentSession: ctx.sessionManager.getSessionFile() ?? parentHeader?.parentSession,
	};
	const entries = ctx.sessionManager.getBranch();
	const fileEntries: FileEntry[] = [header, ...entries];
	await writeFile(path, `${fileEntries.map((entry) => JSON.stringify(entry)).join("\n")}\n`, "utf8");
	return { path, dir };
}

async function runSide(pi: ExtensionAPI, ctx: ExtensionCommandContext, request: SideRequest, signal?: AbortSignal): Promise<string> {
	const config = sideConfig(ctx.cwd);
	const outputLimit = maxOutputChars(config);

	if (!request.useTools) {
		if (!ctx.model) {
			return "No model selected for Side turn.";
		}

		const auth = await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model);
		if (!auth.ok || !auth.apiKey) {
			return auth.ok ? `No API key for ${ctx.model.provider}` : auth.error;
		}

		const userMessage: UserMessage = {
			role: "user",
			content: [{ type: "text", text: request.question }],
			timestamp: Date.now(),
		};
		const messages = [...parentContextMessages(ctx), userMessage];

		const response = await complete(
			ctx.model,
			{ systemPrompt: buildPrompt(request), messages },
			{ apiKey: auth.apiKey, headers: auth.headers, signal, transport: configuredTransport(ctx.cwd, config) },
		);

		if (response.stopReason === "aborted") {
			return "Side turn aborted.";
		}

		const text = response.content
			.filter((content): content is { type: "text"; text: string } => content.type === "text")
			.map((content) => content.text)
			.join("\n")
			.trim();

		const suffix = response.stopReason && response.stopReason !== "stop" ? `\n\n[stop reason: ${response.stopReason}]` : "";
		return truncateMiddle(`${text || "(no output)"}${suffix}`, outputLimit);
	}

	const model = modelArg(ctx.model);
	let snapshot: TemporarySessionSnapshot | undefined;

	try {
		snapshot = await createTemporarySessionSnapshot(ctx);
		const piArgs = ["-p", "--session", snapshot.path, "--session-dir", snapshot.dir];

		piArgs.push("--tools", sideCarTools(config));
		if (model) piArgs.push("--model", model);
		piArgs.push("--append-system-prompt", buildPrompt(request));
		piArgs.push(request.question);

		const result = await pi.exec("pi", piArgs, {
			cwd: ctx.cwd,
			timeout: timeoutMs(config),
			signal,
		});

		const stderr = result.stderr?.trim() ?? "";
		const stdout = result.stdout?.trim() ?? "";
		const output = stdout || stderr;

		if (result.killed) {
			return truncateMiddle(output || `Side turn timed out after ${timeoutMs(config)}ms`, outputLimit);
		}

		if (result.code !== 0) {
			return truncateMiddle(output || `Side turn exited with code ${result.code}`, outputLimit);
		}

		return truncateMiddle(output || "(no output)", outputLimit);
	} finally {
		if (snapshot) {
			await rm(snapshot.dir, { recursive: true, force: true }).catch(() => undefined);
		}
	}
}

function formatResult(request: SideRequest, answer: string): string {
	return `Side result
Not added to the main session context.
Mode: ${request.useTools ? "read-only tools enabled" : "direct/no tools"}
Context: current main session snapshot

Question:
${request.question}

Answer:
${answer}`;
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("side", {
		description: "Ask a one-shot side question without adding it to the main session context",
		handler: async (args, ctx) => {
			const request = parseRequest(args);
			if (!request.question) {
				ctx.ui.notify("Usage: /side [-t|--tools] <question>", "warning");
				return;
			}

			if (!ctx.hasUI) {
				const answer = await runSide(pi, ctx, request, ctx.signal);
				console.log(formatResult(request, answer));
				return;
			}

			const answer = await ctx.ui.custom<string | null>((tui, theme, _keybindings, done) => {
				const mode = request.useTools ? "read-only tools" : "direct";
				const loader = new BorderedLoader(tui, theme, `Side turn (${mode}): ${request.question}`);
				loader.onAbort = () => done(null);

				runSide(pi, ctx, request, loader.signal)
					.then(done)
					.catch((error) => {
						const message = error instanceof Error ? error.message : String(error);
						done(`Side turn failed: ${message}`);
					});

				return loader;
			});

			if (answer === null) {
				ctx.ui.notify("Side cancelled", "info");
				return;
			}

			await ctx.ui.editor("Side result (not added to main context)", formatResult(request, answer));
		},
	});
}
