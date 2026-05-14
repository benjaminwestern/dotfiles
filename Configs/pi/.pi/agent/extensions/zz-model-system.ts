import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

const PROMPT_DIR = "model-system";
const SECTION_START = "<!-- pi:model-system:start -->";
const SECTION_END = "<!-- pi:model-system:end -->";
const SECTION_HEADING = "# Model-specific System Prompt";

type ModelLike = {
	provider: string;
	id: string;
	name?: string;
};

type PromptScope = "global" | "project";
type PromptKind = "all" | "provider" | "model";

type PromptMatch = {
	path: string;
	scope: PromptScope;
	kind: PromptKind;
	content: string;
};

function ancestorDirs(cwd: string): string[] {
	const dirs: string[] = [];
	let dir = resolve(cwd);
	while (true) {
		dirs.push(dir);
		const parent = dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	return dirs.reverse();
}

function modelRef(model: ModelLike | undefined): string {
	return model ? `${model.provider}/${model.id}` : "unknown";
}

function safeFileName(value: string): string {
	return value.replace(/[\\/]/g, "__");
}

function uniqueCandidates(candidates: Array<{ path: string; kind: PromptKind }>): Array<{ path: string; kind: PromptKind }> {
	const seen = new Set<string>();
	const result: Array<{ path: string; kind: PromptKind }> = [];
	for (const candidate of candidates) {
		const key = resolve(candidate.path);
		if (seen.has(key)) continue;
		seen.add(key);
		result.push(candidate);
	}
	return result;
}

function candidateFiles(baseDir: string, model: ModelLike): Array<{ path: string; kind: PromptKind }> {
	const provider = model.provider;
	const id = model.id;
	const safeId = safeFileName(id);
	const safeRef = `${provider}__${safeId}`;

	return uniqueCandidates([
		{ path: join(baseDir, "all.md"), kind: "all" },
		{ path: join(baseDir, `${provider}.md`), kind: "provider" },
		{ path: join(baseDir, provider, "all.md"), kind: "provider" },
		{ path: join(baseDir, provider, "index.md"), kind: "provider" },
		{ path: join(baseDir, provider, `${id}.md`), kind: "model" },
		{ path: join(baseDir, provider, `${safeId}.md`), kind: "model" },
		{ path: join(baseDir, `${safeRef}.md`), kind: "model" },
	]);
}

function promptDirs(cwd: string): Array<{ path: string; scope: PromptScope }> {
	return [
		{ path: join(getAgentDir(), PROMPT_DIR), scope: "global" },
		...ancestorDirs(cwd).map((dir) => ({ path: join(dir, ".pi", PROMPT_DIR), scope: "project" as const })),
	];
}

function loadModelPrompts(ctx: Pick<ExtensionContext, "cwd" | "model">): PromptMatch[] {
	const model = ctx.model;
	if (!model) return [];

	const matches: PromptMatch[] = [];
	const seen = new Set<string>();
	for (const dir of promptDirs(ctx.cwd)) {
		if (!existsSync(dir.path)) continue;
		for (const candidate of candidateFiles(dir.path, model)) {
			const key = resolve(candidate.path);
			if (seen.has(key) || !existsSync(candidate.path)) continue;
			seen.add(key);
			try {
				const content = readFileSync(candidate.path, "utf8").trim();
				if (!content) continue;
				matches.push({
					path: candidate.path,
					scope: dir.scope,
					kind: candidate.kind,
					content,
				});
			} catch {
				// Keep prompt loading best-effort; /model-system will still show the path exists.
			}
		}
	}
	return matches;
}

function stripOwnSection(prompt: string): string {
	const start = prompt.indexOf(SECTION_START);
	if (start < 0) return prompt.trimEnd();
	const end = prompt.indexOf(SECTION_END, start + SECTION_START.length);
	if (end < 0) return prompt.slice(0, start).trimEnd();
	return `${prompt.slice(0, start)}${prompt.slice(end + SECTION_END.length)}`.trimEnd();
}

function appendModelPrompts(basePrompt: string, currentModelRef: string, matches: PromptMatch[]): string {
	if (matches.length === 0) return stripOwnSection(basePrompt);

	const sections = matches.map((match) => {
		return [`## ${match.scope} ${match.kind} instructions`, match.content].join("\n\n");
	});

	return `${stripOwnSection(basePrompt)}\n\n${SECTION_START}\n${SECTION_HEADING}\n\nThese additional instructions apply only because the current model is ${currentModelRef}.\n\n${sections.join("\n\n")}\n${SECTION_END}`;
}

export default function modelSystemPrompts(pi: ExtensionAPI) {
	pi.on("before_agent_start", (event, ctx) => {
		const matches = loadModelPrompts(ctx);
		return {
			systemPrompt: appendModelPrompts(event.systemPrompt, modelRef(ctx.model), matches),
		};
	});
}
