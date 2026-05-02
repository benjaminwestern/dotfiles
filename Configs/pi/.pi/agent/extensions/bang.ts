/**
 * Bang Extension — Inline Bash Expansion for Pi
 *
 * Expands `!{command}` patterns inside user prompts before they reach the LLM.
 *
 * Usage:
 *   What's in !{pwd}?
 *   The current branch is !{git branch --show-current} and status: !{git status --short}
 *   My node version is !{node --version}
 *
 * Whole-line `!command` and `!!command` remain untouched — those are handled natively by Pi.
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const PATTERN = /!\{([^}]+)\}/g;
const TIMEOUT_MS = 30000;
const MAX_OUTPUT_PREVIEW = 60;

interface Expansion {
	command: string;
	output: string;
	error?: string;
	exitCode?: number;
}

export default function (pi: ExtensionAPI) {
	pi.on("input", async (event, ctx) => {
		const text = event.text;

		// Don't process whole-line bash commands (!command or !!command).
		// Those are handled natively by Pi's user_bash event.
		const trimmed = text.trimStart();
		if (trimmed.startsWith("!") && !trimmed.startsWith("!{")) {
			return { action: "continue" };
		}

		// Quick check: any inline bang patterns?
		if (!PATTERN.test(text)) {
			return { action: "continue" };
		}

		// Reset regex state after test()
		PATTERN.lastIndex = 0;

		// Collect all matches first to avoid replacement-order issues
		const matches: Array<{ full: string; command: string }> = [];
		let match = PATTERN.exec(text);
		while (match) {
			matches.push({ full: match[0], command: match[1] });
			match = PATTERN.exec(text);
		}

		let result = text;
		const expansions: Expansion[] = [];

		for (const { full, command } of matches) {
			try {
				const bashResult = await pi.exec("bash", ["-c", command], {
					timeout: TIMEOUT_MS,
				});

				const output = (bashResult.stdout || bashResult.stderr || "").trim();

				expansions.push({
					command,
					output,
					exitCode: bashResult.code,
					error:
						bashResult.code !== 0 && bashResult.stderr
							? `exit code ${bashResult.code}`
							: undefined,
				});

				result = result.replace(full, output);
			} catch (err) {
				const errorMsg = err instanceof Error ? err.message : String(err);
				expansions.push({
					command,
					output: "",
					error: errorMsg,
				});
				result = result.replace(full, `[bang error: ${errorMsg}]`);
			}
		}

		// Show expansion summary when UI is available
		if (ctx.hasUI && expansions.length > 0) {
			const summary = expansions
				.map((e) => {
					const status = e.error ? ` ⚠ ${e.error}` : "";
					const preview =
						e.output.length > MAX_OUTPUT_PREVIEW
							? `${e.output.slice(0, MAX_OUTPUT_PREVIEW)}…`
							: e.output;
					return `!{${e.command}}${status} → "${preview}"`;
				})
				.join("\n");

			ctx.ui.notify(`Bang: expanded ${expansions.length} command(s)\n${summary}`, "info");
		}

		return { action: "transform", text: result, images: event.images };
	});
}
