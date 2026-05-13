import path from "node:path";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";

const GIT_TIMEOUT_MS = 30_000;
const PUSH_TIMEOUT_MS = 120_000;
const MAX_SUBJECT_LENGTH = 72;

type StagedFile = {
	status: string;
	path: string;
	oldPath?: string;
};

type CommitPlan = {
	subject: string;
	body: string;
	files: StagedFile[];
};

async function git(pi: ExtensionAPI, ctx: ExtensionCommandContext, args: string[], timeout = GIT_TIMEOUT_MS) {
	return pi.exec("git", args, { cwd: ctx.cwd, timeout });
}

function oneLine(value: string) {
	return value.replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
}

function truncateSubject(value: string) {
	const subject = oneLine(value).replace(/[.]$/, "");
	if (subject.length <= MAX_SUBJECT_LENGTH) return subject;
	return `${subject.slice(0, MAX_SUBJECT_LENGTH - 1).trimEnd()}…`;
}

function titleCase(value: string) {
	return value.replace(/\b\w/g, (char) => char.toUpperCase());
}

function humanizeBasename(filePath: string) {
	const parsed = path.parse(filePath);
	const name = parsed.name || parsed.base;
	return name.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim();
}

function describePath(filePath: string) {
	const normalized = filePath.replaceAll("\\", "/");
	const base = humanizeBasename(normalized);

	if (normalized.includes("/.pi/agent/extensions/") || normalized.includes("extensions/")) {
		if (base === "README") return "Pi extension documentation";
		return `Pi ${base} extension`;
	}
	if (/README(\.md)?$/i.test(normalized)) return "documentation";
	if (normalized.endsWith("settings.json")) return "Pi settings";
	if (normalized.endsWith("mcp.json")) return "MCP configuration";
	return base || normalized;
}

function parseNameStatus(output: string): StagedFile[] {
	return output
		.split("\n")
		.map((line) => line.trim())
		.filter(Boolean)
		.map((line) => {
			const [status, firstPath, secondPath] = line.split("\t");
			if (status?.startsWith("R") || status?.startsWith("C")) {
				return { status: status[0] ?? "M", oldPath: firstPath ?? "", path: secondPath ?? firstPath ?? "" };
			}
			return { status: status ?? "M", path: firstPath ?? "" };
		})
		.filter((file) => file.path.length > 0);
}

function verbForStatus(status: string) {
	if (status.startsWith("A")) return "Add";
	if (status.startsWith("D")) return "Remove";
	if (status.startsWith("R")) return "Rename";
	if (status.startsWith("C")) return "Copy";
	return "Update";
}

function operationLabel(file: StagedFile) {
	const verb = verbForStatus(file.status);
	if (file.oldPath && file.oldPath !== file.path) return `${verb} ${file.oldPath} -> ${file.path}`;
	return `${verb} ${file.path}`;
}

function commonDirectory(files: StagedFile[]) {
	const dirs = files.map((file) => path.dirname(file.path).replaceAll("\\", "/"));
	if (dirs.length === 0) return "";
	let common = dirs[0] ?? "";
	for (const dir of dirs.slice(1)) {
		while (common && dir !== common && !dir.startsWith(`${common}/`)) {
			common = path.dirname(common).replaceAll("\\", "/");
			if (common === ".") common = "";
		}
	}
	return common;
}

function dominantVerb(files: StagedFile[]) {
	const verbs = files.map((file) => verbForStatus(file.status));
	const unique = [...new Set(verbs)];
	return unique.length === 1 ? unique[0] ?? "Update" : "Update";
}

function subjectForFiles(files: StagedFile[]) {
	if (files.length === 0) return "Update repository changes";
	if (files.length === 1) {
		const [file] = files;
		return `${verbForStatus(file.status)} ${describePath(file.path)}`;
	}

	const dir = commonDirectory(files);
	const verb = dominantVerb(files);
	if (dir.includes("extensions")) return `${verb} Pi extensions`;
	if (files.every((file) => /README(\.md)?$/i.test(file.path))) return `${verb} documentation`;
	if (dir && dir !== ".") return `${verb} ${titleCase(dir.replace(/[-_/]+/g, " "))}`;
	return `${verb} ${files.length} files`;
}

function buildCommitPlan(nameStatus: string, overrideSubject: string | undefined): CommitPlan {
	const files = parseNameStatus(nameStatus);
	const subject = truncateSubject(overrideSubject || subjectForFiles(files));
	const bodyLines = [
		"Changes:",
		...files.map((file) => `- ${operationLabel(file)}`),
		"",
		"Committed with /yeet.",
	];
	return { subject, body: bodyLines.join("\n"), files };
}

function normalizeRemoteUrl(url: string) {
	const trimmed = url.trim().replace(/\.git$/, "");
	const sshGitHub = trimmed.match(/^git@github\.com:(.+)$/);
	if (sshGitHub) return `https://github.com/${sshGitHub[1]}`;
	const ssh = trimmed.match(/^ssh:\/\/git@github\.com\/(.+)$/);
	if (ssh) return `https://github.com/${ssh[1]}`;
	return trimmed;
}

function branchUrl(remoteUrl: string | undefined, branch: string) {
	if (!remoteUrl) return undefined;
	const normalized = normalizeRemoteUrl(remoteUrl);
	if (!normalized.includes("github.com/")) return normalized;
	if (branch === "main") return normalized;
	return `${normalized}/compare/main...${encodeURIComponent(branch)}?expand=1`;
}

async function currentBranch(pi: ExtensionAPI, ctx: ExtensionCommandContext) {
	const result = await git(pi, ctx, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
	if (result.code !== 0 || !result.stdout.trim()) throw new Error("Cannot /yeet from a detached HEAD");
	return result.stdout.trim();
}

async function firstRemote(pi: ExtensionAPI, ctx: ExtensionCommandContext) {
	const result = await git(pi, ctx, ["remote"]);
	if (result.code !== 0) return undefined;
	return result.stdout.split("\n").map((line) => line.trim()).find(Boolean);
}

async function remoteUrl(pi: ExtensionAPI, ctx: ExtensionCommandContext, remote: string | undefined) {
	if (!remote) return undefined;
	const result = await git(pi, ctx, ["remote", "get-url", remote]);
	return result.code === 0 ? result.stdout.trim() : undefined;
}

async function hasUpstream(pi: ExtensionAPI, ctx: ExtensionCommandContext) {
	const result = await git(pi, ctx, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]);
	return result.code === 0 && !!result.stdout.trim();
}

async function pushCurrentBranch(pi: ExtensionAPI, ctx: ExtensionCommandContext, branch: string) {
	if (await hasUpstream(pi, ctx)) {
		const push = await git(pi, ctx, ["push"], PUSH_TIMEOUT_MS);
		if (push.code !== 0) throw new Error(push.stderr.trim() || "git push failed");
		const remote = (await git(pi, ctx, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])).stdout.trim().split("/")[0];
		return { pushed: true, remote, output: push.stdout.trim() || push.stderr.trim() };
	}

	const remote = await firstRemote(pi, ctx);
	if (!remote) return { pushed: false, remote: undefined, output: "No git remote configured; committed locally only." };

	const push = await git(pi, ctx, ["push", "-u", remote, branch], PUSH_TIMEOUT_MS);
	if (push.code !== 0) throw new Error(push.stderr.trim() || "git push -u failed");
	return { pushed: true, remote, output: push.stdout.trim() || push.stderr.trim() };
}

async function runYeet(pi: ExtensionAPI, args: string, ctx: ExtensionCommandContext) {
	const inside = await git(pi, ctx, ["rev-parse", "--is-inside-work-tree"]);
	if (inside.code !== 0 || inside.stdout.trim() !== "true") throw new Error("Current directory is not inside a git repository");

	const branch = await currentBranch(pi, ctx);
	const add = await git(pi, ctx, ["add", "-A"]);
	if (add.code !== 0) throw new Error(add.stderr.trim() || "git add -A failed");

	const staged = await git(pi, ctx, ["diff", "--cached", "--name-status", "--find-renames"]);
	if (staged.code !== 0) throw new Error(staged.stderr.trim() || "git diff --cached failed");
	if (!staged.stdout.trim()) return "No changes to yeet. Working tree has nothing staged after git add -A.";

	const plan = buildCommitPlan(staged.stdout, args.trim() || undefined);
	const commit = await git(pi, ctx, ["commit", "-m", plan.subject, "-m", plan.body]);
	if (commit.code !== 0) throw new Error(commit.stderr.trim() || "git commit failed");

	const push = await pushCurrentBranch(pi, ctx, branch);
	const url = branchUrl(await remoteUrl(pi, ctx, push.remote), branch);

	return [
		"# Yeet complete",
		"",
		`- Branch: ${branch}`,
		`- Commit: ${plan.subject}`,
		`- Files: ${plan.files.length}`,
		`- Push: ${push.pushed ? `pushed to ${push.remote}` : "skipped"}`,
		url ? `- URL: ${url}` : undefined,
		"",
		"## Commit body",
		"",
		plan.body,
	].filter((line): line is string => typeof line === "string").join("\n");
}

export default function yeetExtension(pi: ExtensionAPI) {
	pi.registerCommand("yeet", {
		description: "Add, commit, and push current branch changes with a clear generated commit message",
		handler: async (args, ctx) => {
			await ctx.waitForIdle();
			try {
				const report = await runYeet(pi, args, ctx);
				if (ctx.hasUI) {
					await ctx.ui.editor("/yeet", report);
				} else {
					console.log(report);
				}
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`/yeet failed: ${message}`, "error");
				if (!ctx.hasUI) console.error(message);
			}
		},
	});
}
