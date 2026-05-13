import { accessSync, constants } from "node:fs";
import { basename } from "node:path";
import {
	createLocalBashOperations,
	type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

const MISE_FISH_ENV_PREFIX = "if command -q mise; mise env -s fish | source; end";
const FISH_USER_BASH_PROMPT_NOTE = `User-triggered shell commands (Pi !/!! user_bash) run through fish, matching the configured login shell, and refresh mise with \`mise env -s fish\` immediately before execution. The model-facing bash tool still accepts bash syntax and refreshes mise separately.`;

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

function isFishLike(path: string | undefined): path is string {
	if (!path) return false;
	const name = basename(path);
	return name === "fish" || name === "fsh";
}

function getFishPath(): string {
	const explicit = process.env.PI_USER_FISH_SHELL ?? process.env.PI_USER_FSH_SHELL;
	if (explicit) return explicit;

	const compatibilityShell = process.env.PI_USER_BASH_SHELL;
	if (isFishLike(compatibilityShell)) return compatibilityShell;

	if (isFishLike(process.env.SHELL)) return process.env.SHELL;

	const commonPaths = [
		"/opt/homebrew/bin/fish",
		"/usr/local/bin/fish",
		"/usr/bin/fish",
		"/bin/fish",
	];
	const installed = commonPaths.find(isExecutable);
	if (installed) return installed;

	// Let PATH resolution handle less common installs.
	return "fish";
}

function runInFish(command: string): string {
	return [
		"exec",
		shellQuote(getFishPath()),
		"-C",
		shellQuote(MISE_FISH_ENV_PREFIX),
		"-c",
		shellQuote(command),
	].join(" ");
}

export default function fishUserBash(pi: ExtensionAPI) {
	const local = createLocalBashOperations();

	pi.on("user_bash", () => {
		return {
			operations: {
				exec(command, cwd, options) {
					return local.exec(runInFish(command), cwd, options);
				},
			},
		};
	});

	pi.on("before_agent_start", (event) => {
		if (event.systemPrompt.includes("User-triggered shell commands (Pi !/!! user_bash) run through fish")) {
			return;
		}

		return {
			systemPrompt: `${event.systemPrompt}\n\n${FISH_USER_BASH_PROMPT_NOTE}`,
		};
	});
}
