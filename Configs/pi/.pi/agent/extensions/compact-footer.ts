import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const PAD = 1;

function fmtTokens(n: number): string {
	return n < 1000 ? `${n}` : n < 1_000_000 ? `${(n / 1000).toFixed(1)}k` : `${(n / 1_000_000).toFixed(1)}M`;
}

function computeUsageTotals(ctx: ExtensionContext) {
	let input = 0, output = 0, cacheRead = 0;
	for (const e of ctx.sessionManager.getBranch()) {
		if (e.type === "message" && e.message.role === "assistant") {
			const m = e.message as any;
			input += m.usage?.input ?? 0;
			output += m.usage?.output ?? 0;
			cacheRead += m.usage?.cacheRead ?? 0;
		}
	}
	return { input, output, cacheRead };
}

export default function compactFooter(pi: ExtensionAPI) {
	let requestRender: (() => void) | undefined;

	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;

		ctx.ui.setFooter((tui, theme, footerData) => {
			requestRender = () => tui.requestRender();
			const unsubBranch = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose() {
					unsubBranch();
					requestRender = undefined;
				},
				invalidate() {},
				render(width: number): string[] {
					const innerWidth = Math.max(1, width - PAD * 2);
					const statuses = footerData.getExtensionStatuses();

					// --- Row 1: cwd (muted left) | git + speed (colored right) ---
					const cwdStr = ctx.sessionManager.getCwd() || ctx.cwd;
					const cwdColored = theme.fg("muted", cwdStr);
					const gitRaw = statuses.get("git-status") || "";
					const speedRaw = statuses.get("speed") || "";
					const right1Colored = [gitRaw, speedRaw].filter(Boolean).join("  ");
					const row1 =
						" ".repeat(PAD) +
						truncateToWidth(
							cwdColored +
								" ".repeat(
									Math.max(1, innerWidth - visibleWidth(cwdColored) - visibleWidth(right1Colored))
								) +
								right1Colored,
							innerWidth
						);

					// --- Row 2: usage (muted with accent percent/dim total) | model (muted with accent thinking) ---
					const { input, output, cacheRead } = computeUsageTotals(ctx);
					const usageCtx = ctx.getContextUsage();

					let usageColored = "";
					if (usageCtx && usageCtx.tokens != null) {
						const inputStr = fmtTokens(input);
						const outputStr = fmtTokens(output);
						const cacheReadStr = fmtTokens(cacheRead);
						const percentStr = `${usageCtx.percent?.toFixed(1)}%`;
						const totalStr = fmtTokens(usageCtx.contextWindow);

						usageColored =
							theme.fg("muted", `↑${inputStr} ↓${outputStr} R${cacheReadStr} `) +
							theme.fg("accent", percentStr) +
							theme.fg("muted", "/") +
							theme.fg("dim", totalStr) +
							theme.fg("muted", " (auto)");
					}

					const model = ctx.model;
					const thinking = pi.getThinkingLevel();
					const modelPrefix = model
						? theme.fg("muted", `(${model.provider}) ${model.id}`)
						: theme.fg("muted", "no-model");
					const thinkingColored =
						thinking && thinking !== "off"
							? theme.fg("muted", " • ") + theme.fg("accent", thinking)
							: "";
					const modelColored = modelPrefix + thinkingColored;

					const row2 =
						" ".repeat(PAD) +
						truncateToWidth(
							usageColored +
								" ".repeat(
									Math.max(1, innerWidth - visibleWidth(usageColored) - visibleWidth(modelColored))
								) +
								modelColored,
							innerWidth
						);

					return [row1, row2];
				},
			};
		});
	});

	// Re-render triggers
	pi.on("message_update", async () => requestRender?.());
	pi.on("message_end", async () => requestRender?.());
	pi.on("turn_end", async () => requestRender?.());
	pi.on("agent_end", async () => requestRender?.());
	pi.on("model_select", async () => requestRender?.());
	pi.on("thinking_level_select", async () => requestRender?.());
	pi.on("input", async () => requestRender?.());
	pi.on("tool_execution_end", async () => requestRender?.());

	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setFooter(undefined);
		requestRender = undefined;
	});
}
