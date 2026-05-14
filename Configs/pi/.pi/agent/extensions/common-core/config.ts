import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

export type ExtensionConfigScope = "global" | "project";

export type ExtensionConfigLayer<T extends Record<string, unknown>> = {
	path: string;
	scope: ExtensionConfigScope;
	config: Partial<T>;
};

export type ExtensionConfigResult<T extends Record<string, unknown>> = {
	config: T;
	layers: ExtensionConfigLayer<T>[];
	errors: string[];
};

function stripJsonComments(raw: string): string {
	return raw
		.replace(/\/\*[\s\S]*?\*\//g, "")
		.replace(/(^|[^:])\/\/.*$/gm, "$1")
		.replace(/,\s*([}\]])/g, "$1");
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
	return !!value && typeof value === "object" && !Array.isArray(value);
}

function cloneConfigValue(value: unknown): any {
	if (Array.isArray(value)) return value.map((item) => cloneConfigValue(item));
	if (!isPlainObject(value)) return value;
	const copy: Record<string, unknown> = {};
	for (const [key, child] of Object.entries(value)) copy[key] = cloneConfigValue(child);
	return copy;
}

function mergeConfigValue(base: unknown, override: unknown): any {
	if (override === null) return undefined;
	if (Array.isArray(override) || !isPlainObject(override)) return cloneConfigValue(override);

	const result = isPlainObject(base) ? cloneConfigValue(base) : {};
	for (const [key, value] of Object.entries(override)) {
		if (value === null) {
			delete result[key];
			continue;
		}
		const merged = mergeConfigValue(result[key], value);
		if (merged === undefined) delete result[key];
		else result[key] = merged;
	}
	return result;
}

function mergeConfigs<T extends Record<string, unknown>>(base: T, override: Partial<T> | undefined): T {
	return mergeConfigValue(base, override ?? {}) as T;
}

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

function normalizeConfigFile(fileName: string): string {
	return fileName.endsWith(".json") ? fileName : `${fileName}.json`;
}

function parseConfigFile<T extends Record<string, unknown>>(path: string): Partial<T> {
	const parsed = JSON.parse(stripJsonComments(readFileSync(path, "utf8"))) as unknown;
	return isPlainObject(parsed) ? (parsed as Partial<T>) : {};
}

/**
 * Load extension-owned config without touching Pi's core settings.json.
 *
 * Convention:
 * - global:  ~/.pi/agent/<extension>.json
 * - project: <ancestor>/.pi/<extension>.json, merged outermost to nearest cwd
 *
 * Merge rules mirror the local MCP extension: objects deep-merge, arrays/scalars
 * replace, and null deletes inherited object keys.
 */
export function loadExtensionConfig<T extends Record<string, unknown>>(
	fileName: string,
	cwd: string,
	defaults: T,
): ExtensionConfigResult<T> {
	const configFile = normalizeConfigFile(fileName);
	const layers: ExtensionConfigLayer<T>[] = [];
	const errors: string[] = [];
	let config = cloneConfigValue(defaults) as T;

	const globalPath = join(getAgentDir(), configFile);
	if (existsSync(globalPath)) {
		try {
			const parsed = parseConfigFile<T>(globalPath);
			config = mergeConfigs(config, parsed);
			layers.push({ path: globalPath, scope: "global", config: parsed });
		} catch (error) {
			errors.push(`${globalPath}: ${error instanceof Error ? error.message : String(error)}`);
		}
	}

	for (const dir of ancestorDirs(cwd)) {
		const projectPath = join(dir, ".pi", configFile);
		if (projectPath === globalPath || !existsSync(projectPath)) continue;
		try {
			const parsed = parseConfigFile<T>(projectPath);
			config = mergeConfigs(config, parsed);
			layers.push({ path: projectPath, scope: "project", config: parsed });
		} catch (error) {
			errors.push(`${projectPath}: ${error instanceof Error ? error.message : String(error)}`);
		}
	}

	return { config, layers, errors };
}
