import { readFileSync } from "node:fs";
import {
	CustomEditor,
	type ExtensionAPI,
	type KeybindingsManager,
} from "@earendil-works/pi-coding-agent";
import type {
	AutocompleteItem,
	AutocompleteProvider,
	EditorTheme,
	TUI,
} from "@earendil-works/pi-tui";

const TOKEN_MARKER = /(^|[\s([{])\$:([A-Za-z0-9_.:/-]+)/g;
const BRACED_MARKER = /\$\{:\s*([^}\s]+)(?:\s+([^}]*))?\}/g;
const DOLLAR_PREFIX = /(?:^|[\s([{])(\$(?::[A-Za-z0-9_.:/-]*)?)$/;
const MAX_SUGGESTIONS = 80;

type CommandSource = "extension" | "prompt" | "skill";

interface CommandInfo {
	name: string;
	description?: string;
	source: CommandSource;
	sourceInfo: {
		path: string;
		baseDir?: string;
	};
}

interface ToolInfo {
	name: string;
	description?: string;
}

interface MarkerResult {
	replacement: string;
	message?: string;
	type: "skill" | "prompt" | "tool" | "slash" | "unknown";
}

function stripFrontmatter(content: string): string {
	if (!content.startsWith("---")) return content.trim();

	const end = content.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/);
	if (!end) return content.trim();
	return content.slice(end[0].length).trim();
}

function splitArgs(input: string): string[] {
	const args: string[] = [];
	const pattern = /"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|(\S+)/g;
	let match = pattern.exec(input);
	while (match) {
		const raw = match[1] ?? match[2] ?? match[3] ?? "";
		args.push(raw.replace(/\\(["'\\])/g, "$1"));
		match = pattern.exec(input);
	}
	return args;
}

function expandTemplate(body: string, argsText: string): string {
	const args = splitArgs(argsText);
	const allArgs = args.join(" ");

	return body
		.replace(/\$\{@:(\d+)(?::(\d+))?\}/g, (_match, startText: string, lengthText: string | undefined) => {
			const start = Math.max(1, Number(startText)) - 1;
			const length = lengthText === undefined ? undefined : Math.max(0, Number(lengthText));
			return (length === undefined ? args.slice(start) : args.slice(start, start + length)).join(" ");
		})
		.replace(/\$ARGUMENTS|\$@/g, allArgs)
		.replace(/\$(\d+)/g, (_match, indexText: string) => args[Number(indexText) - 1] ?? "");
}

function escapeXml(value: string): string {
	return value
		.replaceAll("&", "&amp;")
		.replaceAll("<", "&lt;")
		.replaceAll(">", "&gt;")
		.replaceAll('"', "&quot;");
}

function commandList(pi: ExtensionAPI): CommandInfo[] {
	return pi.getCommands() as CommandInfo[];
}

function toolList(pi: ExtensionAPI): ToolInfo[] {
	return pi.getAllTools() as ToolInfo[];
}

function findCommand(pi: ExtensionAPI, rawName: string): CommandInfo | undefined {
	const name = rawName.startsWith("/") ? rawName.slice(1) : rawName;
	const commands = commandList(pi);
	return (
		commands.find((command) => command.name === name) ??
		commands.find((command) => command.source === "skill" && command.name === `skill:${name}`)
	);
}

function activateTools(pi: ExtensionAPI, names: string[]): string[] {
	const allTools = new Set(toolList(pi).map((tool) => tool.name));
	const requested = names.map((name) => name.trim()).filter(Boolean);
	const found = requested.filter((name) => allTools.has(name));
	if (found.length === 0) return [];

	const active = pi.getActiveTools();
	const next = [...active];
	for (const name of found) {
		if (!next.includes(name)) next.push(name);
	}
	pi.setActiveTools(next);
	return found;
}

function formatInlineSlashCommand(name: string, argsText: string): string {
	const command = `/${name.startsWith("/") ? name.slice(1) : name}${argsText ? ` ${argsText}` : ""}`;
	return `<inline_slash_command command="${escapeXml(command)}">Requested inline. If this command changes Pi UI/runtime state, tell the user to run it as a normal slash command; otherwise follow its intent.</inline_slash_command>`;
}

function resolveMarker(pi: ExtensionAPI, rawName: string, argsText = ""): MarkerResult {
	const normalizedName = rawName.startsWith("/") ? rawName.slice(1) : rawName;

	if (normalizedName === "tool" || normalizedName === "tools") {
		const activated = activateTools(pi, argsText.split(/[\s,]+/));
		return {
			replacement: "",
			type: "tool",
			message: activated.length ? `Activated tool(s): ${activated.join(", ")}` : `No matching tool(s): ${argsText}`,
		};
	}

	if (normalizedName.startsWith("tool:")) {
		const activated = activateTools(pi, [normalizedName.slice("tool:".length)]);
		return {
			replacement: "",
			type: "tool",
			message: activated.length
				? `Activated tool: ${activated[0]}`
				: `No matching tool: ${normalizedName.slice("tool:".length)}`,
		};
	}

	if (normalizedName.startsWith("tools:")) {
		const activated = activateTools(pi, normalizedName.slice("tools:".length).split(/[\s,]+/));
		return {
			replacement: "",
			type: "tool",
			message: activated.length ? `Activated tool(s): ${activated.join(", ")}` : `No matching tool(s): ${normalizedName}`,
		};
	}

	const command = findCommand(pi, normalizedName);
	if (!command) {
		return { replacement: `$:${rawName}`, type: "unknown", message: `Unknown $: marker: ${rawName}` };
	}

	if (command.source === "skill") {
		const content = readFileSync(command.sourceInfo.path, "utf-8");
		const body = stripFrontmatter(content);
		const block = `<skill name="${escapeXml(command.name.replace(/^skill:/, ""))}" location="${escapeXml(command.sourceInfo.path)}">\nReferences are relative to ${command.sourceInfo.baseDir ?? command.sourceInfo.path}.\n\n${body}\n</skill>`;
		return {
			replacement: argsText.trim() ? `${block}\n\n${argsText.trim()}` : block,
			type: "skill",
			message: `Loaded skill: ${command.name.replace(/^skill:/, "")}`,
		};
	}

	if (command.source === "prompt") {
		const content = readFileSync(command.sourceInfo.path, "utf-8");
		return {
			replacement: expandTemplate(stripFrontmatter(content), argsText),
			type: "prompt",
			message: `Expanded prompt: /${command.name}`,
		};
	}

	return {
		replacement: formatInlineSlashCommand(command.name, argsText),
		type: "slash",
		message: `Inserted inline slash-command request: /${command.name}`,
	};
}

async function replaceBracedMarkers(pi: ExtensionAPI, text: string, results: MarkerResult[]): Promise<string> {
	let output = "";
	let lastIndex = 0;
	let match = BRACED_MARKER.exec(text);
	while (match) {
		output += text.slice(lastIndex, match.index);
		const result = resolveMarker(pi, match[1] ?? "", match[2] ?? "");
		results.push(result);
		output += result.replacement;
		lastIndex = BRACED_MARKER.lastIndex;
		match = BRACED_MARKER.exec(text);
	}
	output += text.slice(lastIndex);
	BRACED_MARKER.lastIndex = 0;
	return output;
}

async function replaceTokenMarkers(pi: ExtensionAPI, text: string, results: MarkerResult[]): Promise<string> {
	let output = "";
	let lastIndex = 0;
	let match = TOKEN_MARKER.exec(text);
	while (match) {
		const leading = match[1] ?? "";
		const rawName = match[2] ?? "";
		const markerStart = match.index + leading.length;
		output += text.slice(lastIndex, markerStart);
		const result = resolveMarker(pi, rawName);
		results.push(result);
		output += result.replacement;
		lastIndex = TOKEN_MARKER.lastIndex;
		match = TOKEN_MARKER.exec(text);
	}
	output += text.slice(lastIndex);
	TOKEN_MARKER.lastIndex = 0;
	return output;
}

function dollarPrefix(textBeforeCursor: string): string | null {
	return textBeforeCursor.match(DOLLAR_PREFIX)?.[1] ?? null;
}

function compactDescription(value: string | undefined, fallback: string): string {
	const text = (value ?? fallback).replace(/\s+/g, " ").trim();
	return text.length > 120 ? `${text.slice(0, 117)}…` : text;
}

function buildSuggestions(pi: ExtensionAPI, prefix: string): AutocompleteItem[] {
	const query = (prefix.startsWith("$:") ? prefix.slice(2) : prefix.slice(1)).replace(/^\//, "").toLowerCase();
	const items: AutocompleteItem[] = [];

	for (const command of commandList(pi)) {
		if (command.source === "extension") continue;
		items.push({
			value: `$:${command.name}`,
			label: command.source === "skill" ? command.name : `/${command.name}`,
			description: `${command.source} — ${compactDescription(command.description, command.sourceInfo.path)}`,
		});
	}

	for (const tool of toolList(pi)) {
		items.push({
			value: `$:tool:${tool.name}`,
			label: `tool:${tool.name}`,
			description: `activate tool — ${compactDescription(tool.description, tool.name)}`,
		});
	}

	return items
		.filter((item) => {
			const haystack = `${item.value} ${item.label} ${item.description ?? ""}`.toLowerCase();
			return query.length === 0 || haystack.includes(query);
		})
		.slice(0, MAX_SUGGESTIONS);
}

function applyDollarCompletion(
	lines: string[],
	cursorLine: number,
	cursorCol: number,
	item: AutocompleteItem,
	prefix: string,
): { lines: string[]; cursorLine: number; cursorCol: number } {
	const currentLine = lines[cursorLine] ?? "";
	const beforePrefix = currentLine.slice(0, cursorCol - prefix.length);
	const afterCursor = currentLine.slice(cursorCol);
	const suffix = afterCursor.startsWith(" ") || afterCursor.length === 0 ? "" : " ";
	const newLine = `${beforePrefix}${item.value}${suffix}${afterCursor}`;
	const newLines = [...lines];
	newLines[cursorLine] = newLine;
	return { lines: newLines, cursorLine, cursorCol: beforePrefix.length + item.value.length + suffix.length };
}

function shouldWakeDollarAutocomplete(text: string, cursorCol: number): boolean {
	return dollarPrefix(text.slice(0, cursorCol)) !== null;
}

class DollarCommandEditor extends CustomEditor {
	constructor(tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager) {
		super(tui, theme, keybindings);
	}

	override handleInput(data: string): void {
		super.handleInput(data);

		if (data.length !== 1) return;
		if (!/[A-Za-z0-9_.:/\-$]/.test(data)) return;
		if (this.isShowingAutocomplete()) return;

		const cursor = this.getCursor();
		const line = this.getLines()[cursor.line] ?? "";
		if (!shouldWakeDollarAutocomplete(line, cursor.col)) return;

		// Tab asks the editor's autocomplete provider for forced suggestions. Our
		// provider claims $ / $: contexts before path completion sees the request.
		super.handleInput("\t");
	}
}

export default function inlineDollar(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.addAutocompleteProvider((current: AutocompleteProvider): AutocompleteProvider => ({
			async getSuggestions(lines, cursorLine, cursorCol, options) {
				const line = lines[cursorLine] ?? "";
				const prefix = dollarPrefix(line.slice(0, cursorCol));
				if (!prefix) return current.getSuggestions(lines, cursorLine, cursorCol, options);

				const items = buildSuggestions(pi, prefix);
				if (items.length === 0) return null;
				return { prefix, items };
			},
			applyCompletion(lines, cursorLine, cursorCol, item, prefix) {
				if (prefix.startsWith("$:")) return applyDollarCompletion(lines, cursorLine, cursorCol, item, prefix);
				return current.applyCompletion(lines, cursorLine, cursorCol, item, prefix);
			},
			shouldTriggerFileCompletion(lines, cursorLine, cursorCol) {
				const line = lines[cursorLine] ?? "";
				if (dollarPrefix(line.slice(0, cursorCol))) return true;
				return current.shouldTriggerFileCompletion?.(lines, cursorLine, cursorCol) ?? true;
			},
		}));

		ctx.ui.setEditorComponent((tui, theme, keybindings) => new DollarCommandEditor(tui, theme, keybindings));
	});

	pi.on("input", async (event, ctx) => {
		if (!event.text.includes("$:")) return { action: "continue" };

		const results: MarkerResult[] = [];
		let text = await replaceBracedMarkers(pi, event.text, results);
		text = await replaceTokenMarkers(pi, text, results);

		if (results.length === 0) return { action: "continue" };

		const messages = results
			.map((result) => result.message)
			.filter((message): message is string => Boolean(message));
		if (ctx.hasUI && messages.length > 0) {
			ctx.ui.notify(`$: ${messages.join("; ")}`, "info");
		}

		return { action: "transform", text, images: event.images };
	});
}
