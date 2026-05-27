/*
===============================================================================
  EXTENSION: Compact Footer
  PURPOSE: Render a two-line footer with cwd, git, speed, usage, and model.
===============================================================================
*/

// -----------------------------------------------------------------------------
// Imports
// -----------------------------------------------------------------------------

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// -----------------------------------------------------------------------------
// Constants and types
// -----------------------------------------------------------------------------

const execFileAsync = promisify(execFile);
const PAD = 1;
const CHARS_PER_TOKEN_ESTIMATE = 4;
const GIT_INTERVAL_MS = 2_500;
const GIT_TIMEOUT_MS = 2_000;

type Theme = ExtensionContext["ui"]["theme"];

type GitCounts = {
	staged: number;
	unstaged: number;
	untracked: number;
};

type GitSnapshot = GitCounts & {
	branch: string;
	ahead: number;
	behind: number;
};

type DeltaEvent = {
	type?: string;
	delta?: unknown;
};

type SpeedStatus =
	| { kind: "idle" }
	| { kind: "starting" }
	| { kind: "active"; tps: number; tokenLabel: string };

// -----------------------------------------------------------------------------
// Usage and token formatting
// -----------------------------------------------------------------------------

function fmtTokens(n: number): string {
	return n < 1000 ? `${n}` : n < 1_000_000 ? `${(n / 1000).toFixed(1)}k` : `${(n / 1_000_000).toFixed(1)}M`;
}

function computeUsageTotals(ctx: ExtensionContext) {
	let input = 0, output = 0, cacheRead = 0;
	for (const e of ctx.sessionManager.getBranch()) {
		if (e.type === "message" && e.message.role === "assistant") {
			const m = e.message as any;
			input += m.usage?.input ?? 0;
			output += m.usage?.output ?? 0;
			cacheRead += m.usage?.cacheRead ?? 0;
		}
	}
	return { input, output, cacheRead };
}

// -----------------------------------------------------------------------------
// Git status collection
// -----------------------------------------------------------------------------

function currentCwd(ctx: ExtensionContext) {
	return ctx.sessionManager.getCwd?.() ?? ctx.cwd;
}

async function git(args: string[], cwd: string) {
	const { stdout } = await execFileAsync("git", args, {
		cwd,
		timeout: GIT_TIMEOUT_MS,
		maxBuffer: 1024 * 1024,
	});
	return stdout.trimEnd();
}

async function isGitWorktree(cwd: string) {
	try {
		return (await git(["rev-parse", "--is-inside-work-tree"], cwd)) === "true";
	} catch {
		return false;
	}
}

function parseBranchHeader(line: string) {
	const rest = line.replace(/^##\s+/, "").trim();
	const branchPart = rest.includes("...") ? rest.slice(0, rest.indexOf("...")) : rest.replace(/\s+\[.*\]$/, "");
	const noCommitMatch = branchPart.match(/^No commits yet on (.+)$/);
	const branch = (noCommitMatch?.[1] ?? branchPart).trim() || "unknown";
	const ahead = Number(line.match(/ahead (\d+)/)?.[1] ?? 0);
	const behind = Number(line.match(/behind (\d+)/)?.[1] ?? 0);
	return { branch, ahead, behind };
}

function parseCounts(lines: string[]): GitCounts {
	let staged = 0;
	let unstaged = 0;
	let untracked = 0;

	for (const line of lines) {
		if (!line || line.startsWith("##")) continue;
		const x = line[0] ?? " ";
		const y = line[1] ?? " ";
		if (x === "?" && y === "?") {
			untracked += 1;
			continue;
		}
		if (x !== " " && x !== "?") staged += 1;
		if (y !== " " && y !== "?") unstaged += 1;
	}

	return { staged, unstaged, untracked };
}

async function readGitSnapshot(cwd: string): Promise<GitSnapshot | undefined> {
	if (!(await isGitWorktree(cwd))) return undefined;

	const status = await git(["status", "--porcelain=v1", "--branch", "--untracked-files=normal"], cwd);
	const lines = status.split("\n").filter(Boolean);
	const branchLine = lines.find((line) => line.startsWith("##")) ?? "## unknown";
	return {
		...parseBranchHeader(branchLine),
		...parseCounts(lines),
	};
}

function formatGitSnapshot(theme: Theme, snapshot: GitSnapshot) {
	const dirty = snapshot.staged + snapshot.unstaged + snapshot.untracked;
	const branch = theme.fg(dirty ? "warning" : "success", ` ${snapshot.branch}`);
	const sync = [
		snapshot.ahead ? `↑${snapshot.ahead}` : "",
		snapshot.behind ? `↓${snapshot.behind}` : "",
	].filter(Boolean).join(" ");
	const parts = [branch];
	if (sync) parts.push(theme.fg("accent", sync));
	if (dirty === 0) {
		parts.push(theme.fg("dim", "clean"));
	} else {
		if (snapshot.staged) parts.push(theme.fg("success", `+${snapshot.staged}`));
		if (snapshot.unstaged) parts.push(theme.fg("warning", `~${snapshot.unstaged}`));
		if (snapshot.untracked) parts.push(theme.fg("muted", `?${snapshot.untracked}`));
	}
	return `git ${parts.join(" ")}`;
}

// -----------------------------------------------------------------------------
// Streaming speed tracking
// -----------------------------------------------------------------------------

function outputTokens(message: { usage?: { output?: number } }) {
	const value = message.usage?.output;
	return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function streamDelta(event: unknown) {
	if (!event || typeof event !== "object") return "";
	const candidate = event as DeltaEvent;
	if (
		candidate.type !== "text_delta" &&
		candidate.type !== "thinking_delta" &&
		candidate.type !== "toolcall_delta"
	) {
		return "";
	}
	return typeof candidate.delta === "string" ? candidate.delta : "";
}

function formatSpeed(tokens: number, startedAt: number | undefined) {
	if (!startedAt || tokens <= 0) return undefined;
	const seconds = Math.max((Date.now() - startedAt) / 1000, 0.001);
	return { tps: Math.round(tokens / seconds), seconds };
}

function renderSpeedStatus(theme: Theme, status: SpeedStatus) {
	if (status.kind === "starting") return theme.fg("dim", "speed starting");
	if (status.kind === "active") return `${theme.fg("accent", `${status.tps} tok/s`)} ${theme.fg("dim", status.tokenLabel)}`;
	return theme.fg("dim", "speed idle");
}

// -----------------------------------------------------------------------------
// Extension registration
// -----------------------------------------------------------------------------

export default function compactFooter(pi: ExtensionAPI) {
	let requestRender: (() => void) | undefined;
	let gitTimer: NodeJS.Timeout | undefined;
	let gitRefreshing = false;
	let gitSnapshot: GitSnapshot | undefined;
	let speedStatus: SpeedStatus = { kind: "idle" };
	let messageStartedAt: number | undefined;
	let streamStartedAt: number | undefined;
	let estimatedTokens = 0;
	let runOutputTokens = 0;
	let runStreamMs = 0;

	async function refreshGit(ctx: ExtensionContext) {
		if (gitRefreshing) return;
		gitRefreshing = true;
		try {
			const cwd = currentCwd(ctx);
			gitSnapshot = await readGitSnapshot(cwd);
			requestRender?.();
		} catch (error: any) {
			gitSnapshot = undefined;
			requestRender?.();
			if (error?.message?.includes("stale") && gitTimer) {
				clearInterval(gitTimer);
				gitTimer = undefined;
			}
		} finally {
			gitRefreshing = false;
		}
	}

	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;

		if (gitTimer) clearInterval(gitTimer);
		void refreshGit(ctx);
		gitTimer = setInterval(() => void refreshGit(ctx), GIT_INTERVAL_MS);

		ctx.ui.setFooter((tui, theme, footerData) => {
			requestRender = () => tui.requestRender();
			const unsubBranch = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose() {
					unsubBranch();
					requestRender = undefined;
				},
				invalidate() {},
				render(width: number): string[] {
					const innerWidth = Math.max(1, width - PAD * 2);

					// Row 1: cwd (muted left) | git + speed (colored right)
					const cwdStr = ctx.sessionManager.getCwd() || ctx.cwd;
					const cwdColored = theme.fg("muted", cwdStr);
					const gitRaw = gitSnapshot ? formatGitSnapshot(theme, gitSnapshot) : "";
					const speedRaw = renderSpeedStatus(theme, speedStatus);
					const right1Colored = [gitRaw, speedRaw].filter(Boolean).join("  ");
					const row1 =
						" ".repeat(PAD) +
						truncateToWidth(
							cwdColored +
								" ".repeat(
									Math.max(1, innerWidth - visibleWidth(cwdColored) - visibleWidth(right1Colored))
								) +
								right1Colored,
							innerWidth
						);

					// Row 2: usage (muted with accent percent/dim total) | model (muted with accent thinking)
					const { input, output, cacheRead } = computeUsageTotals(ctx);
					const usageCtx = ctx.getContextUsage();

					let usageColored = "";
					if (usageCtx && usageCtx.tokens != null) {
						const inputStr = fmtTokens(input);
						const outputStr = fmtTokens(output);
						const cacheReadStr = fmtTokens(cacheRead);
						const percentStr = `${usageCtx.percent?.toFixed(1)}%`;
						const totalStr = fmtTokens(usageCtx.contextWindow);

						usageColored =
							theme.fg("muted", `↑${inputStr} ↓${outputStr} R${cacheReadStr} `) +
							theme.fg("accent", percentStr) +
							theme.fg("muted", "/") +
							theme.fg("dim", totalStr) +
							theme.fg("muted", " (auto)");
					}

					const model = ctx.model;
					const thinking = pi.getThinkingLevel();
					const modelPrefix = model
						? theme.fg("muted", `(${model.provider}) ${model.id}`)
						: theme.fg("muted", "no-model");
					const thinkingColored =
						thinking && thinking !== "off"
							? theme.fg("muted", " • ") + theme.fg("accent", thinking)
							: "";
					const modelColored = modelPrefix + thinkingColored;

					const row2 =
						" ".repeat(PAD) +
						truncateToWidth(
							usageColored +
								" ".repeat(
									Math.max(1, innerWidth - visibleWidth(usageColored) - visibleWidth(modelColored))
								) +
								modelColored,
							innerWidth
						);

					return [row1, row2];
				},
			};
		});
	});

	pi.on("agent_start", async () => {
		runOutputTokens = 0;
		runStreamMs = 0;
		messageStartedAt = undefined;
		streamStartedAt = undefined;
		estimatedTokens = 0;
		speedStatus = { kind: "starting" };
		requestRender?.();
	});

	pi.on("message_start", async (event) => {
		if (event.message.role !== "assistant") return;
		messageStartedAt = Date.now();
		streamStartedAt = undefined;
		estimatedTokens = 0;
	});

	pi.on("message_update", async (event, ctx) => {
		if (event.message.role !== "assistant") return;

		const delta = streamDelta(event.assistantMessageEvent);
		if (delta) {
			streamStartedAt ??= Date.now();
			estimatedTokens += delta.length / CHARS_PER_TOKEN_ESTIMATE;

			const officialTokens = outputTokens(event.message);
			const tokens = officialTokens > 0 ? officialTokens : Math.round(estimatedTokens);
			const speed = formatSpeed(tokens, streamStartedAt);
			if (speed) {
				const tokenLabel = officialTokens > 0 ? `${officialTokens} tok` : `~${tokens} tok`;
				speedStatus = { kind: "active", tps: speed.tps, tokenLabel };
			}
		}

		requestRender?.();
	});

	pi.on("message_end", async (event) => {
		if (event.message.role !== "assistant") return;

		const officialTokens = outputTokens(event.message);
		const tokens = officialTokens > 0 ? officialTokens : Math.round(estimatedTokens);
		const startedAt = streamStartedAt ?? messageStartedAt;
		if (tokens > 0 && startedAt) {
			runOutputTokens += tokens;
			runStreamMs += Math.max(0, Date.now() - startedAt);
		}

		messageStartedAt = undefined;
		streamStartedAt = undefined;
		estimatedTokens = 0;
		requestRender?.();
	});

	pi.on("agent_end", async () => {
		const seconds = runStreamMs / 1000;
		const tps = runOutputTokens > 0 && seconds > 0 ? Math.round(runOutputTokens / seconds) : 0;
		speedStatus = tps > 0
			? { kind: "active", tps, tokenLabel: `${runOutputTokens} tok` }
			: { kind: "idle" };
		requestRender?.();
	});

	pi.on("model_select", async () => requestRender?.());
	pi.on("thinking_level_select", async () => requestRender?.());
	pi.on("input", async (_event, ctx) => {
		void refreshGit(ctx);
		requestRender?.();
	});
	pi.on("tool_execution_end", async (_event, ctx) => {
		void refreshGit(ctx);
		requestRender?.();
	});
	pi.on("turn_end", async (_event, ctx) => {
		void refreshGit(ctx);
		requestRender?.();
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (gitTimer) clearInterval(gitTimer);
		gitTimer = undefined;
		gitSnapshot = undefined;
		speedStatus = { kind: "idle" };
		if (ctx.hasUI) ctx.ui.setFooter(undefined);
		requestRender = undefined;
	});
}
