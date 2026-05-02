import {
	createBashToolDefinition,
	createLocalBashOperations,
	type ExtensionAPI,
	type ExtensionCommandContext,
} from "@mariozechner/pi-coding-agent";

const MISE_ENV_PREFIX = 'eval "$(mise env -s bash)"';
const MISE_PROMPT_NOTE = `Mise tool hot-reload is enabled for Pi bash commands. Before each bash execution, Pi refreshes the shell environment with \`mise env -s bash\` for the command cwd, so newly installed or changed mise tools are available without restarting the session. Use bash normally; do not hard-code mise install paths.`;

function requireMessage(command: string, args: string, ctx: ExtensionCommandContext): string | undefined {
	const message = args.trim();
	if (message) return message;

	ctx.ui.notify(`Usage: /${command} <message>`, "warning");
	return undefined;
}

function withMiseEnv(command: string): string {
	return `${MISE_ENV_PREFIX}\n${command}`;
}

export default function utils(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		const bashTool = createBashToolDefinition(ctx.cwd, {
			commandPrefix: MISE_ENV_PREFIX,
		});

		pi.registerTool({
			...bashTool,
			description: `${bashTool.description}\n\nMise hot-reload: before each bash execution, Pi refreshes the environment with \`mise env -s bash\` for the command cwd.`,
			promptGuidelines: [
				"Bash commands run with mise hot-reload: Pi refreshes the environment with `mise env -s bash` before each bash execution.",
			],
		});
	});

	pi.on("user_bash", () => {
		const local = createLocalBashOperations();

		return {
			operations: {
				exec(command, cwd, options) {
					return local.exec(withMiseEnv(command), cwd, options);
				},
			},
		};
	});

	// Pi exposes two context-control paths we can lean on when needed:
	// - before_agent_start may return a modified systemPrompt for each model turn.
	// - active tools with promptSnippet/promptGuidelines are included in Pi's tool prompt section.
	//
	// Keep this utility hook narrow. The old skills-context extension used this
	// same mechanism to strip/re-seed skills, but native Pi skills are the
	// cleaner default unless we explicitly need custom context policy again.
	pi.on("before_agent_start", (event) => {
		if (event.systemPrompt.includes("Mise tool hot-reload is enabled for Pi bash commands.")) {
			return;
		}

		return {
			systemPrompt: `${event.systemPrompt}\n\n${MISE_PROMPT_NOTE}`,
		};
	});

	pi.registerCommand("clear", {
		description: "Alias for /new; starts a fresh session",
		handler: async (_args, ctx) => {
			const result = await ctx.newSession({
				withSession: async (nextCtx) => {
					nextCtx.ui.notify("New session started", "info");
				},
			});

			if (result.cancelled) {
				ctx.ui.notify("New session cancelled", "warning");
			}
		},
	});

	pi.registerCommand("steer", {
		description: "Send a steering message; while Pi is working it is delivered before the next model turn",
		handler: async (args, ctx) => {
			const message = requireMessage("steer", args, ctx);
			if (!message) return;

			pi.sendUserMessage(message, { deliverAs: "steer" });
			ctx.ui.notify("Steering message sent", "info");
		},
	});

	pi.registerCommand("queue", {
		description: "Send a follow-up message; while Pi is working it waits until the agent finishes",
		handler: async (args, ctx) => {
			const message = requireMessage("queue", args, ctx);
			if (!message) return;

			pi.sendUserMessage(message, { deliverAs: "followUp" });
			ctx.ui.notify("Follow-up message queued", "info");
		},
	});
}
