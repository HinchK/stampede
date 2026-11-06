---
id: EHS-03
title: "Establish credible methods for evaluating an evolving swarm"
type: wayfinder:research
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: []
---

# Establish credible methods for evaluating an evolving swarm

## Question

Which evaluation methods can distinguish benefits from orchestration, model choice, and harness adaptation in long-horizon software work?

Use primary sources to examine strong single-agent baselines, fixed versus evolving harnesses, comparable budgets, repeated trials, held-out tasks, independent acceptance evidence, delayed defects, and contamination or evaluator-gaming risks. Separate research findings from vendor anecdotes and estimated gains. Identify what current evidence does and does not show about smaller models with specialized harnesses.

Return candidate methods and limitations; do not choose the user's success thresholds, workloads, sample sizes, or spending limits.

**Intended Outcome:** A sourced methodological baseline for a falsifiable experiment protocol.

**Done-Criteria:** Findings identify practical comparisons, confounders, measurement gaps, and evidence limits, with a research branch/commit pointer.

**Verification Step:** Check primary citations and ensure no performance claim is generalized beyond the study or case that supports it.

## Comments

### Research claim — 2026-11-06

Claimed for HinchK by the delegated research agent. Findings will be captured on `research/swarm-evaluation-methods` and linked here with their commit before resolution.

### Resolution — 2026-11-06

The research establishes a usable comparison method and its limits. Published evidence supports task-specific prompt adaptation and durable harness practices; it does not establish that an evolving swarm universally improves software delivery. Control model choice separately from orchestration where attribution is required, compare fixed and evolving configurations from equivalent starting points, protect held-out evaluations, and count human effort and all adaptation/evaluation overhead. Include restart, integration, failure, and later-defect outcomes.

Detailed evidence: [Evaluation methods](../../../docs/findings/2026-11-06-swarm-evaluation-methods.md). Research context: branch `research/swarm-evaluation-methods`, commit `b5f4439ddc488580d9bc86a6b8a59da468fe1699`. The report was reviewed against the question and its central GEPA and infrastructure-noise sources. No experiments were run.

This resolves the methodological investigation. Workloads, sample sizes, resource limits, success thresholds, and the final comparison design remain human decisions in [Choose the pilot configurations and freeze the experiment protocol](09-experiment-protocol.md).
