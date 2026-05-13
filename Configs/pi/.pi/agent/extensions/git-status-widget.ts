import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);
const WIDGET_ID = "git-status";
const DEFAULT_INTERVAL_MS = 2_500;
const GIT_TIMEOUT_MS = 2_000;

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

function intervalMs() {
	const configured = Number(process.env.PI_GIT_STATUS_INTERVAL_MS);
	return Number.isFinite(configured) && configured >= 500 ? configured : DEFAULT_INTERVAL_MS;
}

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

async function readSnapshot(cwd: string): Promise<GitSnapshot | undefined> {
	if (!(await isGitWorktree(cwd))) return undefined;

	const status = await git(["status", "--porcelain=v1", "--branch", "--untracked-files=normal"], cwd);
	const lines = status.split("\n").filter(Boolean);
	const branchLine = lines.find((line) => line.startsWith("##")) ?? "## unknown";
	return {
		...parseBranchHeader(branchLine),
		...parseCounts(lines),
	};
}

function formatSnapshot(ctx: ExtensionContext, snapshot: GitSnapshot) {
	const theme = ctx.ui.theme;
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

async function update(ctx: ExtensionContext) {
	if (!ctx.hasUI) return;
	try {
		const snapshot = await readSnapshot(currentCwd(ctx));
		ctx.ui.setWidget(WIDGET_ID, snapshot ? [formatSnapshot(ctx, snapshot)] : undefined, { placement: "belowEditor" });
	} catch {
		ctx.ui.setWidget(WIDGET_ID, undefined);
	}
}

export default function gitStatusWidget(pi: ExtensionAPI) {
	let timer: NodeJS.Timeout | undefined;
	let refreshing = false;

	async function refresh(ctx: ExtensionContext) {
		if (refreshing) return;
		refreshing = true;
		try {
			await update(ctx);
		} finally {
			refreshing = false;
		}
	}

	pi.on("session_start", async (_event, ctx) => {
		if (timer) clearInterval(timer);
		await refresh(ctx);
		timer = setInterval(() => void refresh(ctx), intervalMs());
	});

	pi.on("input", async (_event, ctx) => {
		await refresh(ctx);
		return { action: "continue" };
	});

	pi.on("tool_execution_end", async (_event, ctx) => {
		await refresh(ctx);
	});

	pi.on("turn_end", async (_event, ctx) => {
		await refresh(ctx);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		if (timer) clearInterval(timer);
		timer = undefined;
		if (ctx.hasUI) ctx.ui.setWidget(WIDGET_ID, undefined);
	});
}
