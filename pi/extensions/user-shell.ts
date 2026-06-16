/*
===============================================================================
  EXTENSION: User Shell
  PURPOSE: Route user shell commands, inline !{} expansion, bash, and pwsh.
===============================================================================
*/

// -----------------------------------------------------------------------------
// Imports
// -----------------------------------------------------------------------------

import { Type } from "@earendil-works/pi-ai";
import { accessSync, constants } from "node:fs";
import { spawn } from "node:child_process";
import { basename, delimiter, join } from "node:path";
import {
	createBashToolDefinition,
	createLocalBashOperations,
	type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

// -----------------------------------------------------------------------------
// Shell model and constants
// -----------------------------------------------------------------------------

type ShellKind = "fish" | "zsh" | "bash" | "pwsh" | "sh";

type UserShell = {
	path: string;
	name: string;
	kind: ShellKind;
};

const USER_BASH_PROMPT_MARKER = "User shell commands (Pi !/!! user_bash and inline !{...}) run through the user's default shell";
const BASH_TOOL_COMMAND_PREFIX = 'if command -v mise >/dev/null 2>&1; then eval "$(mise env -s bash)"; fi';
const BASH_TOOL_PROMPT_MARKER = "Mise tool hot-reload is enabled for Pi bash commands.";
const BASH_TOOL_PROMPT_NOTE = `${BASH_TOOL_PROMPT_MARKER} Before each bash execution, Pi refreshes the shell environment with \`mise env -s bash\` for the command cwd, so newly installed or changed mise tools are available without restarting the session. Use bash normally; do not hard-code mise install paths.`;
const INLINE_BANG_PATTERN = /!\{([^}]+)\}/g;
const INLINE_BANG_TIMEOUT_MS = 30000;
const INLINE_BANG_MAX_OUTPUT_PREVIEW = 60;
const MAX_POWERSHELL_OUTPUT_BYTES = 50 * 1024;
const DEFAULT_POWERSHELL_TIMEOUT_MS = 60_000;
const MAX_POWERSHELL_TIMEOUT_MS = 300_000;

type InlineBangExpansion = {
	command: string;
	output: string;
	error?: string;
	exitCode?: number;
};

// -----------------------------------------------------------------------------
// Shell discovery and command wrapping
// -----------------------------------------------------------------------------

function shellQuote(value: string): string {
	return `'${value.replaceAll("'", `'\\''`)}'`;
}

function isExecutable(path: string | undefined): path is string {
	if (!path) return false;

	try {
		accessSync(path, constants.X_OK);
		return true;
	} catch {
		return false;
	}
}

function shellName(path: string | undefined): string {
	return basename(path ?? "").toLowerCase();
}

function shellKind(path: string): ShellKind {
	const name = shellName(path);
	if (name === "fish" || name === "fsh") return "fish";
	if (name === "zsh") return "zsh";
	if (name === "bash") return "bash";
	if (name === "pwsh" || name === "powershell" || name === "powershell.exe" || name === "pwsh.exe") return "pwsh";
	return "sh";
}

function firstExecutable(paths: string[]): string | undefined {
	return paths.find(isExecutable);
}

function findExecutableOnPath(names: string[]): string | undefined {
	const pathDirs = (process.env.PATH ?? "").split(delimiter).filter(Boolean);
	const extensions = process.platform === "win32"
		? (process.env.PATHEXT ?? ".EXE;.CMD;.BAT;.COM").split(";").filter(Boolean)
		: [""];

	for (const dir of pathDirs) {
		for (const name of names) {
			const candidates = process.platform === "win32" && !name.includes(".")
				? extensions.map((extension) => join(dir, `${name}${extension.toLowerCase()}`)).concat(extensions.map((extension) => join(dir, `${name}${extension.toUpperCase()}`)))
				: [join(dir, name)];
			const match = firstExecutable(candidates);
			if (match) return match;
		}
	}

	return undefined;
}

function findUnixShellOnPath(): string | undefined {
	return findExecutableOnPath(["bash", "zsh", "fish", "fsh", "sh"]);
}

function findBashOnPath(): string | undefined {
	return findExecutableOnPath(["bash"]);
}

function findBashShellPath(): string | undefined {
	const pathBash = findBashOnPath();
	if (pathBash) return pathBash;

	return firstExecutable([
		"/opt/homebrew/bin/bash",
		"/usr/local/bin/bash",
		"/usr/bin/bash",
		"/bin/bash",
	]);
}

function defaultShellPath(): string {
	const explicit = process.env.PI_USER_SHELL ?? process.env.PI_USER_BASH_SHELL;
	if (explicit) return explicit;

	if (process.platform === "win32") {
		return findUnixShellOnPath() ?? process.env.PWSH ?? process.env.SHELL ?? findPowerShellExecutable();
	}

	if (process.env.SHELL) return process.env.SHELL;

	if (process.platform === "darwin") {
		return firstExecutable([
			"/bin/zsh",
			"/opt/homebrew/bin/fish",
			"/usr/local/bin/fish",
			"/bin/bash",
		]) ?? "/bin/zsh";
	}

	return firstExecutable([
		"/usr/bin/zsh",
		"/bin/zsh",
		"/usr/bin/fish",
		"/bin/fish",
		"/bin/bash",
		"/bin/sh",
	]) ?? "/bin/sh";
}

function defaultShell(): UserShell {
	const path = defaultShellPath();
	return {
		path,
		name: shellName(path) || path,
		kind: shellKind(path),
	};
}

function misePrefix(kind: ShellKind): string {
	if (kind === "fish") return "if command -q mise; mise env -s fish | source; end";
	if (kind === "pwsh") return "if (Get-Command mise -ErrorAction SilentlyContinue) { mise env -s pwsh | Invoke-Expression }";
	if (kind === "zsh") return "if command -v mise >/dev/null 2>&1; then eval \"$(mise env -s zsh)\"; fi";
	if (kind === "bash") return "if command -v mise >/dev/null 2>&1; then eval \"$(mise env -s bash)\"; fi";
	return "if command -v mise >/dev/null 2>&1; then eval \"$(mise env -s sh)\"; fi";
}

function runInUserShell(command: string, shell: UserShell): string {
	if (shell.kind === "fish") {
		return [
			"exec",
			shellQuote(shell.path),
			"-C",
			shellQuote(misePrefix(shell.kind)),
			"-c",
			shellQuote(command),
		].join(" ");
	}

	if (shell.kind === "pwsh") {
		return [
			"exec",
			shellQuote(shell.path),
			"-NoLogo",
			"-Command",
			shellQuote(`${misePrefix(shell.kind)}; ${command}`),
		].join(" ");
	}

	const flags = shell.kind === "zsh" || shell.kind === "bash" ? "-lic" : "-lc";
	return [
		"exec",
		shellQuote(shell.path),
		flags,
		shellQuote(`${misePrefix(shell.kind)}\n${command}`),
	].join(" ");
}

// -----------------------------------------------------------------------------
// PowerShell model tool
// -----------------------------------------------------------------------------

function powerShellCandidates(): string[] {
	const windowsRoot = process.env.SystemRoot ?? process.env.WINDIR ?? "C:\\Windows";
	return [
		process.env.PWSH,
		"C:\\Program Files\\PowerShell\\7\\pwsh.exe",
		"C:\\Program Files (x86)\\PowerShell\\7\\pwsh.exe",
		`${windowsRoot}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe`,
		`${windowsRoot}\\SysWOW64\\WindowsPowerShell\\v1.0\\powershell.exe`,
		"pwsh",
		"powershell.exe",
		"powershell",
	].filter((candidate): candidate is string => Boolean(candidate));
}

function findPowerShellExecutable(): string {
	for (const candidate of powerShellCandidates()) {
		if (candidate.includes("\\") && isExecutable(candidate)) return candidate;
	}
	return process.platform === "win32" ? "powershell.exe" : "pwsh";
}

function withPowerShellMise(command: string): string {
	return `${misePrefix("pwsh")}; ${command}`;
}

async function runPowerShell(command: string, cwd: string, timeoutMs: number, signal?: AbortSignal): Promise<{ output: string; exitCode: number; timedOut: boolean; truncated: boolean; executable: string }> {
	const exe = findPowerShellExecutable();

	return new Promise((resolve) => {
		const chunks: Buffer[] = [];
		let totalBytes = 0;
		let truncated = false;
		let timedOut = false;
		let settled = false;
		let killTimer: NodeJS.Timeout | undefined;

		const child = spawn(exe, ["-NoProfile", "-NonInteractive", "-Command", withPowerShellMise(command)], {
			cwd,
			windowsHide: true,
			env: process.env,
		});

		const settle = (exitCode: number) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			if (killTimer) clearTimeout(killTimer);
			signal?.removeEventListener("abort", onAbort);

			resolve({
				output: Buffer.concat(chunks).toString("utf8"),
				exitCode,
				timedOut,
				truncated,
				executable: exe,
			});
		};

		const stopChild = () => {
			child.kill("SIGTERM");
			killTimer = setTimeout(() => child.kill("SIGKILL"), 2000);
		};

		const timer = setTimeout(() => {
			timedOut = true;
			stopChild();
		}, timeoutMs);

		const onAbort = () => stopChild();
		signal?.addEventListener("abort", onAbort, { once: true });

		const onData = (chunk: Buffer) => {
			if (truncated) return;
			const remaining = MAX_POWERSHELL_OUTPUT_BYTES - totalBytes;
			if (chunk.length >= remaining) {
				chunks.push(chunk.subarray(0, Math.max(0, remaining)));
				totalBytes += Math.max(0, remaining);
				truncated = true;
				return;
			}

			chunks.push(chunk);
			totalBytes += chunk.length;
		};

		child.stdout.on("data", onData);
		child.stderr.on("data", onData);
		child.on("error", (error) => {
			chunks.push(Buffer.from(`\n[PowerShell spawn error (${exe}): ${error.message}]`));
			settle(1);
		});
		child.on("close", (code) => settle(code ?? 1));
	});
}

function registerPowerShellTool(pi: ExtensionAPI, bashToolAvailable: boolean) {
	pi.registerTool({
		name: "pwsh",
		label: "PowerShell",
		description: "Execute a PowerShell command on Windows. Prefers PowerShell 7 (pwsh.exe) and falls back to Windows PowerShell 5.1 (powershell.exe). Use this tool for Windows-native shell operations, PowerShell scripts, file manipulation, environment queries, and system commands. Returns combined stdout+stderr and the exit code.",
		promptSnippet: bashToolAvailable
			? "Execute a Windows PowerShell command when PowerShell syntax or Windows-native shell behaviour is needed"
			: "Execute a PowerShell command on Windows; use this as the primary shell because no bash tool is available",
		promptGuidelines: bashToolAvailable
			? [
				"A bash tool is available on this Windows system, so prefer bash for normal cross-platform shell work unless PowerShell syntax or Windows-native behaviour is specifically useful.",
				"Use pwsh for PowerShell scripts, Windows-native environment queries, registry/service operations, or commands that are clearer in PowerShell.",
				"PowerShell commands refresh mise with `mise env -s pwsh` before execution when mise is installed.",
				"In pwsh commands, use PowerShell syntax: Get-ChildItem (ls), Select-String (grep), $env:VAR for environment variables, etc.",
			]
			: [
				"No bash tool is available on this Windows system, so use pwsh for shell commands.",
				"Use pwsh for directory listing, file operations, running scripts, checking environment variables, and any other shell tasks.",
				"PowerShell commands refresh mise with `mise env -s pwsh` before execution when mise is installed.",
				"In pwsh commands, use PowerShell syntax: Get-ChildItem (ls), Select-String (grep), $env:VAR for environment variables, etc.",
				"Chain commands with semicolons or newlines in a single pwsh call rather than making multiple calls.",
			],
		parameters: Type.Object({
			command: Type.String({
				description: "PowerShell command or script block to execute. Use syntax compatible with PowerShell 5.1 when possible (Get-ChildItem, Select-String, $env:VAR, etc.).",
			}),
			timeout: Type.Optional(Type.Number({
				description: "Maximum seconds to wait before killing the process. Default 60, max 300.",
				minimum: 1,
				maximum: 300,
			})),
		}),
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const timeoutSeconds = Math.max(1, Math.min(params.timeout ?? DEFAULT_POWERSHELL_TIMEOUT_MS / 1000, MAX_POWERSHELL_TIMEOUT_MS / 1000));
			onUpdate?.({
				content: [{ type: "text", text: `Running: ${params.command}` }],
				details: {},
			});

			const { output, exitCode, timedOut, truncated, executable } = await runPowerShell(params.command, ctx.cwd, timeoutSeconds * 1000, signal);
			const notes: string[] = [];
			if (timedOut) notes.push(`[Process timed out after ${timeoutSeconds}s and was killed]`);
			if (signal?.aborted) notes.push("[Cancelled by user]");
			if (truncated) notes.push("[Output truncated at 50 KB; narrow your command]");
			if (exitCode !== 0) notes.push(`[Exit code: ${exitCode}]`);

			const text = [output.trim(), ...notes].filter(Boolean).join("\n") || "(no output)";
			return {
				content: [{ type: "text", text }],
				details: { exitCode, timedOut, truncated, command: params.command, executable },
			};
		},
	});
}

// -----------------------------------------------------------------------------
// Extension registration
// -----------------------------------------------------------------------------

export default function userShell(pi: ExtensionAPI) {
	const local = createLocalBashOperations();
	const shell = defaultShell();
	const bashToolShellPath = findBashShellPath();
	const promptNote = `${USER_BASH_PROMPT_MARKER} (${shell.name}) and refresh mise with shell-compatible \`mise env -s ${shell.kind}\` immediately before execution.`;

	if (process.platform === "win32") {
		registerPowerShellTool(pi, Boolean(bashToolShellPath));
	}

	if (bashToolShellPath) {
		pi.on("session_start", (_event, ctx) => {
			const bashTool = createBashToolDefinition(ctx.cwd, {
				commandPrefix: BASH_TOOL_COMMAND_PREFIX,
				shellPath: bashToolShellPath,
			});

			pi.registerTool({
				...bashTool,
				description: `${bashTool.description}\n\nMise hot-reload: before each bash execution, Pi refreshes the environment with \`mise env -s bash\` for the command cwd.`,
				promptGuidelines: [
					"Bash commands run with mise hot-reload: Pi refreshes the environment with `mise env -s bash` before each bash execution.",
				],
			});
		});
	}

	pi.on("user_bash", () => {
		return {
			operations: {
				exec(command, cwd, options) {
					return local.exec(runInUserShell(command, shell), cwd, options);
				},
			},
		};
	});

	pi.on("input", async (event, ctx) => {
		const text = event.text;
		const trimmed = text.trimStart();
		if (trimmed.startsWith("!") && !trimmed.startsWith("!{")) return { action: "continue" };

		INLINE_BANG_PATTERN.lastIndex = 0;
		if (!INLINE_BANG_PATTERN.test(text)) return { action: "continue" };

		INLINE_BANG_PATTERN.lastIndex = 0;
		const matches: Array<{ full: string; command: string }> = [];
		let match = INLINE_BANG_PATTERN.exec(text);
		while (match) {
			matches.push({ full: match[0], command: match[1] });
			match = INLINE_BANG_PATTERN.exec(text);
		}

		let result = text;
		const expansions: InlineBangExpansion[] = [];

		for (const { full, command } of matches) {
			try {
				const bashResult = await local.exec(runInUserShell(command, shell), ctx.cwd, {
					timeout: INLINE_BANG_TIMEOUT_MS,
				});
				const output = (bashResult.stdout || bashResult.stderr || "").trim();

				expansions.push({
					command,
					output,
					exitCode: bashResult.code,
					error: bashResult.code !== 0 && bashResult.stderr ? `exit code ${bashResult.code}` : undefined,
				});
				result = result.replace(full, output);
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				expansions.push({ command, output: "", error: message });
				result = result.replace(full, `[bang error: ${message}]`);
			}
		}

		if (ctx.hasUI && expansions.length > 0) {
			const summary = expansions
				.map((expansion) => {
					const status = expansion.error ? ` warning ${expansion.error}` : "";
					const preview = expansion.output.length > INLINE_BANG_MAX_OUTPUT_PREVIEW
						? `${expansion.output.slice(0, INLINE_BANG_MAX_OUTPUT_PREVIEW)}...`
						: expansion.output;
					return `!{${expansion.command}}${status} -> "${preview}"`;
				})
				.join("\n");

			ctx.ui.notify(`Bang: expanded ${expansions.length} command(s)\n${summary}`, "info");
		}

		return { action: "transform", text: result, images: event.images };
	});

	pi.on("before_agent_start", (event) => {
		const notes = [];
		if (!event.systemPrompt.includes(USER_BASH_PROMPT_MARKER)) notes.push(promptNote);
		if (bashToolShellPath && !event.systemPrompt.includes(BASH_TOOL_PROMPT_MARKER)) notes.push(BASH_TOOL_PROMPT_NOTE);
		if (notes.length === 0) return;

		return {
			systemPrompt: `${event.systemPrompt}\n\n${notes.join("\n\n")}`,
		};
	});
}
