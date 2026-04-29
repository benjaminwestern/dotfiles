import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { createBashToolDefinition, createLocalBashOperations } from "@mariozechner/pi-coding-agent";

const MISE_ENV_PREFIX = 'eval "$(mise env -s bash)"';
const MISE_PROMPT_NOTE = `Mise tool hot-reload is enabled for Pi bash commands. Before each bash execution, Pi refreshes the shell environment with \`mise env -s bash\` for the command cwd, so newly installed or changed mise tools are available without restarting the session. Use bash normally; do not hard-code mise install paths.`;

function withMiseEnv(command: string): string {
  return `${MISE_ENV_PREFIX}\n${command}`;
}

export default function (pi: ExtensionAPI) {
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

  pi.on("before_agent_start", (event) => {
    if (event.systemPrompt.includes("Mise tool hot-reload is enabled for Pi bash commands.")) {
      return;
    }

    return {
      systemPrompt: `${event.systemPrompt}\n\n${MISE_PROMPT_NOTE}`,
    };
  });
}
