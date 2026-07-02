import type { PluginInput, Hooks } from "@opencode-ai/plugin";

const CACHE_TTL_MS = 5000;
const MISE_CONFIG_PATTERNS = /(?:^|\/)(\.?mise(?:\.local)?\.toml|\.tool-versions)$/;

const cache = new Map<string, { env: Record<string, string>; at: number }>();

function cacheKey(cwd: string) {
  return cwd;
}

function cacheGet(key: string): Record<string, string> | undefined {
  const entry = cache.get(key);
  if (entry && Date.now() - entry.at < CACHE_TTL_MS) {
    return entry.env;
  }
  return undefined;
}

function cacheSet(key: string, env: Record<string, string>) {
  cache.set(key, { env, at: Date.now() });
}

export const MisePlugin = async (input: PluginInput): Promise<Hooks> => {
  return {
    "shell.env": async (inputArgs, output) => {
      const cwd = inputArgs.cwd;
      let miseEnv = cacheGet(cacheKey(cwd));

      if (!miseEnv) {
        try {
          const result = await input.$`mise env --json`
            .cwd(cwd)
            .nothrow()
            .quiet();

          if (result.exitCode === 0) {
            const raw = result.json() as Record<string, unknown>;
            miseEnv = {};
            for (const [k, v] of Object.entries(raw)) {
              if (v !== undefined && v !== null) {
                miseEnv[k] = String(v);
              }
            }
            cacheSet(cacheKey(cwd), miseEnv);
          }
        } catch {
          return;
        }
      }

      if (miseEnv) {
        Object.assign(output.env, miseEnv);
      }
    },

    "file.watcher.updated": async (inputArgs) => {
      if (MISE_CONFIG_PATTERNS.test(inputArgs.file)) {
        cache.clear();
      }
    },
  };
};

export const server = MisePlugin;
export default MisePlugin;
