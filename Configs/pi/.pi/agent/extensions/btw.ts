import { randomUUID } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { complete, type Message, type Transport, type UserMessage } from "@mariozechner/pi-ai";
import {
	BorderedLoader,
	CURRENT_SESSION_VERSION,
	convertToLlm,
	type ExtensionAPI,
	type ExtensionCommandContext,
	type FileEntry,
	type SessionHeader,
} from "@mariozechner/pi-coding-agent";

const SIDE_CAR_TOOLS = "read,grep,find,ls,websearch,webfetch,mcp_search,mcp_inspect";
const DEFAULT_TIMEOUT_MS = 60_000;
const MAX_OUTPUT_CHARS = 18_000;
const DEFAULT_TRANSPORT: Transport = "sse";

type TemporarySessionSnapshot = {
	path: string;
	dir: string;
};

type BtwRequest = {
	question: string;
	useTools: boolean;
};

function timeoutMs(): number {
	const configured = Number(process.env.PI_BTW_TIMEOUT_MS);
	if (Number.isFinite(configured) && configured > 0) return Math.trunc(configured);
	return DEFAULT_TIMEOUT_MS;
}

function modelArg(ctxModel: { provider: string; id: string } | undefined): string | undefined {
	if (!ctxModel) return undefined;
	return `${ctxModel.provider}/${ctxModel.id}`;
}

function truncateMiddle(text: string, maxChars = MAX_OUTPUT_CHARS): string {
	if (text.length <= maxChars) return text;
	const head = Math.floor(maxChars * 0.65);
	const tail = Math.max(0, maxChars - head - 120);
	return `${text.slice(0, head)}\n\n[btw truncated ${text.length - head - tail} chars from the middle]\n\n${text.slice(text.length - tail)}`;
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

function configuredTransport(cwd: string): Transport {
	return readTransport(join(cwd, ".pi", "settings.json")) ?? readTransport(join(agentDir(), "settings.json")) ?? DEFAULT_TRANSPORT;
}

function parseRequest(args: string): BtwRequest {
	const raw = args.trim();
	if (raw.startsWith("--tools ")) return { useTools: true, question: raw.slice("--tools ".length).trim() };
	if (raw.startsWith("-t ")) return { useTools: true, question: raw.slice("-t ".length).trim() };
	return { useTools: false, question: raw };
}

function buildPrompt(request: BtwRequest): string {
	const toolLine = request.useTools
		? "You may use the provided read-only tools if they materially help."
		: "Do not use tools. Answer from the supplied session context only.";

	return `You are a throw-away read-only sidecar in the same workspace as the parent Pi session.

Answer the user's BTW question directly and briefly. ${toolLine}

Context:
- The previous messages are a snapshot of the parent Pi session's current context.
- The final user message is the BTW question.
- Use the parent session context to answer status questions like "what are we doing?".

Rules:
- Do not modify files.
- Do not run shell commands.
- Do not attempt session changes.
- Keep the final answer compact and useful.

BTW question:
${request.question}`;
}

function parentContextMessages(ctx: ExtensionCommandContext): Message[] {
	return convertToLlm(ctx.sessionManager.buildSessionContext().messages);
}

async function createTemporarySessionSnapshot(ctx: ExtensionCommandContext): Promise<TemporarySessionSnapshot> {
	const dir = await mkdtemp(join(tmpdir(), "pi-btw-"));
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

async function runBtw(pi: ExtensionAPI, ctx: ExtensionCommandContext, request: BtwRequest, signal?: AbortSignal): Promise<string> {
	if (!request.useTools) {
		if (!ctx.model) {
			return "No model selected for BTW sidecar.";
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
			{ apiKey: auth.apiKey, headers: auth.headers, signal, transport: configuredTransport(ctx.cwd) },
		);

		if (response.stopReason === "aborted") {
			return "BTW sidecar aborted.";
		}

		const text = response.content
			.filter((content): content is { type: "text"; text: string } => content.type === "text")
			.map((content) => content.text)
			.join("\n")
			.trim();

		const suffix = response.stopReason && response.stopReason !== "stop" ? `\n\n[stop reason: ${response.stopReason}]` : "";
		return truncateMiddle(`${text || "(no output)"}${suffix}`);
	}

	const model = modelArg(ctx.model);
	let snapshot: TemporarySessionSnapshot | undefined;

	try {
		snapshot = await createTemporarySessionSnapshot(ctx);
		const piArgs = ["-p", "--session", snapshot.path, "--session-dir", snapshot.dir];

		piArgs.push("--tools", SIDE_CAR_TOOLS);
		if (model) piArgs.push("--model", model);
		piArgs.push("--append-system-prompt", buildPrompt(request));
		piArgs.push(request.question);

		const result = await pi.exec("pi", piArgs, {
			cwd: ctx.cwd,
			timeout: timeoutMs(),
			signal,
		});

		const stderr = result.stderr?.trim() ?? "";
		const stdout = result.stdout?.trim() ?? "";
		const output = stdout || stderr;

		if (result.killed) {
			return truncateMiddle(output || `BTW sidecar timed out after ${timeoutMs()}ms`);
		}

		if (result.code !== 0) {
			return truncateMiddle(output || `BTW sidecar exited with code ${result.code}`);
		}

		return truncateMiddle(output || "(no output)");
	} finally {
		if (snapshot) {
			await rm(snapshot.dir, { recursive: true, force: true }).catch(() => undefined);
		}
	}
}

function formatResult(request: BtwRequest, answer: string): string {
	return `BTW sidecar result
Not added to session context.
Mode: ${request.useTools ? "read-only tools enabled" : "direct/no tools"}
Context: current parent session snapshot

Question:
${request.question}

Answer:
${answer}`;
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("btw", {
		description: "Ask a throw-away read-only sidecar question without adding it to the session context",
		handler: async (args, ctx) => {
			const request = parseRequest(args);
			if (!request.question) {
				ctx.ui.notify("Usage: /btw <question>", "warning");
				return;
			}

			if (!ctx.hasUI) {
				const answer = await runBtw(pi, ctx, request, ctx.signal);
				console.log(formatResult(request, answer));
				return;
			}

			const answer = await ctx.ui.custom<string | null>((tui, theme, _keybindings, done) => {
				const mode = request.useTools ? "read-only tools" : "direct";
				const loader = new BorderedLoader(tui, theme, `BTW sidecar (${mode}): ${request.question}`);
				loader.onAbort = () => done(null);

				runBtw(pi, ctx, request, loader.signal)
					.then(done)
					.catch((error) => {
						const message = error instanceof Error ? error.message : String(error);
						done(`BTW sidecar failed: ${message}`);
					});

				return loader;
			});

			if (answer === null) {
				ctx.ui.notify("BTW cancelled", "info");
				return;
			}

			await ctx.ui.editor("BTW sidecar result (not added to context)", formatResult(request, answer));
		},
	});
}
