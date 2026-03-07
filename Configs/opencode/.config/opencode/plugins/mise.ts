import { $ } from "bun";
import type { PluginInput, Hooks } from "@opencode-ai/plugin";

export const MisePlugin = async (input: PluginInput): Promise<Hooks> => {
  return {
    "shell.env": async (inputArgs, output) => {
      try {
        // Run mise env to get the exact environment for the current directory
        const result = await $`mise env --json`
          .cwd(inputArgs.cwd)
          .nothrow()
          .quiet();

        if (result.exitCode === 0) {
          const miseEnv = await result.json();

          // Inject the mise shims (PATH) and other vars into opencode's command
          for (const [key, value] of Object.entries(miseEnv)) {
            output.env[key] = String(value);
          }
        }
      } catch (err) {
        // Silently fall back to standard system environment if mise fails
      }
    },
  };
};
