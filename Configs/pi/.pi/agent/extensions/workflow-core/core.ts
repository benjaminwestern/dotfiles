import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { randomUUID } from "node:crypto";

export const WORKFLOW_EVENT_TYPE = "pi.workflow.event";

export type WorkflowStatus = "active" | "paused" | "waiting_for_user" | "budget_limited" | "complete" | "failed" | "cleared";

export type WorkflowEventKind =
	| "workflow_started"
	| "workflow_updated"
	| "workflow_status_changed"
	| "workflow_note"
	| "workflow_cleared";

export type WorkflowEvent = {
	version: 1;
	eventId: string;
	workflowId: string;
	controller: string;
	kind: WorkflowEventKind;
	timestamp: string;
	payload: Record<string, unknown>;
};

export type WorkflowRecord = {
	id: string;
	controller: string;
	title: string;
	objective: string;
	status: WorkflowStatus;
	createdAt: string;
	updatedAt: string;
	lastNote?: string;
	nextAction?: string;
	data: Record<string, unknown>;
	events: WorkflowEvent[];
};

export type WorkflowTimingData = {
	originalCreatedAt: string;
	originalUpdatedAt: string;
	capturedAt: string;
	activeElapsedMs: number;
	status: WorkflowStatus;
};

export type StartWorkflowInput = {
	controller: string;
	title: string;
	objective: string;
	status?: WorkflowStatus;
	data?: Record<string, unknown>;
};

export type WorkflowStatusLineSpec = {
	symbol: string;
	label: string;
	color: string;
};

export type WorkflowController = {
	name: string;
	label: string;
	statusLine?: WorkflowStatusLineSpec;
	renderStartPrompt(workflow: WorkflowRecord): string;
	renderContinuePrompt(workflow: WorkflowRecord): string;
	renderStatus?(workflow: WorkflowRecord): string;
};

export const workflowStatusLineSpecs: Record<string, WorkflowStatusLineSpec> = {
	goal: { symbol: "◆", label: "goal", color: "#d4af37" },
	review: { symbol: "◆", label: "review", color: "#7a1f68" },
	autoresearch: { symbol: "◆", label: "auto", color: "#00d5ff" },
};

export function workflowStatusLineSpec(workflow: WorkflowRecord): WorkflowStatusLineSpec | undefined {
	return workflowStatusLineSpecs[workflow.controller];
}

export function currentWorkflowForStatusLine(ctx: ExtensionContext | ExtensionCommandContext): WorkflowRecord | undefined {
	const latest = workflows(ctx)
		.filter((workflow) => workflowStatusLineSpec(workflow) !== undefined)
		.sort((a, b) => a.updatedAt.localeCompare(b.updatedAt))
		.at(-1);
	return latest?.status === "cleared" ? undefined : latest;
}

function nowIso(): string {
	return new Date().toISOString();
}

function asObject(value: unknown): Record<string, unknown> | undefined {
	return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
}

function parseMs(value: string | undefined): number | undefined {
	if (!value) return undefined;
	const ms = Date.parse(value);
	return Number.isFinite(ms) ? ms : undefined;
}

function asWorkflowTimingData(value: unknown): WorkflowTimingData | undefined {
	const object = asObject(value);
	if (!object) return undefined;
	return typeof object.originalCreatedAt === "string" &&
		typeof object.originalUpdatedAt === "string" &&
		typeof object.capturedAt === "string" &&
		typeof object.activeElapsedMs === "number" &&
		isWorkflowStatus(object.status)
		? object as WorkflowTimingData
		: undefined;
}

function nonNegativeInteger(value: unknown): number | undefined {
	const number = Number(value);
	return Number.isFinite(number) && number >= 0 ? Math.trunc(number) : undefined;
}

export function workflowDisplayTurns(workflow: WorkflowRecord): number {
	return nonNegativeInteger(workflow.data.displayTurns) ?? nonNegativeInteger(workflow.data.autoTurns) ?? 0;
}

export function workflowTriggers(workflow: WorkflowRecord): number {
	return nonNegativeInteger(workflow.data.triggers) ?? 0;
}

function isWorkflowEvent(value: unknown): value is WorkflowEvent {
	const object = asObject(value);
	return (
		object?.version === 1 &&
		typeof object.eventId === "string" &&
		typeof object.workflowId === "string" &&
		typeof object.controller === "string" &&
		typeof object.kind === "string" &&
		typeof object.timestamp === "string" &&
		asObject(object.payload) !== undefined
	);
}

export function workflowEvents(ctx: ExtensionContext | ExtensionCommandContext): WorkflowEvent[] {
	return ctx.sessionManager
		.getBranch()
		.filter((entry) => entry.type === "custom" && entry.customType === WORKFLOW_EVENT_TYPE)
		.map((entry) => entry.data)
		.filter(isWorkflowEvent);
}

function applyEvent(record: WorkflowRecord | undefined, event: WorkflowEvent): WorkflowRecord | undefined {
	const payload = event.payload;

	if (event.kind === "workflow_started") {
		const title = typeof payload.title === "string" ? payload.title : event.controller;
		const objective = typeof payload.objective === "string" ? payload.objective : title;
		const status = isWorkflowStatus(payload.status) ? payload.status : "active";
		return {
			id: event.workflowId,
			controller: event.controller,
			title,
			objective,
			status,
			createdAt: typeof payload.createdAt === "string" ? payload.createdAt : event.timestamp,
			updatedAt: typeof payload.updatedAt === "string" ? payload.updatedAt : event.timestamp,
			lastNote: typeof payload.note === "string" ? payload.note : undefined,
			nextAction: typeof payload.nextAction === "string" ? payload.nextAction : undefined,
			data: asObject(payload.data) ?? {},
			events: [event],
		};
	}

	if (!record) return undefined;

	const next: WorkflowRecord = {
		...record,
		updatedAt: event.timestamp,
		data: { ...record.data },
		events: [...record.events, event],
	};

	if (event.kind === "workflow_updated") {
		if (typeof payload.title === "string") next.title = payload.title;
		if (typeof payload.objective === "string") next.objective = payload.objective;
		if (typeof payload.note === "string") next.lastNote = payload.note;
		if (typeof payload.nextAction === "string") next.nextAction = payload.nextAction;
		if (isWorkflowStatus(payload.status)) next.status = payload.status;
		const data = asObject(payload.data);
		if (data) next.data = { ...next.data, ...data };
	}

	if (event.kind === "workflow_status_changed") {
		if (isWorkflowStatus(payload.status)) next.status = payload.status;
		if (typeof payload.note === "string") next.lastNote = payload.note;
		if (typeof payload.nextAction === "string") next.nextAction = payload.nextAction;
	}

	if (event.kind === "workflow_note") {
		if (typeof payload.note === "string") next.lastNote = payload.note;
		if (typeof payload.nextAction === "string") next.nextAction = payload.nextAction;
	}

	if (event.kind === "workflow_cleared") {
		next.status = "cleared";
		if (typeof payload.note === "string") next.lastNote = payload.note;
	}

	return next;
}

export function workflows(ctx: ExtensionContext | ExtensionCommandContext): WorkflowRecord[] {
	const byId = new Map<string, WorkflowRecord>();
	for (const event of workflowEvents(ctx)) {
		const current = byId.get(event.workflowId);
		const next = applyEvent(current, event);
		if (next) byId.set(event.workflowId, next);
	}
	return [...byId.values()].sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

export function activeWorkflow(ctx: ExtensionContext | ExtensionCommandContext, controller?: string): WorkflowRecord | undefined {
	return workflows(ctx)
		.filter((workflow) => !["complete", "failed", "cleared"].includes(workflow.status))
		.filter((workflow) => !controller || workflow.controller === controller)
		.at(-1);
}

export function latestWorkflow(ctx: ExtensionContext | ExtensionCommandContext, controller?: string): WorkflowRecord | undefined {
	return workflows(ctx)
		.filter((workflow) => !controller || workflow.controller === controller)
		.at(-1);
}

export function appendWorkflowEvent(
	pi: ExtensionAPI,
	kind: WorkflowEventKind,
	workflowId: string,
	controller: string,
	payload: Record<string, unknown> = {},
): WorkflowEvent {
	const event: WorkflowEvent = {
		version: 1,
		eventId: randomUUID(),
		workflowId,
		controller,
		kind,
		timestamp: nowIso(),
		payload,
	};
	pi.appendEntry(WORKFLOW_EVENT_TYPE, event);
	return event;
}

export function startWorkflow(pi: ExtensionAPI, input: StartWorkflowInput): WorkflowEvent {
	return appendWorkflowEvent(pi, "workflow_started", randomUUID(), input.controller, {
		title: input.title,
		objective: input.objective,
		status: input.status ?? "active",
		data: input.data ?? {},
	});
}

export function updateWorkflow(
	pi: ExtensionAPI,
	workflow: WorkflowRecord,
	payload: Record<string, unknown>,
): WorkflowEvent {
	return appendWorkflowEvent(pi, "workflow_updated", workflow.id, workflow.controller, payload);
}

export function changeWorkflowStatus(
	pi: ExtensionAPI,
	workflow: WorkflowRecord,
	status: WorkflowStatus,
	note?: string,
	nextAction?: string,
): WorkflowEvent {
	return appendWorkflowEvent(pi, "workflow_status_changed", workflow.id, workflow.controller, { status, note, nextAction });
}

export function clearWorkflow(pi: ExtensionAPI, workflow: WorkflowRecord, note?: string): WorkflowEvent {
	return appendWorkflowEvent(pi, "workflow_cleared", workflow.id, workflow.controller, { note });
}

export function isWorkflowStatus(value: unknown): value is WorkflowStatus {
	return (
		value === "active" ||
		value === "paused" ||
		value === "waiting_for_user" ||
		value === "budget_limited" ||
		value === "complete" ||
		value === "failed" ||
		value === "cleared"
	);
}

function statusAfterEvent(current: WorkflowStatus | undefined, event: WorkflowEvent): WorkflowStatus | undefined {
	if (event.kind === "workflow_started") return isWorkflowStatus(event.payload.status) ? event.payload.status : "active";
	if (event.kind === "workflow_cleared") return "cleared";
	if ((event.kind === "workflow_updated" || event.kind === "workflow_status_changed") && isWorkflowStatus(event.payload.status)) return event.payload.status;
	return current;
}

function activeElapsedFromEvents(events: WorkflowEvent[], nowMs: number, startStatus?: WorkflowStatus, startAtMs?: number): number {
	let status = startStatus;
	let activeSince = status === "active" ? startAtMs : undefined;
	let elapsed = 0;
	for (const event of [...events].sort((a, b) => a.timestamp.localeCompare(b.timestamp))) {
		const at = parseMs(event.timestamp);
		if (at === undefined) continue;
		if (startAtMs !== undefined && at < startAtMs) continue;
		const nextStatus = statusAfterEvent(status, event);
		if (nextStatus === status) continue;
		if (status === "active" && activeSince !== undefined) elapsed += Math.max(0, at - activeSince);
		if (nextStatus === "active") activeSince = at;
		else activeSince = undefined;
		status = nextStatus;
	}
	if (status === "active" && activeSince !== undefined) elapsed += Math.max(0, nowMs - activeSince);
	return elapsed;
}

function isWorkflowTimingRestoreEvent(event: WorkflowEvent, timing: WorkflowTimingData): boolean {
	const data = asObject(event.payload.data);
	const eventTiming = asWorkflowTimingData(data?.workflowTiming);
	return eventTiming?.capturedAt === timing.capturedAt;
}

export function workflowStartedAt(workflow: WorkflowRecord): string {
	return asWorkflowTimingData(workflow.data.workflowTiming)?.originalCreatedAt ?? workflow.createdAt;
}

export function workflowUpdatedAt(workflow: WorkflowRecord): string {
	const timing = asWorkflowTimingData(workflow.data.workflowTiming);
	if (!timing) return workflow.updatedAt;
	const hasPostSnapshotUpdate = workflow.events.some((event) => event.timestamp >= timing.capturedAt && !isWorkflowTimingRestoreEvent(event, timing));
	return hasPostSnapshotUpdate ? workflow.updatedAt : timing.originalUpdatedAt;
}

function workflowWallClockEndMs(workflow: WorkflowRecord, nowMs: number): number {
	if (workflow.status === "complete" || workflow.status === "failed" || workflow.status === "cleared") {
		return parseMs(workflowUpdatedAt(workflow)) ?? parseMs(workflow.updatedAt) ?? nowMs;
	}
	return nowMs;
}

export function workflowWallClockMs(workflow: WorkflowRecord, now = new Date()): number {
	const nowMs = now.getTime();
	const startedAt = parseMs(workflowStartedAt(workflow)) ?? parseMs(workflow.createdAt) ?? nowMs;
	return Math.max(0, workflowWallClockEndMs(workflow, nowMs) - startedAt);
}

export function workflowActiveElapsedMs(workflow: WorkflowRecord, now = new Date()): number {
	const nowMs = now.getTime();
	const timing = asWorkflowTimingData(workflow.data.workflowTiming);
	if (timing) {
		const capturedAt = parseMs(timing.capturedAt) ?? nowMs;
		return Math.max(0, timing.activeElapsedMs) + activeElapsedFromEvents(workflow.events, nowMs, timing.status, capturedAt);
	}
	return activeElapsedFromEvents(workflow.events, nowMs);
}

export function workflowTimingData(workflow: WorkflowRecord, capturedAt = nowIso()): WorkflowTimingData {
	const captured = new Date(capturedAt);
	return {
		originalCreatedAt: workflowStartedAt(workflow),
		originalUpdatedAt: workflowUpdatedAt(workflow),
		capturedAt,
		activeElapsedMs: workflowActiveElapsedMs(workflow, captured),
		status: workflow.status,
	};
}

export function formatWorkflowDuration(ms: number): string {
	const totalSeconds = Math.max(0, Math.floor(ms / 1000));
	const seconds = totalSeconds % 60;
	const totalMinutes = Math.floor(totalSeconds / 60);
	const minutes = totalMinutes % 60;
	const totalHours = Math.floor(totalMinutes / 60);
	const hours = totalHours % 24;
	const days = Math.floor(totalHours / 24);
	const parts: string[] = [];
	if (days) parts.push(`${days}d`);
	if (hours || parts.length) parts.push(`${hours}h`);
	if (minutes || parts.length) parts.push(`${minutes}m`);
	parts.push(`${seconds}s`);
	return parts.join(" ");
}

export function renderWorkflowSummary(workflow: WorkflowRecord): string {
	const lines = [
		`- Controller: ${workflow.controller}`,
		`- Status: ${workflow.status}`,
		`- Objective: ${workflow.objective}`,
		`- Started: ${workflowStartedAt(workflow)}`,
		`- Updated: ${workflowUpdatedAt(workflow)}`,
		`- Wall clock: ${formatWorkflowDuration(workflowWallClockMs(workflow))}`,
		`- Active runtime: ${formatWorkflowDuration(workflowActiveElapsedMs(workflow))}`,
		`- Chat turns: ${workflowDisplayTurns(workflow)}`,
		`- Triggers: ${workflowTriggers(workflow)}`,
		`- Events: ${workflow.events.length}`,
	];
	if (workflow.lastNote) lines.push(`- Last note: ${workflow.lastNote}`);
	if (workflow.nextAction) lines.push(`- Next action: ${workflow.nextAction}`);
	return lines.join("\n");
}

export function renderWorkflowList(ctx: ExtensionContext | ExtensionCommandContext): string {
	const records = workflows(ctx);
	if (records.length === 0) return "No workflows recorded on this session branch.";
	return records
		.map((workflow) => `## ${workflow.title}\n${renderWorkflowSummary(workflow)}`)
		.join("\n\n");
}

export function sendWorkflowPrompt(pi: ExtensionAPI, controller: WorkflowController, workflow: WorkflowRecord, mode: "start" | "continue") {
	const content = mode === "start" ? controller.renderStartPrompt(workflow) : controller.renderContinuePrompt(workflow);
	pi.sendMessage(
		{
			customType: "pi.workflow.prompt",
			content,
			display: true,
			details: { workflowId: workflow.id, controller: workflow.controller, mode },
		},
		{ triggerTurn: true, deliverAs: "followUp" },
	);
}
