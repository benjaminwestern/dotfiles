import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const STATUS_ID = "speed";
const CHARS_PER_TOKEN_ESTIMATE = 4;

type DeltaEvent = {
	type?: string;
	delta?: unknown;
};

function outputTokens(message: { usage?: { output?: number } }) {
	const value = message.usage?.output;
	return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function streamDelta(event: unknown) {
	if (!event || typeof event !== "object") return "";
	const candidate = event as DeltaEvent;
	if (
		candidate.type !== "text_delta" &&
		candidate.type !== "thinking_delta" &&
		candidate.type !== "toolcall_delta"
	) {
		return "";
	}
	return typeof candidate.delta === "string" ? candidate.delta : "";
}

function formatSpeed(tokens: number, startedAt: number | undefined) {
	if (!startedAt || tokens <= 0) return undefined;
	const seconds = Math.max((Date.now() - startedAt) / 1000, 0.001);
	return {
		tps: Math.round(tokens / seconds),
		seconds,
	};
}

export default function tokenSpeedStatus(pi: ExtensionAPI) {
	let messageStartedAt: number | undefined;
	let streamStartedAt: number | undefined;
	let estimatedTokens = 0;
	let runOutputTokens = 0;
	let runStreamMs = 0;

	pi.on("session_start", async (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_ID, ctx.ui.theme.fg("dim", "speed idle"));
	});

	pi.on("agent_start", async (_event, ctx) => {
		runOutputTokens = 0;
		runStreamMs = 0;
		messageStartedAt = undefined;
		streamStartedAt = undefined;
		estimatedTokens = 0;
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_ID, ctx.ui.theme.fg("dim", "speed starting"));
	});

	pi.on("message_start", async (event) => {
		if (event.message.role !== "assistant") return;
		messageStartedAt = Date.now();
		streamStartedAt = undefined;
		estimatedTokens = 0;
	});

	pi.on("message_update", async (event, ctx) => {
		if (event.message.role !== "assistant" || !ctx.hasUI) return;

		const delta = streamDelta(event.assistantMessageEvent);
		if (!delta) return;

		streamStartedAt ??= Date.now();
		estimatedTokens += delta.length / CHARS_PER_TOKEN_ESTIMATE;

		const officialTokens = outputTokens(event.message);
		const tokens = officialTokens > 0 ? officialTokens : Math.round(estimatedTokens);
		const speed = formatSpeed(tokens, streamStartedAt);
		if (!speed) return;

		const tokenLabel = officialTokens > 0 ? `${officialTokens} tok` : `~${tokens} tok`;
		ctx.ui.setStatus(
			STATUS_ID,
			`${ctx.ui.theme.fg("accent", `${speed.tps} tok/s`)} ${ctx.ui.theme.fg("dim", tokenLabel)}`,
		);
	});

	pi.on("message_end", async (event) => {
		if (event.message.role !== "assistant") return;

		const officialTokens = outputTokens(event.message);
		const tokens = officialTokens > 0 ? officialTokens : Math.round(estimatedTokens);
		const startedAt = streamStartedAt ?? messageStartedAt;
		if (tokens > 0 && startedAt) {
			runOutputTokens += tokens;
			runStreamMs += Math.max(0, Date.now() - startedAt);
		}

		messageStartedAt = undefined;
		streamStartedAt = undefined;
		estimatedTokens = 0;
	});

	pi.on("agent_end", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		const seconds = runStreamMs / 1000;
		const tps = runOutputTokens > 0 && seconds > 0 ? Math.round(runOutputTokens / seconds) : 0;
		const status = tps > 0
			? `${ctx.ui.theme.fg("accent", `${tps} tok/s`)} ${ctx.ui.theme.fg("dim", `${runOutputTokens} tok`)}`
			: ctx.ui.theme.fg("dim", "speed idle");
		ctx.ui.setStatus(STATUS_ID, status);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_ID, undefined);
	});
}
