import type { PluginInput, Hooks } from "@opencode-ai/plugin";

export const MisePlugin = async (input: PluginInput): Promise<Hooks> => {
  return {
    "shell.env": async (inputArgs, output) => {
      try {
        // Re-run mise for every shell execution so tool/env changes are picked up
        // without restarting the opencode session.
        const result = await input.$`mise env --json`
          .cwd(inputArgs.cwd)
          .nothrow()
          .quiet();

        if (result.exitCode !== 0) return;

        const miseEnv = result.json() as Record<string, unknown>;
        for (const [key, value] of Object.entries(miseEnv)) {
          if (value !== undefined && value !== null) {
            output.env[key] = String(value);
          }
        }
      } catch {
        // Silently fall back to opencode's standard environment if mise fails.
      }
    },
  };
};

export const server = MisePlugin;
export default MisePlugin;
