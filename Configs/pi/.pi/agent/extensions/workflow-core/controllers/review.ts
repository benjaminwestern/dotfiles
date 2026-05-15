import {
	formatWorkflowDuration,
	workflowActiveElapsedMs,
	workflowDisplayTurns,
	workflowStartedAt,
	workflowTriggers,
	workflowUpdatedAt,
	workflowWallClockMs,
	type WorkflowController,
	type WorkflowRecord,
} from "../core.js";

const REVIEW_RUBRIC = `You are acting as a reviewer for a proposed code change made by another engineer.

General guidelines for deciding whether to flag a bug:
1. It meaningfully impacts accuracy, performance, security, or maintainability.
2. The bug is discrete and actionable, not a broad concern or vague architectural preference.
3. Fixing it does not demand a level of rigor absent from the rest of the codebase.
4. The bug was introduced by the change under review; do not flag pre-existing issues unless the change makes them newly reachable.
5. The author would likely fix it if made aware.
6. The issue does not rely on unstated assumptions about intent.
7. You must identify the other code/inputs/environments that are provably affected; speculation is not enough.
8. The issue is clearly not just an intentional behaviour change.

Comment guidelines:
- Be clear about why this is a bug and communicate severity accurately.
- Keep each comment to one concise paragraph.
- Do not include code blocks longer than 3 lines.
- Explicitly name the scenarios, environments, or inputs required for the bug to arise.
- Use a matter-of-fact, helpful tone. Avoid praise, blame, or filler.
- Avoid unnecessary location details in the body because the finding already has a location.

Finding policy:
- Output all findings that the original author would fix if they knew about them.
- If there are no findings the author would definitely fix, prefer no findings.
- Ignore trivial style unless it obscures meaning or violates documented standards.
- Use one comment per distinct issue.
- Choose the smallest line range that pinpoints the problem, usually no more than 5-10 lines.
- The code_location must overlap changed lines when a diff is available.
- Do not generate a PR fix unless the user explicitly asks you to fix findings.

Priority tags:
- [P0] Blocking release/major usage; universal, not assumption-dependent.
- [P1] Urgent; should be addressed in the next cycle.
- [P2] Normal; should be fixed eventually.
- [P3] Low; nice to have.`;

const JSON_SCHEMA = `Preferred structured output shape:
{
  "findings": [
    {
      "title": "<≤ 80 chars, starts with [P0]/[P1]/[P2]/[P3]>",
      "body": "<valid Markdown explaining why this is a problem; cite files/lines/functions>",
      "confidence_score": <float 0.0-1.0>,
      "priority": <int 0-3>,
      "code_location": {
        "absolute_file_path": "<file path>",
        "line_range": {"start": <int>, "end": <int>}
      }
    }
  ],
  "overall_correctness": "patch is correct" | "patch is incorrect",
  "overall_explanation": "<1-3 sentence explanation>",
  "overall_confidence_score": <float 0.0-1.0>
}`;

function reviewTarget(workflow: WorkflowRecord): string {
	const target = typeof workflow.data.target === "string" ? workflow.data.target : "current changes";
	const base = typeof workflow.data.base === "string" ? workflow.data.base : undefined;
	const commit = typeof workflow.data.commit === "string" ? workflow.data.commit : undefined;
	const instructions = typeof workflow.data.instructions === "string" ? workflow.data.instructions : undefined;
	if (target === "base" && base) return `changes against base branch ${base}`;
	if (target === "commit" && commit) return `commit ${commit}`;
	if (target === "custom" && instructions) return instructions;
	return "current staged, unstaged, and untracked changes";
}

function inspectInstructions(workflow: WorkflowRecord): string {
	const target = workflow.data.target;
	if (target === "base") {
		const base = typeof workflow.data.base === "string" ? workflow.data.base : "main";
		const mergeBase = typeof workflow.data.mergeBase === "string" ? workflow.data.mergeBase : undefined;
		return mergeBase
			? `The merge base for ${base} is ${mergeBase}. Inspect the review patch with \`git diff ${mergeBase}\`.`
			: `Find the merge base for ${base}, then inspect the patch with git diff against that merge base.`;
	}
	if (target === "commit") {
		const commit = typeof workflow.data.commit === "string" ? workflow.data.commit : "HEAD";
		return `Inspect the patch introduced by \`git show --stat --patch ${commit}\`.`;
	}
	if (target === "custom") {
		return "Use the user's custom review instructions, but still apply the bug-finding rubric, changed-line constraint, and output discipline.";
	}
	return "Inspect current staged, unstaged, and untracked changes. Use git diff, git diff --cached, and git ls-files --others --exclude-standard as needed.";
}

function header(workflow: WorkflowRecord): string {
	return `<workflow>\ncontroller: review\nid: ${workflow.id}\nstatus: ${workflow.status}\ntarget: ${reviewTarget(workflow)}\n</workflow>`;
}

export const reviewController: WorkflowController = {
	name: "review",
	label: "Review",
	statusLine: { symbol: "◆", label: "review", color: "#7a1f68" },
	renderStartPrompt(workflow) {
		return `${header(workflow)}

You are now in the main Pi review workflow. This is not a side task. Review only; do not edit files unless the user explicitly asks you to fix a finding.

${REVIEW_RUBRIC}

Target: ${reviewTarget(workflow)}
${inspectInstructions(workflow)}

${JSON_SCHEMA}

Output for the user may be human-readable, but preserve the same fields and discipline as the schema: prioritized findings, exact absolute file paths, exact line ranges, overall correctness, explanation, and confidence. If no findings qualify, say that no actionable findings were found and mark the patch correct.

This review workflow will be automatically marked as complete after your response. Do not call workflow_update or update_review. If follow-up review is needed, the user will create a new review workflow.`;
	},
	renderContinuePrompt(workflow) {
		return `${header(workflow)}

Continue the Pi review workflow for ${reviewTarget(workflow)}.

${REVIEW_RUBRIC}

Output any additional findings. This workflow will be automatically marked as complete after your response. Do not call workflow_update or update_review.`;
	},
	renderStatus(workflow) {
		const lines = [
			"# Review",
			"",
			`- Status: ${workflow.status}`,
			`- Target: ${reviewTarget(workflow)}`,
			`- Started: ${workflowStartedAt(workflow)}`,
			`- Updated: ${workflowUpdatedAt(workflow)}`,
			`- Wall clock: ${formatWorkflowDuration(workflowWallClockMs(workflow))}`,
			`- Active runtime: ${formatWorkflowDuration(workflowActiveElapsedMs(workflow))}`,
			`- Turns: ${workflowDisplayTurns(workflow)}`,
			`- Triggers: ${workflowTriggers(workflow)}`,
			`- Events: ${workflow.events.length}`,
		];
		if (workflow.lastNote) lines.push(`- Last note: ${workflow.lastNote}`);
		if (workflow.nextAction) lines.push(`- Next action: ${workflow.nextAction}`);
		return lines.join("\n");
	},
};
