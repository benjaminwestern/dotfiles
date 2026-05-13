import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

export type ModalCloseResult = "close";
export type HudResult = "close" | "markdown";

export type HudOverlayOptions = {
	width: string;
	maxHeight: string;
	anchor: string;
	offsetY?: number;
	margin?: number;
};

export type ThemeLike = {
	fg?: (color: string, text: string) => string;
	bg?: (color: string, text: string) => string;
	bold?: (text: string) => string;
	italic?: (text: string) => string;
	underline?: (text: string) => string;
};

type TuiLike = { requestRender?: () => void };

type HudControls = {
	done: (result: HudResult) => void;
	requestRender: () => void;
};

export type HudOptions = {
	render: (width: number, theme: ThemeLike, tui: TuiLike) => string[];
	handleInput?: (data: string, controls: HudControls) => boolean | void;
	overlayOptions?: HudOverlayOptions;
};

export const defaultHudOverlayOptions: HudOverlayOptions = {
	width: "94%",
	maxHeight: "92%",
	anchor: "top-center",
	offsetY: 2,
	margin: 2,
};

export function isCloseKey(data: string) {
	return data === "q" || data === "Q" || data === "\u0003" || matchesKey(data, "escape") || matchesKey(data, "ctrl+c");
}

export function isMarkdownKey(data: string) {
	return data === "m" || data === "M" || data === "e" || data === "E";
}

export function keyMatches(data: string, keyName: string, aliases: string[] = []) {
	return matchesKey(data, keyName) || aliases.includes(data);
}

export async function showHud(ctx: ExtensionCommandContext, options: HudOptions) {
	if (!ctx.hasUI) return "close" as HudResult;
	const custom = (ctx.ui as unknown as {
		custom: (
			factory: (tui: TuiLike, theme: ThemeLike, keybindings: unknown, done: (value: HudResult) => void) => unknown,
			options?: unknown,
		) => Promise<HudResult>;
	}).custom;

	return custom(
		(tui, theme, _keybindings, done) => ({
			render: (width: number) => options.render(width, theme, tui),
			handleInput: (data: string) => {
				const requestRender = () => tui.requestRender?.();
				const consumed = options.handleInput?.(data, { done, requestRender });
				if (consumed) return;
				if (isMarkdownKey(data)) done("markdown");
				if (isCloseKey(data)) done("close");
				requestRender();
			},
			invalidate: () => {},
		}),
		{
			overlay: true,
			overlayOptions: options.overlayOptions ?? defaultHudOverlayOptions,
		},
	);
}

export function color(theme: ThemeLike | undefined, name: string, text: string) {
	return theme?.fg ? theme.fg(name, text) : text;
}

export function strong(theme: ThemeLike | undefined, text: string) {
	return theme?.bold ? theme.bold(text) : text;
}

export function italic(theme: ThemeLike | undefined, text: string) {
	return theme?.italic ? theme.italic(text) : text;
}

export function underline(theme: ThemeLike | undefined, text: string) {
	return theme?.underline ? theme.underline(text) : text;
}

export function fitText(text: string | undefined, width: number) {
	const value = text && text.trim() ? text : "none";
	if (width <= 0) return "";
	if (visibleWidth(value) <= width) return value;
	return truncateToWidth(value, width);
}

export function padRight(text: string, width: number) {
	const visible = visibleWidth(text);
	return visible >= width ? fitText(text, width) : text + " ".repeat(width - visible);
}

export function fill(width: number, char = " ") {
	return width > 0 ? char.repeat(width) : "";
}

export function panelStyled(theme: ThemeLike | undefined, text: string, tone: "normal" | "accent" | "muted" | "warning" | "error" = "normal") {
	const fg = tone === "normal" ? text : color(theme, tone === "accent" ? "accent" : tone, text);
	return theme?.bg ? theme.bg("selectedBg", fg) : fg;
}

export function panelLine(theme: ThemeLike | undefined, raw: string, width: number, tone: "normal" | "accent" | "muted" | "warning" | "error" = "normal") {
	const inner = Math.max(1, width - 4);
	const text = raw.trim() ? fitText(raw, inner) : "";
	return panelStyled(theme, `│ ${padRight(text, inner)} │`, tone);
}

export const panelContentLine = panelLine;

export function panelBlank(theme: ThemeLike | undefined, width: number) {
	return panelLine(theme, "", width);
}

export function panelRule(theme: ThemeLike | undefined, width: number, title?: string, top = false, bottom = false) {
	const left = top ? "╭" : bottom ? "╰" : "├";
	const right = top ? "╮" : bottom ? "╯" : "┤";
	const label = title ? ` ${color(theme, "accent", strong(theme, title))} ` : "";
	const middleWidth = Math.max(1, width - 2);
	const rule = label ? `${label}${fill(Math.max(0, middleWidth - visibleWidth(label)), "─")}` : fill(middleWidth, "─");
	return panelStyled(theme, `${left}${fitText(rule, middleWidth)}${right}`, "accent");
}

export function panelTopRule(theme: ThemeLike | undefined, width: number, title: string, help: string) {
	const middleWidth = Math.max(1, width - 2);
	const leftLabel = ` ${color(theme, "accent", strong(theme, title))} `;
	const rightLabel = ` ${color(theme, "muted", help)} `;
	const rule = `${leftLabel}${fill(Math.max(1, middleWidth - visibleWidth(leftLabel) - visibleWidth(rightLabel)), "─")}${rightLabel}`;
	return panelStyled(theme, `╭${fitText(rule, middleWidth)}╮`, "accent");
}

export function withPanelShadow(lines: string[], width: number, theme?: ThemeLike) {
	const sideShadow = color(theme, "dim", " ░");
	const bottomShadow = color(theme, "dim", `${fill(2)}${"░".repeat(width)}`);
	return [...lines.map((line) => `${line}${sideShadow}`), bottomShadow];
}

export function gridColumnCount(width: number, maxColumns = 4) {
	if (width >= 104) return maxColumns;
	if (width >= 76) return Math.min(3, maxColumns);
	if (width >= 46) return Math.min(2, maxColumns);
	return 1;
}

export function gridLine(parts: string[], width: number, columns = gridColumnCount(width), gap = 5) {
	const colWidth = Math.max(1, Math.floor((width - gap * (columns - 1)) / columns));
	return parts.map((part) => padRight(fitText(part, colWidth), colWidth)).join(fill(gap)).trimEnd();
}

export function wrapItems(items: string[], width: number, gap = "     ") {
	const lines: string[] = [];
	let current = "";
	for (const item of items.filter(Boolean)) {
		const next = current ? `${current}${gap}${item}` : item;
		if (visibleWidth(next) <= width) {
			current = next;
			continue;
		}
		if (current) lines.push(current);
		current = fitText(item, width);
	}
	if (current) lines.push(current);
	return lines.length ? lines : ["none"];
}

export function columnize(items: string[], width: number) {
	if (items.length === 0) return ["none"];
	const columns = gridColumnCount(width, 4);
	const lines: string[] = [];
	for (let index = 0; index < items.length; index += columns) {
		lines.push(gridLine(items.slice(index, index + columns), width, columns));
	}
	return lines;
}
