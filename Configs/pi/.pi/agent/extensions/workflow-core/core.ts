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
			createdAt: event.timestamp,
			updatedAt: event.timestamp,
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

export function renderWorkflowSummary(workflow: WorkflowRecord): string {
	const lines = [
		`- Controller: ${workflow.controller}`,
		`- Status: ${workflow.status}`,
		`- Objective: ${workflow.objective}`,
		`- Started: ${workflow.createdAt}`,
		`- Updated: ${workflow.updatedAt}`,
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
