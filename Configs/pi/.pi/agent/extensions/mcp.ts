import { Type } from "@mariozechner/pi-ai";
import { DynamicBorder, defineTool, getAgentDir, getSettingsListTheme, type ExtensionAPI, type ExtensionCommandContext } from "@mariozechner/pi-coding-agent";
import { Container, type SettingItem, SettingsList, Text } from "@mariozechner/pi-tui";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const DEFAULT_TIMEOUT_MS = 30_000;
const GLOBAL_CONFIG_PATH = join(getAgentDir(), "mcp.json");
const PROJECT_CONFIG_DIR = ".pi";
const PROJECT_CONFIG_FILE = "mcp.json";
const ROUTER_TOOL_NAMES = ["mcp_search", "mcp_inspect", "mcp_call"];

type McpServerConfig = {
	type?: "remote" | "http" | "streamable-http" | "sse" | "stdio";
	description?: string;
	enabled?: boolean;
	selectedTools?: string[];
	url?: string;
	baseUrl?: string;
	command?: string;
	args?: string[];
	cwd?: string;
	env?: Record<string, string | null>;
	headers?: Record<string, string | null>;
	envHeaders?: Record<string, string | null>;
	apiKeyEnv?: string;
	timeoutMs?: number;
	protocolVersion?: string;
	enabledTools?: string[];
	allowedTools?: string[];
	disabledTools?: string[];
};

type McpConfig = {
	servers?: Record<string, McpServerConfig>;
	/** Deprecated compatibility cache. Prefer servers.<name>.selectedTools. */
	toolSurfaces?: Record<string, McpToolSurfaceConfig>;
};

type McpToolSurfaceConfig = {
	server: string;
	tool: string;
	name?: string;
	description?: string;
	inputSchema?: unknown;
	enabled?: boolean;
	loadedAt?: string;
};

type InventoryTool = {
	server: string;
	name: string;
	description: string;
	inputSchema: unknown;
};

type Inventory = {
	tools: InventoryTool[];
	errors: string[];
	loadedAt: string;
};

type McpProjectLayer = {
	path: string;
	root: string;
	config: McpConfig;
};

type McpWriteTarget = {
	scope: "global" | "project";
	path: string;
};

type McpDiagnostic = {
	level: "error" | "warning";
	path: string;
	message: string;
};

type McpState = {
	cwd: string;
	globalPath: string;
	globalExists: boolean;
	globalConfig: McpConfig;
	projectLayers: McpProjectLayer[];
	projectConfig: McpConfig;
	effectiveConfig: McpConfig;
	serverSources: Record<string, string>;
	diagnostics: McpDiagnostic[];
};

type InventoryCache = {
	key: string;
	inventory: Inventory;
};

const stdioClients = new Map<string, StdioMcpClient>();
const hydratedSurfaceTools = new Map<string, McpToolSurfaceConfig>();
let inventoryCache: InventoryCache | undefined;
const registeredSurfaceTools = new Map<string, string>();

function textResult(text: string, details: Record<string, unknown> = {}) {
	return {
		content: [{ type: "text" as const, text }],
		details,
	};
}

function parseJsonOrSse(raw: string): any {
	const trimmed = raw.trim();
	if (trimmed.startsWith("{")) return JSON.parse(trimmed);

	for (const line of trimmed.split(/\r?\n/)) {
		if (!line.startsWith("data:")) continue;
		const payload = line.slice("data:".length).trim();
		if (!payload || payload === "[DONE]") continue;
		return JSON.parse(payload);
	}

	throw new Error("MCP response was not JSON or SSE");
}

function stripJsonComments(raw: string): string {
	return raw
		.replace(/\/\*[\s\S]*?\*\//g, "")
		.replace(/(^|[^:])\/\/.*$/gm, "$1")
		.replace(/,\s*([}\]])/g, "$1");
}

function defaultConfig(): McpConfig {
	return emptyConfig();
}

function emptyConfig(): McpConfig {
	return { servers: {} };
}

function normalizeConfig(config: McpConfig | undefined): McpConfig {
	const normalized = config ?? emptyConfig();
	if (!normalized.servers) normalized.servers = {};
	return normalized;
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

function mergeConfigs(base: McpConfig, override: McpConfig | undefined): McpConfig {
	return normalizeConfig(mergeConfigValue(base, override ?? emptyConfig()) as McpConfig);
}

function projectConfigPath(cwd: string): string {
	return join(cwd, PROJECT_CONFIG_DIR, PROJECT_CONFIG_FILE);
}

function projectRootForConfigPath(path: string): string {
	return dirname(dirname(path));
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

function readConfigFile(path: string): McpConfig {
	const raw = readFileSync(path, "utf8");
	return normalizeConfig(JSON.parse(stripJsonComments(raw)) as McpConfig);
}

function configForWrite(config: McpConfig): McpConfig {
	const copy = cloneConfigValue(normalizeConfig(config)) as McpConfig;
	if (copy.toolSurfaces && Object.keys(copy.toolSurfaces).length === 0) delete copy.toolSurfaces;
	return copy;
}

function writeConfigFile(path: string, config: McpConfig) {
	writeFileSync(path, `${JSON.stringify(configForWrite(config), null, 2)}\n`, "utf8");
}

function loadGlobalConfig(): { exists: boolean; config: McpConfig } {
	if (!existsSync(GLOBAL_CONFIG_PATH)) return { exists: false, config: defaultConfig() };
	return { exists: true, config: readConfigFile(GLOBAL_CONFIG_PATH) };
}

function loadProjectLayers(cwd: string): McpProjectLayer[] {
	return ancestorDirs(cwd)
		.map((dir) => projectConfigPath(dir))
		.filter((path) => existsSync(path))
		.map((path) => ({ path, root: projectRootForConfigPath(path), config: readConfigFile(path) }));
}

function mergeProjectLayers(layers: McpProjectLayer[]): McpConfig {
	return layers.reduce((merged, layer) => mergeConfigs(merged, layer.config), emptyConfig());
}

function compactMiddle(value: string, maxLength = 96): string {
	if (value.length <= maxLength) return value;
	const marker = "…";
	const keep = maxLength - marker.length;
	const head = Math.ceil(keep * 0.45);
	const tail = Math.floor(keep * 0.55);
	return `${value.slice(0, head)}${marker}${value.slice(value.length - tail)}`;
}

function formatLayerPath(path: string): string {
	return compactMiddle(path, 100);
}

function sourceByServer(globalConfig: McpConfig, projectLayers: McpProjectLayer[], effectiveConfig: McpConfig, globalExists: boolean): Record<string, string> {
	const sources: Record<string, string> = {};
	for (const serverName of Object.keys(effectiveConfig.servers ?? {})) {
		const inGlobal = !!globalConfig.servers?.[serverName];
		const projectHits = projectLayers.filter((layer) => !!layer.config.servers?.[serverName]);
		if (inGlobal && projectHits.length) sources[serverName] = `project override over ${globalExists ? "global" : "built-in"} (${projectHits.length} layer${projectHits.length === 1 ? "" : "s"})`;
		else if (projectHits.length) sources[serverName] = `project (${projectHits.length} layer${projectHits.length === 1 ? "" : "s"})`;
		else if (inGlobal) sources[serverName] = globalExists ? "global" : "built-in";
		else sources[serverName] = "effective";
	}
	return sources;
}

function diagnostic(level: McpDiagnostic["level"], path: string, message: string): McpDiagnostic {
	return { level, path, message };
}

function validateStringArray(value: unknown, path: string, diagnostics: McpDiagnostic[], allowNull = false) {
	if (value === undefined || (allowNull && value === null)) return;
	if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
		diagnostics.push(diagnostic("error", path, allowNull ? "must be an array of strings or null" : "must be an array of strings"));
	}
}

function validateStringRecord(value: unknown, path: string, diagnostics: McpDiagnostic[], allowNull = false) {
	if (value === undefined) return;
	if (!isPlainObject(value)) {
		diagnostics.push(diagnostic("error", path, "must be an object"));
		return;
	}
	for (const [key, item] of Object.entries(value)) {
		if (typeof item !== "string" && !(allowNull && item === null)) diagnostics.push(diagnostic("error", `${path}.${key}`, allowNull ? "must be a string or null" : "must be a string"));
	}
}

function validateConfig(config: McpConfig, label: string, allowNull = true): McpDiagnostic[] {
	const diagnostics: McpDiagnostic[] = [];
	if (!isPlainObject(config.servers)) {
		diagnostics.push(diagnostic("error", `${label}.servers`, "must be an object"));
		return diagnostics;
	}

	for (const [serverName, rawServer] of Object.entries(config.servers ?? {})) {
		const path = `${label}.servers.${serverName}`;
		if (allowNull && rawServer === null) continue;
		if (!isPlainObject(rawServer)) {
			diagnostics.push(diagnostic("error", path, allowNull ? "must be an object or null" : "must be an object"));
			continue;
		}
		const server = rawServer as McpServerConfig;
		const kind = server.type ?? (server.command ? "stdio" : "remote");
		if (!["remote", "http", "streamable-http", "sse", "stdio"].includes(kind)) diagnostics.push(diagnostic("error", `${path}.type`, "must be one of remote, http, streamable-http, sse, stdio"));
		if (server.enabled !== undefined && !(allowNull && (server.enabled as any) === null) && typeof server.enabled !== "boolean") diagnostics.push(diagnostic("error", `${path}.enabled`, allowNull ? "must be a boolean or null" : "must be a boolean"));
		if (server.timeoutMs !== undefined && !(allowNull && (server.timeoutMs as any) === null) && typeof server.timeoutMs !== "number") diagnostics.push(diagnostic("error", `${path}.timeoutMs`, allowNull ? "must be a number or null" : "must be a number"));
		if (server.description !== undefined && !(allowNull && (server.description as any) === null) && typeof server.description !== "string") diagnostics.push(diagnostic("warning", `${path}.description`, allowNull ? "should be a string or null" : "should be a string"));
		if (!allowNull && kind === "stdio" && (typeof server.command !== "string" || !server.command.trim())) diagnostics.push(diagnostic("error", `${path}.command`, "is required for stdio servers"));
		if (!allowNull && kind !== "stdio" && typeof server.url !== "string" && typeof server.baseUrl !== "string") diagnostics.push(diagnostic("error", `${path}.url`, "url or baseUrl is required for remote servers"));
		if (server.command !== undefined && !(allowNull && (server.command as any) === null) && typeof server.command !== "string") diagnostics.push(diagnostic("error", `${path}.command`, allowNull ? "must be a string or null" : "must be a string"));
		if (server.cwd !== undefined && !(allowNull && (server.cwd as any) === null) && typeof server.cwd !== "string") diagnostics.push(diagnostic("error", `${path}.cwd`, allowNull ? "must be a string or null" : "must be a string"));
		if (server.url !== undefined && !(allowNull && (server.url as any) === null) && typeof server.url !== "string") diagnostics.push(diagnostic("error", `${path}.url`, allowNull ? "must be a string or null" : "must be a string"));
		if (server.baseUrl !== undefined && !(allowNull && (server.baseUrl as any) === null) && typeof server.baseUrl !== "string") diagnostics.push(diagnostic("error", `${path}.baseUrl`, allowNull ? "must be a string or null" : "must be a string"));
		if (server.apiKeyEnv !== undefined && !(allowNull && (server.apiKeyEnv as any) === null) && typeof server.apiKeyEnv !== "string") diagnostics.push(diagnostic("error", `${path}.apiKeyEnv`, allowNull ? "must be a string or null" : "must be a string"));
		validateStringArray(server.args, `${path}.args`, diagnostics, allowNull);
		validateStringArray(server.selectedTools, `${path}.selectedTools`, diagnostics, allowNull);
		validateStringArray(server.enabledTools, `${path}.enabledTools`, diagnostics, allowNull);
		validateStringArray(server.allowedTools, `${path}.allowedTools`, diagnostics, allowNull);
		validateStringArray(server.disabledTools, `${path}.disabledTools`, diagnostics, allowNull);
		validateStringRecord(server.env, `${path}.env`, diagnostics, allowNull);
		validateStringRecord(server.headers, `${path}.headers`, diagnostics, allowNull);
		validateStringRecord(server.envHeaders, `${path}.envHeaders`, diagnostics, allowNull);
	}
	return diagnostics;
}

function serverRuntimeIdentity(server: McpServerConfig): string {
	const kind = server.type ?? (server.command ? "stdio" : "remote");
	if (kind === "stdio") return `stdio:${server.command ?? ""}:${JSON.stringify(server.args ?? [])}`;
	return `${kind}:${server.url ?? server.baseUrl ?? ""}`;
}

function validateDirectToolNamespace(config: McpConfig): McpDiagnostic[] {
	const diagnostics: McpDiagnostic[] = [];
	const owners = new Map<string, string[]>();
	for (const selection of selectedDirectTools(config)) {
		const owner = `${selection.serverName}.${selection.toolName}`;
		owners.set(selection.directName, [...(owners.get(selection.directName) ?? []), owner]);
	}
	for (const [directName, mappedOwners] of owners) {
		const uniqueOwners = [...new Set(mappedOwners)];
		if (mappedOwners.length > 1) {
			diagnostics.push(diagnostic("error", `effective.selectedTools.${directName}`, `direct MCP tool name collision: ${uniqueOwners.join(", ")} all map to ${directName}. Rename the server or raw tool, or expose only one directly.`));
		}
	}
	return diagnostics;
}

function validateDuplicateRuntimeTargets(config: McpConfig): McpDiagnostic[] {
	const diagnostics: McpDiagnostic[] = [];
	const owners = new Map<string, string[]>();
	for (const [serverName, server] of enabledServers(config)) {
		const identity = serverRuntimeIdentity(server);
		owners.set(identity, [...(owners.get(identity) ?? []), serverName]);
	}
	for (const [identity, serverNames] of owners) {
		if (serverNames.length > 1) {
			diagnostics.push(diagnostic("warning", "effective.servers", `enabled servers ${serverNames.join(", ")} share the same MCP runtime target (${identity}). This can spawn duplicate MCP processes; prefer one server name with project-layer overrides.`));
		}
	}
	return diagnostics;
}

function validateEffectiveConfig(config: McpConfig): McpDiagnostic[] {
	return [
		...validateConfig(config, "effective", false),
		...validateDirectToolNamespace(config),
		...validateDuplicateRuntimeTargets(config),
	];
}

function loadMcpState(cwd: string): McpState {
	const global = loadGlobalConfig();
	const projectLayers = loadProjectLayers(cwd);
	const projectConfig = mergeProjectLayers(projectLayers);
	const effectiveConfig = mergeConfigs(global.config, projectLayers.length ? projectConfig : undefined);
	const diagnostics = [
		...validateConfig(global.config, global.exists ? "global" : "built-in"),
		...projectLayers.flatMap((layer, index) => validateConfig(layer.config, `project[${index}]:${layer.path}`)),
		...validateEffectiveConfig(effectiveConfig),
	];
	return {
		cwd,
		globalPath: GLOBAL_CONFIG_PATH,
		globalExists: global.exists,
		globalConfig: global.config,
		projectLayers,
		projectConfig,
		effectiveConfig,
		serverSources: sourceByServer(global.config, projectLayers, effectiveConfig, global.exists),
		diagnostics,
	};
}

function safeLoadMcpState(cwd: string): McpState {
	try {
		return loadMcpState(cwd);
	} catch (error: any) {
		const effectiveConfig = defaultConfig();
		return {
			cwd,
			globalPath: GLOBAL_CONFIG_PATH,
			globalExists: false,
			globalConfig: effectiveConfig,
			projectLayers: [],
			projectConfig: emptyConfig(),
			effectiveConfig,
			serverSources: sourceByServer(effectiveConfig, [], effectiveConfig, false),
			diagnostics: [diagnostic("error", "config", error?.message ?? String(error))],
		};
	}
}

function loadConfig(cwd: string): McpConfig {
	return loadMcpState(cwd).effectiveConfig;
}

function loadTargetConfig(target: McpWriteTarget): McpConfig {
	if (existsSync(target.path)) return readConfigFile(target.path);
	return target.scope === "global" ? defaultConfig() : emptyConfig();
}

function saveTargetConfig(target: McpWriteTarget, config: McpConfig, closeClientsOnChange = true) {
	if (target.scope === "project") mkdirSync(dirname(target.path), { recursive: true });
	writeConfigFile(target.path, config);
	resetRuntimeForConfigChange(closeClientsOnChange);
}

function ensureLayerServer(config: McpConfig, serverName: string): McpServerConfig {
	if (!config.servers) config.servers = {};
	config.servers[serverName] ??= {};
	return config.servers[serverName];
}

function sortedUnique(values: string[]): string[] {
	return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function saveServerEnabledOverride(cwd: string, target: McpWriteTarget, serverName: string, enabled: boolean): McpState {
	const config = loadTargetConfig(target);
	ensureLayerServer(config, serverName).enabled = enabled;
	saveTargetConfig(target, config);
	return loadMcpState(cwd);
}

function saveSelectedToolsOverride(cwd: string, target: McpWriteTarget, serverName: string, selectedTools: string[]): McpState {
	const config = loadTargetConfig(target);
	const server = ensureLayerServer(config, serverName);
	server.selectedTools = sortedUnique(selectedTools);
	saveTargetConfig(target, config, false);
	return loadMcpState(cwd);
}

function initProjectConfig(cwd: string): { path: string; created: boolean } {
	const path = projectConfigPath(cwd);
	if (existsSync(path)) return { path, created: false };
	mkdirSync(join(cwd, PROJECT_CONFIG_DIR), { recursive: true });
	writeConfigFile(path, emptyConfig());
	return { path, created: true };
}

function globalWriteTarget(): McpWriteTarget {
	return { scope: "global", path: GLOBAL_CONFIG_PATH };
}

function nearestProjectWriteTarget(state: McpState): McpWriteTarget | undefined {
	const nearest = state.projectLayers.at(-1);
	return nearest ? { scope: "project", path: nearest.path } : undefined;
}

function defaultWriteTarget(state: McpState): McpWriteTarget {
	return nearestProjectWriteTarget(state) ?? globalWriteTarget();
}

function formatWriteTarget(target: McpWriteTarget): string {
	return target.scope === "project" ? `project ${formatLayerPath(target.path)}` : `global ${formatLayerPath(target.path)}`;
}

async function chooseWriteTarget(ctx: ExtensionCommandContext, state = safeLoadMcpState(ctx.cwd)): Promise<McpWriteTarget | undefined> {
	if (state.projectLayers.length === 0) return globalWriteTarget();

	const targets = new Map<string, McpWriteTarget>();
	const nearest = nearestProjectWriteTarget(state)!;
	const nearestChoice = `[nearest] project ${formatLayerPath(nearest.path)}`;
	targets.set(nearestChoice, nearest);

	const currentPath = projectConfigPath(ctx.cwd);
	if (!state.projectLayers.some((layer) => layer.path === currentPath)) {
		targets.set(`[create] project ${formatLayerPath(currentPath)}`, { scope: "project", path: currentPath });
	}

	for (const [index, layer] of [...state.projectLayers].reverse().entries()) {
		if (layer.path === nearest.path) continue;
		targets.set(`[ancestor ${index + 1}] project ${formatLayerPath(layer.path)}`, { scope: "project", path: layer.path });
	}

	const globalChoice = `[global] ${formatLayerPath(state.globalPath)}`;
	targets.set(globalChoice, globalWriteTarget());
	const choice = await ctx.ui.select("Persist MCP change to", [...targets.keys()]);
	return choice ? targets.get(choice) : undefined;
}

function resetRuntimeForConfigChange(closeClientsOnChange = true) {
	inventoryCache = undefined;
	hydratedSurfaceTools.clear();
	if (closeClientsOnChange) closeClients();
}

function configuredServers(config: McpConfig): Array<[string, McpServerConfig]> {
	return Object.entries(config.servers ?? {}).filter(([, server]) => isPlainObject(server)) as Array<[string, McpServerConfig]>;
}

function enabledServers(config: McpConfig): Array<[string, McpServerConfig]> {
	return configuredServers(config).filter(([, server]) => server.enabled !== false);
}

function selectedModelTools(server: McpServerConfig): string[] {
	return Array.isArray(server.selectedTools) ? server.selectedTools.filter((tool) => typeof tool === "string") : [];
}

function routerToolsExposed(config: McpConfig): boolean {
	return enabledServers(config).length > 0;
}

function toolSurfacesExposed(config: McpConfig): boolean {
	return enabledServers(config).some(([, server]) => selectedModelTools(server).length > 0);
}

function directToolHydrationNeeded(config: McpConfig): boolean {
	return toolSurfacesExposed(config);
}

function timeoutFor(server: McpServerConfig): number {
	return Math.max(1_000, Math.min(300_000, server.timeoutMs ?? DEFAULT_TIMEOUT_MS));
}

function resolveEnvPlaceholder(value: string): string | undefined {
	const match = value.match(/^\$env:([A-Za-z_][A-Za-z0-9_]*)$/);
	if (!match) return value;
	return process.env[match[1]];
}

function resolveEnvRecord(record: Record<string, string | null> | undefined, omitMissing: boolean): Record<string, string> {
	const resolved: Record<string, string> = {};
	for (const [key, value] of Object.entries(record ?? {})) {
		if (typeof value !== "string") continue;
		const next = resolveEnvPlaceholder(value);
		if (next === undefined && omitMissing) continue;
		resolved[key] = next ?? "";
	}
	return resolved;
}

function linkedSignal(parent: AbortSignal | undefined, timeoutMs: number) {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(new Error(`Timed out after ${timeoutMs}ms`)), timeoutMs);
	const abort = () => controller.abort(parent?.reason ?? new Error("Aborted"));

	if (parent) {
		if (parent.aborted) abort();
		else parent.addEventListener("abort", abort, { once: true });
	}

	return {
		signal: controller.signal,
		cleanup: () => {
			clearTimeout(timer);
			parent?.removeEventListener("abort", abort);
		},
	};
}

function mcpUrl(server: McpServerConfig): string {
	const rawUrl = server.url ?? server.baseUrl;
	if (!rawUrl) throw new Error("remote MCP server is missing url/baseUrl");
	const url = new URL(rawUrl);
	const apiKey = server.apiKeyEnv ? process.env[server.apiKeyEnv] : undefined;
	if (apiKey && url.hostname === "mcp.exa.ai" && !url.searchParams.has("exaApiKey")) {
		url.searchParams.set("exaApiKey", apiKey);
	}
	return url.toString();
}

function headersFor(server: McpServerConfig): Record<string, string> {
	const headers: Record<string, string> = {
		accept: "application/json, text/event-stream",
		"content-type": "application/json",
		...resolveEnvRecord(server.headers, true),
	};

	for (const [header, envName] of Object.entries(server.envHeaders ?? {})) {
		if (typeof envName !== "string") continue;
		const value = process.env[envName];
		if (value) headers[header] = value;
	}

	const apiKey = server.apiKeyEnv ? process.env[server.apiKeyEnv] : undefined;
	if (apiKey && !headers.authorization && !headers.Authorization) {
		headers.authorization = `Bearer ${apiKey}`;
	}

	return headers;
}

async function remoteRequest(serverName: string, server: McpServerConfig, method: string, params: unknown, signal: AbortSignal | undefined): Promise<any> {
	const timeoutMs = timeoutFor(server);
	const linked = linkedSignal(signal, timeoutMs);

	try {
		const response = await fetch(mcpUrl(server), {
			method: "POST",
			signal: linked.signal,
			headers: headersFor(server),
			body: JSON.stringify({
				jsonrpc: "2.0",
				id: Date.now(),
				method,
				params,
			}),
		});

		const raw = await response.text();
		if (!response.ok) throw new Error(`${serverName}: HTTP ${response.status}: ${raw.slice(0, 500)}`);

		const payload = parseJsonOrSse(raw);
		if (payload.error) throw new Error(`${serverName}: ${payload.error.message ?? JSON.stringify(payload.error)}`);
		return payload.result ?? payload;
	} finally {
		linked.cleanup();
	}
}

class StdioMcpClient {
	private process: ChildProcessWithoutNullStreams | undefined;
	private buffer = "";
	private nextId = 1;
	private pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void; timer: NodeJS.Timeout }>();
	private initialized: Promise<void> | undefined;

	constructor(private readonly name: string, private readonly config: McpServerConfig) {}

	async listTools(signal: AbortSignal | undefined): Promise<any> {
		await this.initialize(signal);
		return this.request("tools/list", {}, signal);
	}

	async callTool(tool: string, args: unknown, signal: AbortSignal | undefined): Promise<any> {
		await this.initialize(signal);
		return this.request("tools/call", { name: tool, arguments: args ?? {} }, signal);
	}

	close() {
		for (const pending of this.pending.values()) {
			clearTimeout(pending.timer);
			pending.reject(new Error(`${this.name}: MCP stdio client closed`));
		}
		this.pending.clear();
		this.process?.kill();
		this.process = undefined;
		this.initialized = undefined;
	}

	private async initialize(signal: AbortSignal | undefined) {
		if (this.initialized) return this.initialized;
		this.initialized = this.startAndInitialize(signal);
		return this.initialized;
	}

	private async startAndInitialize(signal: AbortSignal | undefined) {
		if (!this.config.command) throw new Error(`${this.name}: stdio MCP server is missing command`);

		this.process = spawn(this.config.command, this.config.args ?? [], {
			cwd: this.config.cwd,
			env: { ...process.env, ...resolveEnvRecord(this.config.env, true) },
			stdio: ["pipe", "pipe", "pipe"],
		});

		this.process.stdout.on("data", (chunk) => this.onStdout(chunk));
		this.process.stderr.on("data", () => {});
		this.process.on("exit", (code, signalName) => {
			const error = new Error(`${this.name}: MCP stdio server exited (${code ?? signalName ?? "unknown"})`);
			for (const pending of this.pending.values()) {
				clearTimeout(pending.timer);
				pending.reject(error);
			}
			this.pending.clear();
			this.process = undefined;
			this.initialized = undefined;
		});

		await this.request(
			"initialize",
			{
				protocolVersion: this.config.protocolVersion ?? "2025-06-18",
				capabilities: {},
				clientInfo: { name: "pi-mcp-extension", version: "0.2.0" },
			},
			signal,
		);
		this.notify("notifications/initialized", {});
	}

	private onStdout(chunk: Buffer) {
		this.buffer += chunk.toString("utf8");

		while (true) {
			const newline = this.buffer.indexOf("\n");
			if (newline === -1) break;

			const line = this.buffer.slice(0, newline).trim();
			this.buffer = this.buffer.slice(newline + 1);
			if (!line) continue;

			let message: any;
			try {
				message = JSON.parse(line);
			} catch {
				continue;
			}

			if (typeof message.id !== "number") continue;
			const pending = this.pending.get(message.id);
			if (!pending) continue;

			this.pending.delete(message.id);
			clearTimeout(pending.timer);
			if (message.error) pending.reject(new Error(`${this.name}: ${message.error.message ?? JSON.stringify(message.error)}`));
			else pending.resolve(message.result ?? message);
		}
	}

	private notify(method: string, params: unknown) {
		this.process?.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
	}

	private request(method: string, params: unknown, signal: AbortSignal | undefined): Promise<any> {
		const processRef = this.process;
		if (!processRef) throw new Error(`${this.name}: MCP stdio server is not running`);

		const id = this.nextId++;
		const timeoutMs = timeoutFor(this.config);

		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => {
				this.pending.delete(id);
				reject(new Error(`${this.name}: ${method} timed out after ${timeoutMs}ms`));
			}, timeoutMs);

			const abort = () => {
				clearTimeout(timer);
				this.pending.delete(id);
				reject(new Error(`${this.name}: ${method} aborted`));
			};

			if (signal) {
				if (signal.aborted) return abort();
				signal.addEventListener("abort", abort, { once: true });
			}

			this.pending.set(id, {
				resolve: (value) => {
					signal?.removeEventListener("abort", abort);
					resolve(value);
				},
				reject: (error) => {
					signal?.removeEventListener("abort", abort);
					reject(error);
				},
				timer,
			});

			processRef.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
		});
	}
}

function stdioClientKey(name: string, server: McpServerConfig): string {
	return JSON.stringify({
		name,
		command: server.command,
		args: server.args ?? [],
		cwd: server.cwd,
		env: server.env ?? {},
		protocolVersion: server.protocolVersion,
		timeoutMs: server.timeoutMs,
	});
}

function clientFor(name: string, server: McpServerConfig): StdioMcpClient {
	const key = stdioClientKey(name, server);
	let client = stdioClients.get(key);
	if (!client) {
		client = new StdioMcpClient(name, server);
		stdioClients.set(key, client);
	}
	return client;
}

function closeClients() {
	for (const client of stdioClients.values()) client.close();
	stdioClients.clear();
}

function sanitizeToolNamePart(value: string): string {
	const sanitized = value.replace(/[^A-Za-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "");
	if (!sanitized) return "tool";
	if (/^[0-9]/.test(sanitized)) return `_${sanitized}`;
	return sanitized;
}

function directMcpToolName(serverName: string, toolName: string): string {
	return `mcp__${sanitizeToolNamePart(serverName)}__${sanitizeToolNamePart(toolName)}`;
}

function surfaceFromInventoryTool(tool: InventoryTool): McpToolSurfaceConfig {
	return {
		server: tool.server,
		tool: tool.name,
		name: directMcpToolName(tool.server, tool.name),
		description: tool.description,
		inputSchema: tool.inputSchema,
		enabled: true,
		loadedAt: new Date().toISOString(),
	};
}

function minimalSurface(serverName: string, toolName: string): McpToolSurfaceConfig {
	return {
		server: serverName,
		tool: toolName,
		name: directMcpToolName(serverName, toolName),
		description: `${serverName}.${toolName}`,
		enabled: true,
	};
}

function legacySurface(config: McpConfig, serverName: string, toolName: string): McpToolSurfaceConfig | undefined {
	const directName = directMcpToolName(serverName, toolName);
	const direct = config.toolSurfaces?.[directName];
	if (direct?.server === serverName && direct.tool === toolName) return direct;
	return Object.values(config.toolSurfaces ?? {}).find((surface) => surface.server === serverName && surface.tool === toolName);
}

function schemaForSurface(surface: McpToolSurfaceConfig): any {
	const schema = surface.inputSchema;
	if (schema && typeof schema === "object" && !Array.isArray(schema)) {
		const copy = structuredClone(schema) as Record<string, unknown>;
		if (!copy.type && copy.properties) copy.type = "object";
		return copy as any;
	}
	return Type.Any();
}

function surfacePromptDescription(surface: McpToolSurfaceConfig): string {
	return surface.description?.trim() || `Call MCP tool ${surface.server}.${surface.tool}`;
}

function surfaceRegistrationSignature(surface: McpToolSurfaceConfig): string {
	return JSON.stringify({
		server: surface.server,
		tool: surface.tool,
		description: surface.description ?? "",
		inputSchema: surface.inputSchema ?? null,
	});
}

function registerSurfaceTool(pi: ExtensionAPI, surface: McpToolSurfaceConfig): string {
	const name = surface.name || directMcpToolName(surface.server, surface.tool);
	const signature = surfaceRegistrationSignature(surface);
	if (registeredSurfaceTools.get(name) === signature) return name;

	pi.registerTool(
		defineTool({
			name,
			label: `MCP ${surface.server}.${surface.tool}`,
			description: `${surfacePromptDescription(surface)}\n\nRoutes to MCP server "${surface.server}", raw tool "${surface.tool}".`,
			promptSnippet: `${name}: ${surfacePromptDescription(surface)} (MCP ${surface.server}.${surface.tool}).`,
			promptGuidelines: [
				`Use ${name} directly for requests that match ${surface.server}.${surface.tool}; use mcp_inspect only if the arguments are unclear.`,
			],
			parameters: schemaForSurface(surface),
			prepareArguments(args) {
				return args && typeof args === "object" && !Array.isArray(args) ? (args as any) : {};
			},
			async execute(_toolCallId, params, signal, _onUpdate, ctx) {
				const result = await callMcpTool(ctx.cwd, surface.server, surface.tool, params ?? {}, signal);
				return textResult(extractCallText(result), {
					server: surface.server,
					tool: surface.tool,
					surface: name,
				});
			},
		}),
	);

	registeredSurfaceTools.set(name, signature);
	return name;
}

function selectedDirectTools(config: McpConfig): Array<{ serverName: string; server: McpServerConfig; toolName: string; directName: string }> {
	const selected: Array<{ serverName: string; server: McpServerConfig; toolName: string; directName: string }> = [];
	for (const [serverName, server] of enabledServers(config)) {
		for (const toolName of selectedModelTools(server)) {
			selected.push({ serverName, server, toolName, directName: directMcpToolName(serverName, toolName) });
		}
	}
	return selected;
}

function activeSurfaceToolNames(config: McpConfig): string[] {
	if (!toolSurfacesExposed(config)) return [];
	return selectedDirectTools(config)
		.map((selection) => selection.directName)
		.filter((name) => registeredSurfaceTools.has(name))
		.sort((left, right) => left.localeCompare(right));
}

function syncActiveMcpTools(pi: ExtensionAPI, config: McpConfig) {
	const active = new Set(pi.getActiveTools());
	for (const name of registeredSurfaceTools.keys()) active.delete(name);
	for (const name of ROUTER_TOOL_NAMES) active.delete(name);

	for (const name of activeSurfaceToolNames(config)) active.add(name);
	if (routerToolsExposed(config)) {
		for (const name of ROUTER_TOOL_NAMES) active.add(name);
	}
	pi.setActiveTools([...active]);
}

async function hydrateDirectToolSurfaces(pi: ExtensionAPI, cwd: string, signal: AbortSignal | undefined, refresh = false): Promise<Inventory> {
	const config = loadConfig(cwd);
	const inventory = await loadInventory(cwd, signal, refresh);

	for (const selection of selectedDirectTools(config)) {
		const inventoryTool = inventory.tools.find((tool) => tool.server === selection.serverName && tool.name === selection.toolName);
		const surface = inventoryTool
			? surfaceFromInventoryTool(inventoryTool)
			: legacySurface(config, selection.serverName, selection.toolName);
		if (!surface) continue;
		hydratedSurfaceTools.set(selection.directName, surface);
		registerSurfaceTool(pi, surface);
	}

	syncActiveMcpTools(pi, config);
	return inventory;
}

function toolAllowed(server: McpServerConfig, toolName: string): boolean {
	const enabled = server.enabledTools ?? server.allowedTools;
	if (enabled?.length && !enabled.includes(toolName)) return false;
	if (server.disabledTools?.includes(toolName)) return false;
	return true;
}

function modelToolSelected(server: McpServerConfig, toolName: string): boolean {
	return selectedModelTools(server).includes(toolName);
}

function toolVisibleToModelAsDirect(config: McpConfig, serverName: string, toolName: string): boolean {
	const server = config.servers?.[serverName];
	return !!server && server.enabled !== false && modelToolSelected(server, toolName);
}

function normalizeTools(serverName: string, server: McpServerConfig, result: any): InventoryTool[] {
	const rawTools = Array.isArray(result?.tools) ? result.tools : Array.isArray(result) ? result : [];
	return rawTools
		.filter((tool) => typeof tool?.name === "string" && toolAllowed(server, tool.name))
		.map((tool) => ({
			server: serverName,
			name: tool.name,
			description: typeof tool.description === "string" ? tool.description : "",
			inputSchema: tool.inputSchema ?? tool.input_schema ?? tool.parameters ?? {},
		}));
}

async function listServerTools(serverName: string, server: McpServerConfig, signal: AbortSignal | undefined): Promise<InventoryTool[]> {
	const kind = server.type ?? (server.command ? "stdio" : "remote");
	if (kind === "stdio") {
		const result = await clientFor(serverName, server).listTools(signal);
		return normalizeTools(serverName, server, result);
	}

	const result = await remoteRequest(serverName, server, "tools/list", {}, signal);
	return normalizeTools(serverName, server, result);
}

function inventoryCacheKey(cwd: string, config: McpConfig): string {
	return `${cwd}:${JSON.stringify(config.servers ?? {})}`;
}

async function loadInventory(cwd: string, signal: AbortSignal | undefined, refresh = false): Promise<Inventory> {
	const config = loadConfig(cwd);
	const key = inventoryCacheKey(cwd, config);
	if (inventoryCache && inventoryCache.key === key && !refresh) return inventoryCache.inventory;

	const errors: string[] = [];
	const tools: InventoryTool[] = [];
	const results = await Promise.all(
		enabledServers(config).map(async ([serverName, server]) => {
			try {
				return { tools: await listServerTools(serverName, server, signal), error: undefined };
			} catch (error: any) {
				return { tools: [] as InventoryTool[], error: `${serverName}: ${error?.message ?? String(error)}` };
			}
		}),
	);

	for (const result of results) {
		tools.push(...result.tools);
		if (result.error) errors.push(result.error);
	}

	const inventory = { tools, errors, loadedAt: new Date().toISOString() };
	inventoryCache = { key, inventory };
	return inventory;
}

function filterInventoryForEnabledServers(config: McpConfig, inventory: Inventory): Inventory {
	const routerServers = new Set(enabledServers(config).map(([serverName]) => serverName));
	return {
		tools: inventory.tools.filter((tool) => routerServers.has(tool.server)),
		errors: inventory.errors.filter((error) => routerServers.has(error.split(":")[0])),
		loadedAt: inventory.loadedAt,
	};
}

function findTool(inventory: Inventory, server: string | undefined, tool: string): InventoryTool | undefined {
	return inventory.tools.find((candidate) => candidate.name === tool && (!server || candidate.server === server));
}

function matchesQuery(tool: InventoryTool, query: string): boolean {
	const needle = query.toLowerCase();
	return (
		tool.name.toLowerCase().includes(needle) ||
		tool.server.toLowerCase().includes(needle) ||
		tool.description.toLowerCase().includes(needle)
	);
}

function formatInventory(inventory: Inventory, query: string | undefined, limit: number): string {
	const filtered = query ? inventory.tools.filter((tool) => matchesQuery(tool, query)) : inventory.tools;
	const lines = filtered.slice(0, limit).map((tool) => {
		const description = tool.description ? ` - ${tool.description}` : "";
		return `- ${tool.server}.${tool.name}${description}`;
	});

	if (filtered.length > limit) lines.push(`... ${filtered.length - limit} more tool(s) omitted`);
	if (lines.length === 0) lines.push(query ? `No MCP tools matched "${query}".` : "No MCP tools found.");
	if (inventory.errors.length) lines.push("\nMCP server errors:\n" + inventory.errors.map((error) => `- ${error}`).join("\n"));

	return lines.join("\n");
}

function extractCallText(result: any): string {
	const content = result?.content ?? result?.result?.content;
	if (Array.isArray(content)) {
		const text = content
			.map((item) => {
				if (typeof item?.text === "string") return item.text;
				if (typeof item === "string") return item;
				return "";
			})
			.filter(Boolean)
			.join("\n\n");
		if (text.trim()) return text.trim();
	}

	if (typeof result?.text === "string") return result.text;
	if (typeof result === "string") return result;
	return JSON.stringify(result, null, 2);
}

async function callMcpTool(cwd: string, serverName: string, toolName: string, args: unknown, signal: AbortSignal | undefined): Promise<any> {
	const config = loadConfig(cwd);
	const server = config.servers?.[serverName];
	if (!server || server.enabled === false) throw new Error(`MCP server "${serverName}" is not configured or is disabled`);

	const kind = server.type ?? (server.command ? "stdio" : "remote");
	if (kind === "stdio") return clientFor(serverName, server).callTool(toolName, args, signal);
	return remoteRequest(serverName, server, "tools/call", { name: toolName, arguments: args ?? {} }, signal);
}

const mcpSearchTool = defineTool({
	name: "mcp_search",
	label: "MCP Search",
	description: "Search configured MCP servers for available tools without calling them.",
	promptSnippet: "mcp_search: find tools exposed by MCP servers from ~/.pi/agent/mcp.json layered with project .pi/mcp.json. Use refresh=true after config changes.",
	promptGuidelines: [
		"Prefer MCP over websearch when the request matches a configured MCP server domain.",
		"For Google Cloud, Cloud Run, Firebase, Android, Chrome, Go, Gemini, TensorFlow, or web.dev documentation, prefer google-developer-knowledge MCP before websearch.",
		"Use direct mcp__server__tool surfaces when they are available; otherwise use mcp_search, then mcp_inspect, then mcp_call.",
		"Do not guess MCP tool arguments; inspect the schema first when a direct surface schema is not enough.",
	],
	parameters: Type.Object({
		query: Type.Optional(Type.String({ description: "Search text matched against server, tool name, and description" })),
		limit: Type.Optional(Type.Number({ description: "Maximum tools to return" })),
		refresh: Type.Optional(Type.Boolean({ description: "Reload MCP config and tool inventory before searching" })),
	}),

	async execute(_toolCallId, params, signal, _onUpdate, ctx) {
		const config = loadConfig(ctx.cwd);
		const inventory = filterInventoryForEnabledServers(config, await loadInventory(ctx.cwd, signal, params.refresh === true));
		const limit = Math.max(1, Math.min(100, Math.trunc(params.limit ?? 30)));
		return textResult(formatInventory(inventory, params.query, limit), {
			loadedAt: inventory.loadedAt,
			tools: inventory.tools.length,
			errors: inventory.errors.length,
		});
	},
});

const mcpInspectTool = defineTool({
	name: "mcp_inspect",
	label: "MCP Inspect",
	description: "Inspect one MCP tool schema and description before calling it.",
	promptSnippet: "mcp_inspect: inspect the schema for one MCP tool.",
	parameters: Type.Object({
		server: Type.Optional(Type.String({ description: "MCP server name. Optional if the tool name is unique." })),
		tool: Type.String({ description: "MCP tool name" }),
		refresh: Type.Optional(Type.Boolean({ description: "Reload MCP config and tool inventory before inspecting" })),
	}),

	async execute(_toolCallId, params, signal, _onUpdate, ctx) {
		const config = loadConfig(ctx.cwd);
		const inventory = filterInventoryForEnabledServers(config, await loadInventory(ctx.cwd, signal, params.refresh === true));
		const tool = findTool(inventory, params.server, params.tool);
		if (!tool) {
			return textResult(`MCP tool not found: ${params.server ? `${params.server}.` : ""}${params.tool}\n\n${formatInventory(inventory, params.tool, 20)}`, {
				found: false,
			});
		}

		return textResult(JSON.stringify(tool, null, 2), { found: true, server: tool.server, tool: tool.name });
	},
});

const mcpCallTool = defineTool({
	name: "mcp_call",
	label: "MCP Call",
	description: "Call a configured MCP tool by server and tool name.",
	promptSnippet: "mcp_call: execute a tool from a configured MCP server after inspecting its schema.",
	parameters: Type.Object({
		server: Type.String({ description: "Configured MCP server name" }),
		tool: Type.String({ description: "MCP tool name to call" }),
		arguments: Type.Optional(Type.Any({ description: "Arguments object matching the MCP tool input schema" })),
	}),

	async execute(_toolCallId, params, signal, _onUpdate, ctx) {
		const result = await callMcpTool(ctx.cwd, params.server, params.tool, params.arguments ?? {}, signal);
		return textResult(extractCallText(result), {
			server: params.server,
			tool: params.tool,
		});
	},
});

function serverItemId(serverName: string): string {
	return `server:${encodeURIComponent(serverName)}`;
}

function discoverItemId(serverName: string): string {
	return `discover:${encodeURIComponent(serverName)}`;
}

function surfaceItemId(serverName: string, toolName: string): string {
	return `surface:${encodeURIComponent(serverName)}:${encodeURIComponent(toolName)}`;
}

function parseSelectorItemId(id: string): { kind: "server"; server: string } | { kind: "discover"; server: string } | { kind: "surface"; server: string; tool: string } | undefined {
	const [kind, first, second] = id.split(":");
	if (kind === "server" && first) return { kind, server: decodeURIComponent(first) };
	if (kind === "discover" && first) return { kind, server: decodeURIComponent(first) };
	if (kind === "surface" && first && second) return { kind, server: decodeURIComponent(first), tool: decodeURIComponent(second) };
	return undefined;
}

function surfaceIsLoaded(config: McpConfig, serverName: string, toolName: string): boolean {
	return toolVisibleToModelAsDirect(config, serverName, toolName);
}

function configuredSurfaceText(config: McpConfig): string {
	const selected = configuredServers(config)
		.filter(([, server]) => selectedModelTools(server).length)
		.map(([serverName, server]) => `${serverName}: ${selectedModelTools(server).join(", ")}`);
	if (selected.length === 0) return "Selected direct tools: none";
	return `Selected direct tools: ${selected.join(" | ")}`;
}

async function loadServerInventory(cwd: string, serverName: string, signal: AbortSignal | undefined): Promise<Inventory> {
	const config = loadConfig(cwd);
	const server = config.servers?.[serverName];
	if (!server || server.enabled === false) {
		return { tools: [], errors: [`${serverName}: server is not configured or is disabled`], loadedAt: new Date().toISOString() };
	}

	try {
		return { tools: await listServerTools(serverName, server, signal), errors: [], loadedAt: new Date().toISOString() };
	} catch (error: any) {
		return { tools: [], errors: [`${serverName}: ${error?.message ?? String(error)}`], loadedAt: new Date().toISOString() };
	}
}

function selectorSurfaceEntries(config: McpConfig): McpToolSurfaceConfig[] {
	return selectedDirectTools(config)
		.map((selection) => hydratedSurfaceTools.get(selection.directName) ?? legacySurface(config, selection.serverName, selection.toolName) ?? minimalSurface(selection.serverName, selection.toolName))
		.sort((left, right) => `${left.server}.${left.tool}`.localeCompare(`${right.server}.${right.tool}`));
}

function buildMcpSelectorItems(state: McpState): SettingItem[] {
	const items: SettingItem[] = [];
	const config = state.effectiveConfig;
	const surfaces = selectorSurfaceEntries(config);

	for (const [serverName, server] of configuredServers(config).sort(([left], [right]) => left.localeCompare(right))) {
		const enabled = server.enabled !== false;
		const source = state.serverSources[serverName] ?? "effective";
		items.push({
			id: serverItemId(serverName),
			label: `server ${serverName}`,
			description: `${source}; ${server.description || `${server.type ?? (server.command ? "stdio" : "remote")} MCP server`}`,
			currentValue: enabled ? "enabled" : "disabled",
			values: ["enabled", "disabled"],
		});

		if (enabled) {
			items.push({
				id: discoverItemId(serverName),
				label: "  discover tools",
				description: `List tools for ${serverName} and choose which raw tools are included in ${serverName}.selectedTools.`,
				currentValue: "open",
				values: ["open"],
			});
		}

		for (const surface of surfaces.filter((candidate) => candidate.server === serverName)) {
			const directName = surface.name || directMcpToolName(surface.server, surface.tool);
			items.push({
				id: surfaceItemId(surface.server, surface.tool),
				label: `  ${directName}`,
				description: surface.description || `${surface.server}.${surface.tool}`,
				currentValue: modelToolSelected(server, surface.tool) ? "loaded" : "search-only",
				values: ["search-only", "loaded"],
			});
		}
	}

	return items;
}

async function showSettingsSelector(
	ctx: ExtensionCommandContext,
	title: string,
	lines: string[],
	items: SettingItem[],
	onChange: (id: string, newValue: string, close: () => void) => void,
) {
	await ctx.ui.custom<void>((tui, theme, _keybindings, done) => {
		const container = new Container();
		container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));
		container.addChild(new Text(theme.fg("accent", theme.bold(title))));
		for (const line of lines) container.addChild(new Text(theme.fg("dim", line)));

		const close = () => done(undefined);
		const settingsList = new SettingsList(
			items,
			Math.min(Math.max(items.length, 8), 18),
			getSettingsListTheme(),
			(id, newValue) => onChange(id, newValue, close),
			close,
		);

		container.addChild(settingsList);
		container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));

		return {
			render(width: number) {
				return container.render(width);
			},
			invalidate() {
				container.invalidate();
			},
			handleInput(data: string) {
				settingsList.handleInput?.(data);
				tui.requestRender();
			},
		};
	});
}

async function syncAfterMutation(pi: ExtensionAPI, cwd: string, signal: AbortSignal | undefined, config: McpConfig) {
	if (directToolHydrationNeeded(config)) await hydrateDirectToolSurfaces(pi, cwd, signal, true);
	else syncActiveMcpTools(pi, config);
}

async function showMcpSelector(pi: ExtensionAPI, ctx: ExtensionCommandContext) {
	let state = safeLoadMcpState(ctx.cwd);
	const items = buildMcpSelectorItems(state);
	if (items.length === 0) {
		ctx.ui.notify("No MCP servers configured", "warning");
		return;
	}

	let writeTarget: McpWriteTarget | undefined;
	const targetForMutation = async () => {
		writeTarget ??= await chooseWriteTarget(ctx, state);
		return writeTarget;
	};

	await showSettingsSelector(
		ctx,
		"MCP Servers / Tool Surfaces",
		[
			"Enter toggles servers and selectedTools. Router tools can always reach enabled servers. Esc closes.",
			`Layers: global ${state.globalExists ? "present" : "missing/default"}; project ${state.projectLayers.length ? `${state.projectLayers.length} found` : "not initialised"}`,
			`Writes: ${state.projectLayers.length ? "ask on first change" : formatWriteTarget(globalWriteTarget())}`,
			configuredSurfaceText(state.effectiveConfig),
		],
		items,
		(id, newValue, close) => {
			void (async () => {
				const parsed = parseSelectorItemId(id);
				if (!parsed) return;

				if (parsed.kind === "discover") {
					close();
					void showServerToolSelector(pi, ctx, parsed.server, writeTarget);
					return;
				}

				const target = await targetForMutation();
				if (!target) return;
				state = safeLoadMcpState(ctx.cwd);

				if (parsed.kind === "server") {
					const enabled = newValue === "enabled";
					state = saveServerEnabledOverride(ctx.cwd, target, parsed.server, enabled);
					await syncAfterMutation(pi, ctx.cwd, ctx.signal, state.effectiveConfig);
					ctx.ui.notify(`MCP server ${parsed.server} ${enabled ? "enabled" : "disabled"} in ${formatWriteTarget(target)}`, "info");
					return;
				}

				const server = state.effectiveConfig.servers?.[parsed.server];
				if (!server) return;
				const selected = selectedModelTools(server);
				const next = newValue === "loaded"
					? [...selected, parsed.tool]
					: selected.filter((candidate) => candidate !== parsed.tool);
				state = saveSelectedToolsOverride(ctx.cwd, target, parsed.server, next);
				await syncAfterMutation(pi, ctx.cwd, ctx.signal, state.effectiveConfig);
				ctx.ui.notify(`${newValue === "loaded" ? "Loaded" : "Unloaded"} ${directMcpToolName(parsed.server, parsed.tool)} in ${formatWriteTarget(target)}`, "info");
			})().catch((error: any) => ctx.ui.notify(`MCP update failed: ${error?.message ?? String(error)}`, "error"));
		},
	);
}

async function showServerToolSelector(pi: ExtensionAPI, ctx: ExtensionCommandContext, serverName: string, writeTarget?: McpWriteTarget) {
	if (!writeTarget) writeTarget = await chooseWriteTarget(ctx);
	if (!writeTarget) return;

	ctx.ui.notify(`Loading MCP tools for ${serverName}...`, "info");
	let state = safeLoadMcpState(ctx.cwd);
	const inventory = await loadServerInventory(ctx.cwd, serverName, ctx.signal);
	if (inventory.errors.length) {
		await ctx.ui.editor(`MCP ${serverName} error`, inventory.errors.join("\n"));
		return;
	}
	if (inventory.tools.length === 0) {
		ctx.ui.notify(`MCP server ${serverName} returned no tools`, "warning");
		return;
	}

	const items: SettingItem[] = inventory.tools
		.sort((left, right) => left.name.localeCompare(right.name))
		.map((tool) => ({
			id: surfaceItemId(serverName, tool.name),
			label: directMcpToolName(serverName, tool.name),
			description: tool.description || `${serverName}.${tool.name}`,
			currentValue: surfaceIsLoaded(state.effectiveConfig, serverName, tool.name) ? "loaded" : "search-only",
			values: ["search-only", "loaded"],
		}));

	await showSettingsSelector(
		ctx,
		`MCP Tools: ${serverName}`,
		[
			"Enter/Space toggles search-only vs loaded direct tool surface. Esc closes.",
			`Writes: ${formatWriteTarget(writeTarget)}`,
		],
		items,
		(id, newValue, _close) => {
			void (async () => {
				const parsed = parseSelectorItemId(id);
				if (!parsed || parsed.kind !== "surface") return;

				state = safeLoadMcpState(ctx.cwd);
				const server = state.effectiveConfig.servers?.[parsed.server];
				const tool = inventory.tools.find((candidate) => candidate.server === parsed.server && candidate.name === parsed.tool);
				if (!server || !tool) return;

				const directName = directMcpToolName(parsed.server, parsed.tool);
				const selected = selectedModelTools(server);
				const next = newValue === "loaded"
					? [...selected, parsed.tool]
					: selected.filter((candidate) => candidate !== parsed.tool);

				if (newValue === "loaded") {
					const surface = surfaceFromInventoryTool(tool);
					hydratedSurfaceTools.set(directName, surface);
					registerSurfaceTool(pi, surface);
				}

				state = saveSelectedToolsOverride(ctx.cwd, writeTarget!, parsed.server, next);
				await syncAfterMutation(pi, ctx.cwd, ctx.signal, state.effectiveConfig);
				ctx.ui.notify(`${newValue === "loaded" ? "Loaded" : "Unloaded"} ${directName} in ${formatWriteTarget(writeTarget!)}`, "info");
			})().catch((error: any) => ctx.ui.notify(`MCP tool update failed: ${error?.message ?? String(error)}`, "error"));
		},
	);
}

function formatConfigServerLine(state: McpState, serverName: string, server: McpServerConfig): string {
	const kind = server.type ?? (server.command ? "stdio" : "remote");
	const target = server.command ? `${server.command} ${(server.args ?? []).join(" ")}`.trim() : (server.url ?? server.baseUrl ?? "(no url)");
	const stateText = server.enabled === false ? "disabled" : "enabled";
	const selected = selectedModelTools(server).length ? `, selectedTools=${selectedModelTools(server).join(",")}` : "";
	const source = state.serverSources[serverName] ?? "effective";
	return `- ${serverName}: ${stateText}, ${kind}, source=${source}${selected}, ${target}`;
}

function hydratedSurfaceCount(config: McpConfig): number {
	return selectedDirectTools(config).filter((selection) => hydratedSurfaceTools.has(selection.directName) || legacySurface(config, selection.serverName, selection.toolName)).length;
}

function envPlaceholderName(value: string): string | undefined {
	return value.match(/^\$env:([A-Za-z_][A-Za-z0-9_]*)$/)?.[1];
}

function formatEnvLikeRecord(label: string, record: Record<string, string | null> | undefined): string[] {
	const entries = Object.entries(record ?? {}).filter(([, value]) => typeof value === "string") as Array<[string, string]>;
	if (entries.length === 0) return [];
	const lines = [`  ${label}:`];
	for (const [key, value] of entries.sort(([left], [right]) => left.localeCompare(right))) {
		const envName = envPlaceholderName(value);
		if (envName) lines.push(`    - ${key}: $env:${envName} (${process.env[envName] ? "present" : "missing"})`);
		else lines.push(`    - ${key}: literal (${value ? "set" : "empty"})`);
	}
	return lines;
}

function formatEnvHeaders(server: McpServerConfig): string[] {
	const entries = Object.entries(server.envHeaders ?? {}).filter(([, value]) => typeof value === "string") as Array<[string, string]>;
	if (entries.length === 0) return [];
	const lines = ["  envHeaders:"];
	for (const [header, envName] of entries.sort(([left], [right]) => left.localeCompare(right))) {
		lines.push(`    - ${header}: $env:${envName} (${process.env[envName] ? "present" : "missing"})`);
	}
	return lines;
}

function formatServerRuntimeDiagnostics(server: McpServerConfig): string[] {
	const lines: string[] = [];
	if (server.apiKeyEnv) lines.push(`  apiKeyEnv: $env:${server.apiKeyEnv} (${process.env[server.apiKeyEnv] ? "present" : "missing"})`);
	lines.push(...formatEnvLikeRecord("env", server.env));
	lines.push(...formatEnvLikeRecord("headers", server.headers));
	lines.push(...formatEnvHeaders(server));
	return lines;
}

function formatDiagnostics(diagnostics: McpDiagnostic[]): string[] {
	if (diagnostics.length === 0) return ["(none)"];
	return diagnostics.map((item) => `- ${item.level.toUpperCase()} ${compactMiddle(item.path, 120)}: ${item.message}`);
}

function formatServerLayerContributors(state: McpState, serverName: string): string[] {
	const lines: string[] = [];
	const contributors: string[] = [];
	if (state.globalConfig.servers?.[serverName]) contributors.push(`global ${formatLayerPath(state.globalPath)}`);
	for (const [index, layer] of state.projectLayers.entries()) {
		const server = layer.config.servers?.[serverName];
		if (!server) continue;
		const enabled = isPlainObject(server) && typeof server.enabled === "boolean" ? `, enabled=${server.enabled}` : "";
		contributors.push(`project[${index}] ${formatLayerPath(layer.path)}${enabled}`);
	}
	if (contributors.length) {
		lines.push("  defined by:");
		for (const contributor of contributors) lines.push(`    - ${contributor}`);
	}
	return lines;
}

function formatMcpStatus(state: McpState, inventory: Inventory): string {
	const config = state.effectiveConfig;
	const lines: string[] = [];
	lines.push("# MCP Status");
	lines.push("");
	lines.push("## Config Layers");
	lines.push(`- global: ${formatLayerPath(state.globalPath)} (${state.globalExists ? "present" : "missing; built-in defaults active"})`);
	if (state.projectLayers.length === 0) {
		lines.push("- project: none found walking upward from cwd");
	} else {
		for (const [index, layer] of state.projectLayers.entries()) {
			const nearest = index === state.projectLayers.length - 1 ? ", nearest" : "";
			lines.push(`- project[${index}]: ${formatLayerPath(layer.path)} (root=${formatLayerPath(layer.root)}${nearest})`);
		}
	}
	lines.push(`- effective write default: ${formatWriteTarget(defaultWriteTarget(state))}`);
	lines.push("");
	lines.push("## Config Diagnostics");
	lines.push(...formatDiagnostics(state.diagnostics));
	lines.push("");
	lines.push("## Exposure");
	lines.push(`- model can use mcp_search/mcp_inspect/mcp_call: ${routerToolsExposed(config) ? "yes, across all enabled servers" : "no, no servers enabled"}`);
	lines.push(`- model can use direct MCP tools: ${toolSurfacesExposed(config) ? "selectedTools only" : "no selectedTools configured"}`);
	lines.push(`- manual /mcp search/inspect/call: yes`);
	lines.push(`Loaded: ${inventory.loadedAt}`);
	lines.push(`Searchable tools: ${inventory.tools.length}`);
	lines.push(`Selected direct tools: ${selectedDirectTools(config).length}`);
	lines.push(`Hydrated direct tool surfaces: ${hydratedSurfaceCount(config)}`);
	lines.push(`Exposed direct tool surfaces: ${activeSurfaceToolNames(config).length}`);
	lines.push("");
	lines.push("## Servers");
	for (const [serverName, server] of configuredServers(config).sort(([left], [right]) => left.localeCompare(right))) {
		lines.push(formatConfigServerLine(state, serverName, server));
		if (server.description) lines.push(`  ${server.description}`);
		lines.push(...formatServerLayerContributors(state, serverName));
		lines.push(...formatServerRuntimeDiagnostics(server));
	}
	lines.push("");
	lines.push("## Direct Tool Surfaces");
	const selected = selectedDirectTools(config);
	if (selected.length === 0) {
		lines.push("(none)");
	} else {
		for (const selection of selected) {
			const surface = hydratedSurfaceTools.get(selection.directName) ?? legacySurface(config, selection.serverName, selection.toolName) ?? minimalSurface(selection.serverName, selection.toolName);
			const hydrated = hydratedSurfaceTools.has(selection.directName) || !!legacySurface(config, selection.serverName, selection.toolName) ? "hydrated" : "pending discovery";
			lines.push(`- ${surface.name || selection.directName}: loaded, ${hydrated} -> ${surface.server}.${surface.tool}`);
			if (surface.description) lines.push(`  ${surface.description}`);
		}
	}
	lines.push("");
	lines.push("## Inventory Errors");
	if (inventory.errors.length === 0) {
		lines.push("(none)");
	} else {
		for (const error of inventory.errors) lines.push(`- ${error}`);
	}
	lines.push("");
	lines.push("## Inventory By Server");
	const counts = new Map<string, number>();
	for (const tool of inventory.tools) counts.set(tool.server, (counts.get(tool.server) ?? 0) + 1);
	for (const [serverName] of configuredServers(config).sort(([left], [right]) => left.localeCompare(right))) {
		lines.push(`- ${serverName}: ${counts.get(serverName) ?? 0} tool(s)`);
	}
	return lines.join("\n");
}

async function runManualMcpSearch(ctx: ExtensionCommandContext, query: string) {
	ctx.ui.notify("Searching MCP inventory...", "info");
	const inventory = await loadInventory(ctx.cwd, ctx.signal, false);
	const title = query ? `MCP search: ${query}` : "MCP search";
	await ctx.ui.editor(title, formatInventory(inventory, query || undefined, 100));
}

async function runManualMcpInspect(ctx: ExtensionCommandContext, serverName: string, toolName: string) {
	ctx.ui.notify(`Inspecting ${serverName}.${toolName}...`, "info");
	const inventory = await loadServerInventory(ctx.cwd, serverName, ctx.signal);
	const tool = inventory.tools.find((candidate) => candidate.name === toolName);
	if (!tool) {
		await ctx.ui.editor(`MCP inspect failed: ${serverName}.${toolName}`, inventory.errors.length ? inventory.errors.join("\n") : `Tool not found: ${serverName}.${toolName}`);
		return;
	}
	await ctx.ui.editor(`MCP inspect: ${serverName}.${toolName}`, JSON.stringify(tool, null, 2));
}

async function runManualMcpCall(ctx: ExtensionCommandContext, serverName: string, toolName: string, argsJson: string) {
	let args: unknown = {};
	if (argsJson.trim()) {
		try {
			args = JSON.parse(argsJson);
		} catch (error: any) {
			ctx.ui.notify(`MCP call arguments must be JSON: ${error?.message ?? String(error)}`, "error");
			return;
		}
	}

	ctx.ui.notify(`Calling ${serverName}.${toolName}...`, "info");
	const result = await callMcpTool(ctx.cwd, serverName, toolName, args, ctx.signal);
	await ctx.ui.editor(`MCP call: ${serverName}.${toolName}`, extractCallText(result));
}

function findDirectToolSelection(config: McpConfig, directName: string): { server: string; tool: string } | undefined {
	const selection = selectedDirectTools(config).find((candidate) => candidate.directName === directName);
	if (selection) return { server: selection.serverName, tool: selection.toolName };
	return undefined;
}

export default function (pi: ExtensionAPI) {
	pi.registerTool(mcpSearchTool);
	pi.registerTool(mcpInspectTool);
	pi.registerTool(mcpCallTool);

	pi.on("session_start", (_event, ctx) => {
		const config = safeLoadMcpState(ctx.cwd).effectiveConfig;
		syncActiveMcpTools(pi, config);
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		const config = safeLoadMcpState(ctx.cwd).effectiveConfig;
		if (directToolHydrationNeeded(config)) {
			await hydrateDirectToolSurfaces(pi, ctx.cwd, ctx.signal, false);
		} else {
			syncActiveMcpTools(pi, config);
		}
	});

	pi.registerCommand("mcp", {
		description: "Open MCP selector or manage inventory: /mcp | /mcp init | /mcp search [query] | /mcp status | /mcp tools <server> | /mcp reload",
		handler: async (args, ctx) => {
			const command = args.trim() || "status";

			if (!args.trim()) {
				await showMcpSelector(pi, ctx);
				return;
			}

			if (command === "reload") {
				resetRuntimeForConfigChange();
				const config = safeLoadMcpState(ctx.cwd).effectiveConfig;
				syncActiveMcpTools(pi, config);
				if (directToolHydrationNeeded(config)) await hydrateDirectToolSurfaces(pi, ctx.cwd, ctx.signal, true);
				ctx.ui.notify("MCP config layers and clients reloaded", "info");
				return;
			}

			if (command === "init") {
				const result = initProjectConfig(ctx.cwd);
				if (result.created) {
					resetRuntimeForConfigChange();
					ctx.ui.notify(`Created project MCP config: ${result.path}`, "info");
				} else {
					ctx.ui.notify(`Project MCP config already exists: ${result.path}`, "info");
				}
				return;
			}

			if (command === "status") {
				ctx.ui.notify("Loading MCP status...", "info");
				const state = safeLoadMcpState(ctx.cwd);
				const configLoadFailed = state.diagnostics.some((item) => item.path === "config");
				const inventory = configLoadFailed
					? { tools: [], errors: ["Config could not be fully loaded; see Config Diagnostics."], loadedAt: new Date().toISOString() }
					: directToolHydrationNeeded(state.effectiveConfig)
						? await hydrateDirectToolSurfaces(pi, ctx.cwd, ctx.signal, true)
						: await loadInventory(ctx.cwd, ctx.signal, true);
				await ctx.ui.editor("MCP status", formatMcpStatus(safeLoadMcpState(ctx.cwd), inventory));
				return;
			}

			if (command === "search" || command.startsWith("search ")) {
				await runManualMcpSearch(ctx, command === "search" ? "" : command.slice("search ".length).trim());
				return;
			}

			if (command.startsWith("inspect ")) {
				const [, serverName, toolName] = command.match(/^inspect\s+(\S+)\s+(.+)$/) ?? [];
				if (!serverName || !toolName) {
					ctx.ui.notify("Usage: /mcp inspect <server> <tool>", "warning");
					return;
				}
				await runManualMcpInspect(ctx, serverName, toolName);
				return;
			}

			if (command.startsWith("call ")) {
				const [, serverName, toolName, argsJson = ""] = command.match(/^call\s+(\S+)\s+(\S+)(?:\s+([\s\S]+))?$/) ?? [];
				if (!serverName || !toolName) {
					ctx.ui.notify("Usage: /mcp call <server> <tool> [json args]", "warning");
					return;
				}
				await runManualMcpCall(ctx, serverName, toolName, argsJson);
				return;
			}

			if (command.startsWith("tools ")) {
				const serverName = command.slice("tools ".length).trim();
				if (!serverName) {
					ctx.ui.notify("Usage: /mcp tools <server>", "warning");
					return;
				}
				await showServerToolSelector(pi, ctx, serverName);
				return;
			}

			if (command.startsWith("load ")) {
				const [, serverName, toolName] = command.match(/^load\s+(\S+)\s+(.+)$/) ?? [];
				if (!serverName || !toolName) {
					ctx.ui.notify("Usage: /mcp load <server> <tool>", "warning");
					return;
				}
				const state = safeLoadMcpState(ctx.cwd);
				const writeTarget = await chooseWriteTarget(ctx, state);
				if (!writeTarget) return;
				const inventory = await loadServerInventory(ctx.cwd, serverName, ctx.signal);
				const tool = inventory.tools.find((candidate) => candidate.name === toolName);
				if (!tool) {
					await ctx.ui.editor(`MCP ${serverName} load failed`, inventory.errors.length ? inventory.errors.join("\n") : `Tool not found: ${serverName}.${toolName}`);
					return;
				}
				const server = state.effectiveConfig.servers?.[serverName];
				if (!server) {
					ctx.ui.notify(`MCP server not found: ${serverName}`, "warning");
					return;
				}
				const surface = surfaceFromInventoryTool(tool);
				hydratedSurfaceTools.set(surface.name!, surface);
				registerSurfaceTool(pi, surface);
				const nextState = saveSelectedToolsOverride(ctx.cwd, writeTarget, serverName, [...selectedModelTools(server), toolName]);
				await syncAfterMutation(pi, ctx.cwd, ctx.signal, nextState.effectiveConfig);
				ctx.ui.notify(`Loaded ${surface.name} in ${formatWriteTarget(writeTarget)}`, "info");
				return;
			}

			if (command.startsWith("unload ")) {
				const directName = command.slice("unload ".length).trim();
				if (!directName) {
					ctx.ui.notify("Usage: /mcp unload <mcp__server__tool>", "warning");
					return;
				}
				const state = safeLoadMcpState(ctx.cwd);
				const writeTarget = await chooseWriteTarget(ctx, state);
				if (!writeTarget) return;
				const selection = findDirectToolSelection(state.effectiveConfig, directName);
				if (!selection) {
					ctx.ui.notify(`Direct MCP surface not found: ${directName}`, "warning");
					return;
				}
				const server = state.effectiveConfig.servers?.[selection.server];
				if (!server) {
					ctx.ui.notify(`MCP server not found: ${selection.server}`, "warning");
					return;
				}
				const nextState = saveSelectedToolsOverride(ctx.cwd, writeTarget, selection.server, selectedModelTools(server).filter((candidate) => candidate !== selection.tool));
				await syncAfterMutation(pi, ctx.cwd, ctx.signal, nextState.effectiveConfig);
				ctx.ui.notify(`Unloaded ${directName} in ${formatWriteTarget(writeTarget)}`, "info");
				return;
			}

			ctx.ui.notify("Usage: /mcp | /mcp init | /mcp status | /mcp search [query] | /mcp inspect <server> <tool> | /mcp call <server> <tool> [json] | /mcp tools <server> | /mcp load <server> <tool> | /mcp unload <mcp__server__tool> | /mcp reload", "warning");
		},
	});

	pi.on("session_shutdown", async () => {
		closeClients();
	});
}
