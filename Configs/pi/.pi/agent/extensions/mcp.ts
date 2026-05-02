import { Type } from "@mariozechner/pi-ai";
import { DynamicBorder, defineTool, getAgentDir, getSettingsListTheme, type ExtensionAPI, type ExtensionCommandContext } from "@mariozechner/pi-coding-agent";
import { Container, type SettingItem, SettingsList, Text } from "@mariozechner/pi-tui";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const DEFAULT_TIMEOUT_MS = 30_000;
const CONFIG_PATH = join(getAgentDir(), "mcp.json");

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
	env?: Record<string, string>;
	headers?: Record<string, string>;
	envHeaders?: Record<string, string>;
	apiKeyEnv?: string;
	timeoutMs?: number;
	protocolVersion?: string;
	enabledTools?: string[];
	allowedTools?: string[];
	disabledTools?: string[];
};

type McpConfig = {
	servers?: Record<string, McpServerConfig>;
	toolSurfaces?: Record<string, McpToolSurfaceConfig>;
};

type InventoryTool = {
	server: string;
	name: string;
	description: string;
	inputSchema: unknown;
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

type Inventory = {
	tools: InventoryTool[];
	errors: string[];
	loadedAt: string;
};

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
	return {
		servers: {
			exa: {
				type: "remote",
				url: "https://mcp.exa.ai/mcp",
				apiKeyEnv: "EXA_API_KEY",
				enabled: true,
				timeoutMs: 25_000,
			},
		},
	};
}

function loadConfig(): McpConfig {
	if (!existsSync(CONFIG_PATH)) return defaultConfig();
	const raw = readFileSync(CONFIG_PATH, "utf8");
	const parsed = JSON.parse(stripJsonComments(raw)) as McpConfig;
	if (!parsed.servers) parsed.servers = {};
	if (!parsed.toolSurfaces) parsed.toolSurfaces = {};
	return parsed;
}

function saveConfig(config: McpConfig) {
	if (!config.servers) config.servers = {};
	if (!config.toolSurfaces) config.toolSurfaces = {};
	writeFileSync(CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`, "utf8");
}

function safeLoadConfig(): McpConfig {
	try {
		return loadConfig();
	} catch {
		return defaultConfig();
	}
}

function enabledServers(config: McpConfig): Array<[string, McpServerConfig]> {
	return Object.entries(config.servers ?? {}).filter(([, server]) => server.enabled !== false);
}

function timeoutFor(server: McpServerConfig): number {
	return Math.max(1_000, Math.min(300_000, server.timeoutMs ?? DEFAULT_TIMEOUT_MS));
}

function resolveEnvPlaceholder(value: string): string | undefined {
	const match = value.match(/^\$env:([A-Za-z_][A-Za-z0-9_]*)$/);
	if (!match) return value;
	return process.env[match[1]];
}

function resolveEnvRecord(record: Record<string, string> | undefined, omitMissing: boolean): Record<string, string> {
	const resolved: Record<string, string> = {};
	for (const [key, value] of Object.entries(record ?? {})) {
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
				clientInfo: { name: "pi-mcp-extension", version: "0.1.0" },
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

const stdioClients = new Map<string, StdioMcpClient>();
let inventoryCache: Inventory | undefined;
const registeredSurfaceTools = new Set<string>();
const ROUTER_TOOL_NAMES = ["mcp_search", "mcp_inspect", "mcp_call"];

function selectedModelTools(server: McpServerConfig): string[] {
	return server.selectedTools ?? [];
}

function routerToolsExposed(config: McpConfig): boolean {
	return enabledServers(config).length > 0;
}

function toolSurfacesExposed(config: McpConfig): boolean {
	return enabledServers(config).some(([, server]) => selectedModelTools(server).length > 0);
}

function directToolHydrationNeeded(config: McpConfig): boolean {
	return enabledServers(config).some(([, server]) => selectedModelTools(server).length > 0);
}

function clientFor(name: string, server: McpServerConfig): StdioMcpClient {
	let client = stdioClients.get(name);
	if (!client) {
		client = new StdioMcpClient(name, server);
		stdioClients.set(name, client);
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
	const description = surface.description?.trim();
	return description || `Call MCP tool ${surface.server}.${surface.tool}`;
}

function registerSurfaceTool(pi: ExtensionAPI, surface: McpToolSurfaceConfig): string {
	const name = surface.name || directMcpToolName(surface.server, surface.tool);
	if (registeredSurfaceTools.has(name)) return name;

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
			async execute(_toolCallId, params, signal) {
				const result = await callMcpTool(surface.server, surface.tool, params ?? {}, signal);
				return textResult(extractCallText(result), {
					server: surface.server,
					tool: surface.tool,
					surface: name,
				});
			},
		}),
	);

	registeredSurfaceTools.add(name);
	return name;
}

function registerConfiguredSurfaceTools(pi: ExtensionAPI) {
	const config = safeLoadConfig();
	for (const surface of Object.values(config.toolSurfaces ?? {})) {
		if (surface.enabled === false) continue;
		if (!surface.server || !surface.tool) continue;
		registerSurfaceTool(pi, surface);
	}
}

async function hydrateDirectToolSurfaces(pi: ExtensionAPI, signal: AbortSignal | undefined, refresh = false): Promise<Inventory> {
	const config = loadConfig();
	const inventory = await loadInventory(signal, refresh);

	if (!config.toolSurfaces) config.toolSurfaces = {};
	let changed = false;
	for (const tool of inventory.tools) {
		const server = config.servers?.[tool.server];
		if (!server) continue;
		const surface = surfaceFromInventoryTool(tool);
		const name = surface.name!;
		if (modelToolSelected(server, tool.name)) {
			const existing = config.toolSurfaces[name];
			config.toolSurfaces[name] = {
				...surface,
				loadedAt: existing?.loadedAt ?? surface.loadedAt,
			};
			registerSurfaceTool(pi, config.toolSurfaces[name]);
			changed = true;
		}
	}
	if (changed) saveConfig(config);
	syncActiveMcpTools(pi, config);
	return inventory;
}

function activeSurfaceToolNames(config: McpConfig): string[] {
	if (!toolSurfacesExposed(config)) return [];
	const names = new Set(Object.values(config.toolSurfaces ?? {})
		.filter((surface) => surface.enabled !== false && surface.server && surface.tool && toolVisibleToModelAsDirect(config, surface.server, surface.tool))
		.map((surface) => surface.name || directMcpToolName(surface.server, surface.tool)));
	return [...names].sort((left, right) => left.localeCompare(right));
}

function syncActiveMcpTools(pi: ExtensionAPI, config: McpConfig) {
	const active = new Set(pi.getActiveTools());
	for (const name of registeredSurfaceTools) {
		active.delete(name);
	}
	for (const name of ROUTER_TOOL_NAMES) {
		active.delete(name);
	}
	for (const name of activeSurfaceToolNames(config)) {
		active.add(name);
	}
	if (routerToolsExposed(config)) {
		for (const name of ROUTER_TOOL_NAMES) active.add(name);
	}
	pi.setActiveTools([...active]);
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

function ensureModelTool(server: McpServerConfig, toolName: string) {
	const tools = new Set(selectedModelTools(server));
	tools.add(toolName);
	server.selectedTools = [...tools].sort((left, right) => left.localeCompare(right));
}

function removeModelTool(server: McpServerConfig, toolName: string) {
	const next = selectedModelTools(server).filter((candidate) => candidate !== toolName);
	if (next.length) server.selectedTools = next;
	else delete server.selectedTools;
}

function toolVisibleToModelAsDirect(config: McpConfig, serverName: string, toolName: string): boolean {
	const server = config.servers?.[serverName];
	if (!server || server.enabled === false) return false;
	return modelToolSelected(server, toolName);
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

async function loadInventory(signal: AbortSignal | undefined, refresh = false): Promise<Inventory> {
	if (inventoryCache && !refresh) return inventoryCache;

	const config = loadConfig();
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

	inventoryCache = { tools, errors, loadedAt: new Date().toISOString() };
	return inventoryCache;
}

function filterInventoryForEnabledServers(config: McpConfig, inventory: Inventory): Inventory {
	const routerServers = new Set(
		enabledServers(config)
			.map(([serverName]) => serverName),
	);
	return {
		tools: inventory.tools.filter((tool) => routerServers.has(tool.server)),
		errors: inventory.errors.filter((error) => {
			const serverName = error.split(":")[0];
			return routerServers.has(serverName);
		}),
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

function formatServerPromptSummary(): string {
	const config = safeLoadConfig();
	const lines = Object.entries(config.servers ?? {})
		.filter(([, server]) => server.enabled !== false)
		.map(([name, server]) => {
			const description = server.description?.trim() || "configured MCP server";
			return `${name}: ${description}`;
		});

	return lines.length > 0 ? lines.join("; ") : "no configured MCP servers";
}

function formatSurfacePromptSummary(): string {
	const config = safeLoadConfig();
	const surfaces = activeSurfaceToolNames(config);
	return surfaces.length > 0 ? surfaces.join(", ") : "none loaded";
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

async function callMcpTool(serverName: string, toolName: string, args: unknown, signal: AbortSignal | undefined): Promise<any> {
	const config = loadConfig();
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
	promptSnippet: `mcp_search: find tools exposed by configured MCP servers. Servers: ${formatServerPromptSummary()}. Direct MCP tool surfaces currently loaded: ${formatSurfacePromptSummary()}.`,
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

	async execute(_toolCallId, params, signal) {
		const config = loadConfig();
		const inventory = filterInventoryForEnabledServers(config, await loadInventory(signal, params.refresh === true));
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

	async execute(_toolCallId, params, signal) {
		const config = loadConfig();
		const inventory = filterInventoryForEnabledServers(config, await loadInventory(signal, params.refresh === true));
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

	async execute(_toolCallId, params, signal) {
		const result = await callMcpTool(params.server, params.tool, params.arguments ?? {}, signal);
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
	const directName = directMcpToolName(serverName, toolName);
	const surface = config.toolSurfaces?.[directName];
	return surface?.enabled !== false && surface?.server === serverName && surface?.tool === toolName && toolVisibleToModelAsDirect(config, serverName, toolName);
}

function configuredSurfaceText(config: McpConfig): string {
	const selected = Object.entries(config.servers ?? {})
		.filter(([, server]) => selectedModelTools(server).length)
		.map(([serverName, server]) => `${serverName}: ${selectedModelTools(server).join(", ")}`);
	if (selected.length === 0) return "Selected direct tools: none";
	return `Selected direct tools: ${selected.join(" | ")}`;
}

async function loadServerInventory(serverName: string, signal: AbortSignal | undefined): Promise<Inventory> {
	const config = loadConfig();
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

function buildMcpSelectorItems(config: McpConfig): SettingItem[] {
	const items: SettingItem[] = [];
	const surfaces = Object.values(config.toolSurfaces ?? {})
		.filter((surface) => surface.server && surface.tool)
		.sort((left, right) => `${left.server}.${left.tool}`.localeCompare(`${right.server}.${right.tool}`));

	for (const [serverName, server] of Object.entries(config.servers ?? {}).sort(([left], [right]) => left.localeCompare(right))) {
		const enabled = server.enabled !== false;
		items.push({
			id: serverItemId(serverName),
			label: `server ${serverName}`,
			description: server.description || `${server.type ?? (server.command ? "stdio" : "remote")} MCP server`,
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

async function showMcpSelector(pi: ExtensionAPI, ctx: ExtensionCommandContext) {
	let config = loadConfig();
	const items = buildMcpSelectorItems(config);
	if (items.length === 0) {
		ctx.ui.notify("No MCP servers configured", "warning");
		return;
	}

	await ctx.ui.custom<void>((tui, theme, _keybindings, done) => {
		const container = new Container();
		container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));
		container.addChild(new Text(theme.fg("accent", theme.bold("MCP Servers / Tool Surfaces"))));
		container.addChild(new Text(theme.fg("dim", "Enter toggles servers and selectedTools. Router tools can always reach enabled servers. Esc closes.")));
		container.addChild(new Text(theme.fg("dim", configuredSurfaceText(config))));

		const settingsList = new SettingsList(
			items,
			Math.min(Math.max(items.length, 8), 18),
			getSettingsListTheme(),
			(id, newValue) => {
				const parsed = parseSelectorItemId(id);
				if (!parsed) return;

				config = loadConfig();
				if (!config.servers) config.servers = {};
				if (!config.toolSurfaces) config.toolSurfaces = {};

				if (parsed.kind === "server") {
					const server = config.servers[parsed.server];
					if (!server) return;
					server.enabled = newValue === "enabled";
					if (!server.enabled) {
						for (const surface of Object.values(config.toolSurfaces)) {
							if (surface.server === parsed.server) surface.enabled = false;
						}
					}
					saveConfig(config);
					inventoryCache = undefined;
					closeClients();
					syncActiveMcpTools(pi, config);
					ctx.ui.notify(`MCP server ${parsed.server} ${server.enabled ? "enabled" : "disabled"}`, "info");
					return;
				}

				if (parsed.kind === "discover") {
					done(undefined);
					void showServerToolSelector(pi, ctx, parsed.server);
					return;
				}

				const directName = directMcpToolName(parsed.server, parsed.tool);
				const server = config.servers[parsed.server];
				if (!server) return;
				if (newValue === "loaded") {
					const existing = config.toolSurfaces[directName];
					if (!existing) {
						ctx.ui.notify(`Run /mcp tools ${parsed.server} to discover ${parsed.server}.${parsed.tool} before loading it`, "warning");
						return;
					}
					const surface = { ...existing, enabled: true };
					config.toolSurfaces[directName] = surface;
					ensureModelTool(server, parsed.tool);
					registerSurfaceTool(pi, surface);
					saveConfig(config);
					syncActiveMcpTools(pi, config);
					ctx.ui.notify(`Loaded ${directName}`, "info");
				} else {
					removeModelTool(server, parsed.tool);
					if (config.toolSurfaces[directName]) {
						delete config.toolSurfaces[directName];
					}
					saveConfig(config);
					syncActiveMcpTools(pi, config);
					ctx.ui.notify(`Unloaded ${directName}`, "info");
				}
			},
			() => done(undefined),
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

async function showServerToolSelector(pi: ExtensionAPI, ctx: ExtensionCommandContext, serverName: string) {
	ctx.ui.notify(`Loading MCP tools for ${serverName}...`, "info");
	let config = loadConfig();
	const inventory = await loadServerInventory(serverName, ctx.signal);
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
		.map((tool) => {
			const directName = directMcpToolName(serverName, tool.name);
			return {
				id: surfaceItemId(serverName, tool.name),
				label: directName,
				description: tool.description || `${serverName}.${tool.name}`,
				currentValue: surfaceIsLoaded(config, serverName, tool.name) ? "loaded" : "search-only",
				values: ["search-only", "loaded"],
			};
		});

	await ctx.ui.custom<void>((tui, theme, _keybindings, done) => {
		const container = new Container();
		container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));
		container.addChild(new Text(theme.fg("accent", theme.bold(`MCP Tools: ${serverName}`))));
		container.addChild(new Text(theme.fg("dim", "Enter/Space toggles search-only vs loaded direct tool surface. Esc closes.")));

		const settingsList = new SettingsList(
			items,
			Math.min(Math.max(items.length, 8), 18),
			getSettingsListTheme(),
			(id, newValue) => {
				const parsed = parseSelectorItemId(id);
				if (!parsed || parsed.kind !== "surface") return;

				config = loadConfig();
				if (!config.servers) config.servers = {};
				if (!config.toolSurfaces) config.toolSurfaces = {};
				const tool = inventory.tools.find((candidate) => candidate.server === parsed.server && candidate.name === parsed.tool);
				const server = config.servers[parsed.server];
				if (!server) return;
				if (!tool) return;

				const directName = directMcpToolName(parsed.server, parsed.tool);
				if (newValue === "loaded") {
					const surface = surfaceFromInventoryTool(tool);
					ensureModelTool(server, parsed.tool);
					config.toolSurfaces[directName] = surface;
					registerSurfaceTool(pi, surface);
					saveConfig(config);
					syncActiveMcpTools(pi, config);
					ctx.ui.notify(`Loaded ${directName}`, "info");
				} else {
					removeModelTool(server, parsed.tool);
					delete config.toolSurfaces[directName];
					saveConfig(config);
					syncActiveMcpTools(pi, config);
					ctx.ui.notify(`Unloaded ${directName}`, "info");
				}
			},
			() => done(undefined),
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

function formatConfigServerLine(_config: McpConfig, serverName: string, server: McpServerConfig): string {
	const kind = server.type ?? (server.command ? "stdio" : "remote");
	const target = server.command ? `${server.command} ${(server.args ?? []).join(" ")}`.trim() : (server.url ?? server.baseUrl ?? "(no url)");
	const state = server.enabled === false ? "disabled" : "enabled";
	const selected = selectedModelTools(server).length ? `, selectedTools=${selectedModelTools(server).join(",")}` : "";
	return `- ${serverName}: ${state}, ${kind}${selected}, ${target}`;
}

function formatMcpStatus(config: McpConfig, inventory: Inventory): string {
	const lines: string[] = [];
	lines.push("# MCP Status");
	lines.push("");
	lines.push(`Config: ${CONFIG_PATH}`);
	lines.push(`- model can use mcp_search/mcp_inspect/mcp_call: ${routerToolsExposed(config) ? "yes, across all enabled servers" : "no, no servers enabled"}`);
	lines.push(`- model can use direct MCP tools: ${toolSurfacesExposed(config) ? "selectedTools only" : "no selectedTools configured"}`);
	lines.push(`- manual /mcp search/inspect/call: yes`);
	lines.push(`Loaded: ${inventory.loadedAt}`);
	lines.push(`Searchable tools: ${inventory.tools.length}`);
	lines.push(`Selected direct tools: ${Object.values(config.servers ?? {}).reduce((count, server) => count + selectedModelTools(server).length, 0)}`);
	lines.push(`Configured direct tool surfaces: ${Object.values(config.toolSurfaces ?? {}).filter((surface) => surface.enabled !== false).length}`);
	lines.push(`Exposed direct tool surfaces: ${activeSurfaceToolNames(config).length}`);
	lines.push("");
	lines.push("## Servers");
	for (const [serverName, server] of Object.entries(config.servers ?? {}).sort(([left], [right]) => left.localeCompare(right))) {
		lines.push(formatConfigServerLine(config, serverName, server));
		if (server.description) lines.push(`  ${server.description}`);
	}
	lines.push("");
	lines.push("## Direct Tool Surfaces");
	const surfaces = Object.values(config.toolSurfaces ?? {}).sort((left, right) =>
		`${left.server}.${left.tool}`.localeCompare(`${right.server}.${right.tool}`),
	);
	if (surfaces.length === 0) {
		lines.push("(none)");
	} else {
		for (const surface of surfaces) {
			const state = surface.enabled === false ? "disabled" : "loaded";
			lines.push(`- ${surface.name || directMcpToolName(surface.server, surface.tool)}: ${state} -> ${surface.server}.${surface.tool}`);
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
	for (const [serverName] of Object.entries(config.servers ?? {}).sort(([left], [right]) => left.localeCompare(right))) {
		lines.push(`- ${serverName}: ${counts.get(serverName) ?? 0} tool(s)`);
	}
	return lines.join("\n");
}

async function runManualMcpSearch(ctx: ExtensionCommandContext, query: string) {
	ctx.ui.notify("Searching MCP inventory...", "info");
	const inventory = await loadInventory(ctx.signal, false);
	const title = query ? `MCP search: ${query}` : "MCP search";
	await ctx.ui.editor(title, formatInventory(inventory, query || undefined, 100));
}

async function runManualMcpInspect(ctx: ExtensionCommandContext, serverName: string, toolName: string) {
	ctx.ui.notify(`Inspecting ${serverName}.${toolName}...`, "info");
	const inventory = await loadServerInventory(serverName, ctx.signal);
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
	const result = await callMcpTool(serverName, toolName, args, ctx.signal);
	await ctx.ui.editor(`MCP call: ${serverName}.${toolName}`, extractCallText(result));
}

export default function (pi: ExtensionAPI) {
	registerConfiguredSurfaceTools(pi);
	pi.registerTool(mcpSearchTool);
	pi.registerTool(mcpInspectTool);
	pi.registerTool(mcpCallTool);

	pi.on("session_start", () => {
		const config = loadConfig();
		registerConfiguredSurfaceTools(pi);
		syncActiveMcpTools(pi, config);
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		const config = loadConfig();
		registerConfiguredSurfaceTools(pi);
		if (directToolHydrationNeeded(config)) {
			await hydrateDirectToolSurfaces(pi, ctx.signal, false);
		} else {
			syncActiveMcpTools(pi, config);
		}
	});

	pi.registerCommand("mcp", {
		description: "Open MCP selector or manage inventory: /mcp | /mcp search [query] | /mcp status | /mcp tools <server> | /mcp reload",
		handler: async (args, ctx) => {
			const command = args.trim() || "status";

			if (!args.trim()) {
				await showMcpSelector(pi, ctx);
				return;
			}

			if (command === "reload") {
				inventoryCache = undefined;
				closeClients();
				const config = loadConfig();
				registerConfiguredSurfaceTools(pi);
				syncActiveMcpTools(pi, config);
				if (directToolHydrationNeeded(config)) await hydrateDirectToolSurfaces(pi, ctx.signal, true);
				ctx.ui.notify("MCP config and clients reloaded", "info");
				return;
			}

			if (command === "status") {
				ctx.ui.notify("Loading MCP status...", "info");
				const config = loadConfig();
				const inventory = directToolHydrationNeeded(config)
					? await hydrateDirectToolSurfaces(pi, ctx.signal, true)
					: await loadInventory(ctx.signal, true);
				await ctx.ui.editor("MCP status", formatMcpStatus(loadConfig(), inventory));
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
				const inventory = await loadServerInventory(serverName, ctx.signal);
				const tool = inventory.tools.find((candidate) => candidate.name === toolName);
				if (!tool) {
					await ctx.ui.editor(`MCP ${serverName} load failed`, inventory.errors.length ? inventory.errors.join("\n") : `Tool not found: ${serverName}.${toolName}`);
					return;
				}
				const config = loadConfig();
				const server = config.servers?.[serverName];
				if (!server) {
					ctx.ui.notify(`MCP server not found: ${serverName}`, "warning");
					return;
				}
				if (!config.toolSurfaces) config.toolSurfaces = {};
				const surface = surfaceFromInventoryTool(tool);
				ensureModelTool(server, toolName);
				config.toolSurfaces[surface.name!] = surface;
				registerSurfaceTool(pi, surface);
				saveConfig(config);
				syncActiveMcpTools(pi, config);
				ctx.ui.notify(`Loaded ${surface.name}`, "info");
				return;
			}

			if (command.startsWith("unload ")) {
				const directName = command.slice("unload ".length).trim();
				if (!directName) {
					ctx.ui.notify("Usage: /mcp unload <mcp__server__tool>", "warning");
					return;
				}
				const config = loadConfig();
				if (config.toolSurfaces?.[directName]) {
					const surface = config.toolSurfaces[directName];
					const server = config.servers?.[surface.server];
					if (server) removeModelTool(server, surface.tool);
					delete config.toolSurfaces[directName];
					saveConfig(config);
					syncActiveMcpTools(pi, config);
					ctx.ui.notify(`Unloaded ${directName}`, "info");
				} else {
					ctx.ui.notify(`Direct MCP surface not found: ${directName}`, "warning");
				}
				return;
			}

			ctx.ui.notify("Usage: /mcp | /mcp status | /mcp search [query] | /mcp inspect <server> <tool> | /mcp call <server> <tool> [json] | /mcp tools <server> | /mcp load <server> <tool> | /mcp unload <mcp__server__tool> | /mcp reload", "warning");
		},
	});

	pi.on("session_shutdown", async () => {
		closeClients();
	});
}
