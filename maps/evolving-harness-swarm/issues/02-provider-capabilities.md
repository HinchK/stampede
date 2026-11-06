---
id: EHS-02
title: "Establish supported provider and harness capabilities"
type: wayfinder:research
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: []
---

# Establish supported provider and harness capabilities

## Question

What supported interfaces can connect frontier providers to a common bounded loop, and which capabilities can that loop actually rely on?

Research Claude Code, Codex, Gemini CLI, and the existing OpenCode/AGY entry points using primary sources. Distinguish subscription authentication from paid API access, provider from model from harness, structured output, tool/permission controls, session continuation, cancellation, concurrency, and usage/quota observability. Mark undocumented or inaccessible facts unknown; do not inspect credentials, start paid sessions, or infer the user's entitlements. Existing local installs may be inventoried read-only without printing secrets.

Return a dated capability matrix and constraints for adapter/routing design. A documented capability is not a live integration proof.

**Intended Outcome:** A sourced capability baseline for the provider-neutral design.

**Done-Criteria:** Primary sources support the claimed capabilities, access and measurement limits are explicit, and the findings are linked with a research branch/commit pointer.

**Verification Step:** Check citations against the actual claims and distinguish documented support, local observations, and untested behavior.

## Comments

### Research claim — 2026-11-06

Claimed for HinchK by the delegated research agent. Findings will be captured on `research/swarm-provider-capabilities` and linked here with their commit before resolution.

### Resolution — 2026-11-06

The installed harnesses have documented non-interactive structured invocation and continuation paths, but their permission, interruption, authentication, and accounting semantics differ. A provider, model, harness, and account entitlement must be represented separately. Documented consumer Google access has moved from Gemini CLI to AGY; older documentation conflicts with the current announcement and repository README. No account entitlement was inferred from an installed CLI.

Detailed evidence: [Provider and harness capabilities](../../../docs/findings/2026-11-06-swarm-provider-capabilities.md). Research context: branch `research/swarm-provider-capabilities`, commit `e35339b50ba8a1ef49dc131abd6593bf93cde639`. The report was reviewed against the ticket and the transition announcement; primary sources and read-only CLI observations are recorded in the report. No credentials or live workloads were used.

This resolves the documentary capability investigation. The initial provider roster, paid-access policy, routing, and resource limits remain human decisions in [Define the first engineering workload and what better means](01-workload-and-success.md) and [Set replication, routing, resource, and authority limits](07-replication-and-routing.md). Live cancellation, quota, and continuation behavior require explicitly scoped probes before an adapter is declared ready.
