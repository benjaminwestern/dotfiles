import type { WorkflowController, WorkflowRecord } from "../core.js";

const BENCHMARK_GUARDRAIL = "Be careful not to overfit to the benchmarks and do not cheat on the benchmarks.";

function header(workflow: WorkflowRecord): string {
	return `<workflow>\ncontroller: autoresearch\nid: ${workflow.id}\nstatus: ${workflow.status}\nobjective: ${workflow.objective}\n</workflow>`;
}

function stateLine(workflow: WorkflowRecord): string {
	const metric = typeof workflow.data.metricName === "string" ? workflow.data.metricName : undefined;
	const direction = typeof workflow.data.direction === "string" ? workflow.data.direction : undefined;
	const runs = typeof workflow.data.runCount === "number" ? workflow.data.runCount : 0;
	const best = typeof workflow.data.bestMetric === "number" ? workflow.data.bestMetric : undefined;
	return [
		metric ? `metric=${metric}` : undefined,
		direction ? `direction=${direction}` : undefined,
		`runs=${runs}`,
		best !== undefined ? `best=${best}` : undefined,
	]
		.filter(Boolean)
		.join(", ");
}

const SETUP_DOCTRINE = `Setup doctrine:
1. Ask or infer: Goal, Command, Metric + direction, Files in scope, Constraints.
2. Prefer creating/switching to a branch named autoresearch/<goal>-<date> before noisy experimentation when safe.
3. Read the source files. Understand the workload deeply before writing anything.
4. For fast-moving or domain-heavy work (ML/HF, framework APIs, infra, browsers, papers), do source-grounded reconnaissance before implementing: current docs, examples, issues, papers, datasets, and prior art. Use research_probe for noisy evidence gathering so throwaway pi --no-session scouts keep the main loop compact.
5. Write autoresearch.md and autoresearch.sh if they do not exist. Add autoresearch.preflight.sh when a cheap smoke test is useful. Commit them when working in a git repository.
6. Call init_experiment, run the baseline with run_experiment, log the baseline, then start looping immediately.

autoresearch.md contract:
A fresh agent with no context should be able to read this file and run the loop effectively. Include:
- Objective: specific workload and optimization target.
- Metrics: primary metric with unit/direction, plus secondary tradeoff monitors.
- How to Run: ./autoresearch.sh, which outputs METRIC name=number lines.
- Preflight / Smoke: optional autoresearch.preflight.sh contract and when run_preflight should be used.
- Files in Scope: every file the agent may modify, with a brief note.
- Off Limits: what must not be touched.
- Evidence / Recipes: current docs, examples, papers, issue links, benchmark sources, and any result-backed recipes worth trying.
- Benchmark / Data Audit: what the metric really measures, input data shape, seeds/warmups/sample counts, noise risks, and known ways it could be gamed.
- Resource Budget: max iterations/time/cost/hardware/network limits and any required approval gates. If needed, encode generic limits in autoresearch.config.json: maxIterations, maxWallClockSeconds, maxExperimentSeconds, maxConsecutiveFailures, maxConsecutiveDiscards, maxConsecutiveCrashes, maxCommandRepeats, requirePreflight.
- Constraints: hard rules such as tests, types, no new deps, API compatibility.
- What's Been Tried: key wins, dead ends, architectural insights, and repeated failures to avoid.
Update autoresearch.md periodically, especially What's Been Tried, so resuming agents do not repeat failed paths.

autoresearch.sh contract:
- Bash script with set -euo pipefail.
- Do fast pre-checks first when possible.
- Run the benchmark and print structured METRIC name=value lines.
- For fast noisy benchmarks, run multiple samples and report the median.
- Output phase timings, error categories, memory/cache data, or other diagnostics that will help choose the next experiment.
- You may improve the script during the loop if better signal is needed.`;

const LOOP_RULES = `Loop rules:
- LOOP FOREVER. Never ask "should I continue?"; the user expects autonomous work until interrupted, paused, budget-limited, failed, or explicitly complete.
- Primary metric is king. Improved -> keep. Worse/equal -> discard. Secondary metrics are tradeoff monitors unless they violate constraints.
- Use run_experiment instead of bash for experiment commands. After every run_experiment, always call log_experiment exactly once.
- Annotate every run with useful structured side information in log_experiment.asi when available. Prefer keys: hypothesis, evidence, changed, learned, next_focus, risk. Record what you learned, not just what you did.
- Watch confidence/noise. After several runs, re-run marginal improvements if the signal may be within noise.
- Simpler is better. Removing code for equal performance can be a keep. Ugly complexity for tiny gain is probably discard.
- Do not thrash. The extension detects repeated non-keeps/descriptions/hypotheses and will steer you away from loops; when that happens, use research_probe or deeper inspection and try a fundamentally different strategy.
- For expensive jobs or batch sweeps, call run_preflight for one small smoke experiment first, verify it starts and records the metric, then fan out.
- Crashes: fix if trivial; otherwise log as crash and move on.
- Think longer when stuck. Re-read source, study profiling/diagnostic data, reason about what the CPU/runtime/workload is doing, and return to external evidence when internal knowledge may be stale.
- If autoresearch.md exists, read it plus recent autoresearch.jsonl and git log, then continue looping.
- If autoresearch.ideas.md exists, check it for promising paths, prune stale/tried ideas, and experiment with the rest.
- When you discover complex but promising optimizations you will not pursue immediately, append them as bullets to autoresearch.ideas.md.
- If the user sends a follow-on message while an experiment is running, finish the current run_experiment + log_experiment cycle first, then incorporate their feedback in the next iteration.
- ${BENCHMARK_GUARDRAIL}`;

const CHECKS_RULES = `Backpressure checks:
- Create autoresearch.checks.sh only when the user's constraints require correctness validation.
- When autoresearch.checks.sh exists, it should run tests/types/lint or other correctness checks after passing benchmarks.
- If checks fail, log status checks_failed. Do not keep the result.
- Checks execution time does not affect the primary metric.
- Keep checks output minimal and focused on errors.`;

const BENCHMARK_HYGIENE_RULES = `Benchmark and evidence hygiene:
- Audit the benchmark before optimizing it: what input data it uses, whether it is representative, how noisy it is, and what changes would be cheating.
- Prefer scripts that emit primary and secondary METRIC lines plus phase timings or diagnostics that explain why a change moved the metric.
- Use medians/warmups/seeds for noisy fast benchmarks; preserve comparability between baseline and variants.
- Do not silently substitute datasets, models, workloads, dependencies, or task definitions. If the requested resource is unavailable, record the blocker and ask before changing scope.
- When external APIs/libraries matter, verify current docs/examples before writing code; internal model memory is not authoritative. Use research_probe for broad or noisy lookup tasks.
- For ML-style work, tie recipes to evidence: dataset + method + hyperparameters -> reported result, then validate data format before training.`;

export const autoresearchController: WorkflowController = {
	name: "autoresearch",
	label: "Autoresearch",
	statusLine: { symbol: "◆", label: "auto", color: "#00d5ff" },
	renderStartPrompt(workflow) {
		return `${header(workflow)}

You are now in the main Pi autoresearch workflow.

Objective: ${workflow.objective}

${SETUP_DOCTRINE}

${LOOP_RULES}

${CHECKS_RULES}

${BENCHMARK_HYGIENE_RULES}

Start now. If the session files exist, resume from them. Otherwise set up autoresearch.md and autoresearch.sh, initialize the experiment, run the baseline, log it, then immediately continue to the first real experiment.`;
	},
	renderContinuePrompt(workflow) {
		const note = workflow.lastNote ? `\nLast note: ${workflow.lastNote}` : "";
		return `${header(workflow)}${note}

Continue the Pi autoresearch workflow.

Current state: ${stateLine(workflow)}

${LOOP_RULES}

${CHECKS_RULES}

${BENCHMARK_HYGIENE_RULES}

Use persisted autoresearch state as source of truth: autoresearch.md, autoresearch.jsonl, autoresearch.sh, autoresearch.checks.sh, autoresearch.ideas.md, and git log. Pick the most promising next hypothesis from the evidence or ideas backlog, call run_experiment, then call log_experiment. Do not stop after a successful run; continue until paused, budget-limited, failed, or explicitly complete.`;
	},
	renderStatus(workflow) {
		const lines = [
			"# Autoresearch",
			"",
			`- Status: ${workflow.status}`,
			`- Objective: ${workflow.objective}`,
			`- State: ${stateLine(workflow)}`,
			`- Started: ${workflow.createdAt}`,
			`- Updated: ${workflow.updatedAt}`,
			`- Events: ${workflow.events.length}`,
		];
		if (workflow.lastNote) lines.push(`- Last note: ${workflow.lastNote}`);
		if (workflow.nextAction) lines.push(`- Next action: ${workflow.nextAction}`);
		return lines.join("\n");
	},
};
