---
id: EHS-13
title: "Establish enforceable isolation for subscription-backed routes"
type: wayfinder:research
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: []
---

# Establish enforceable isolation for subscription-backed routes

## Question

Which concrete trust boundary can preserve subscription login while preventing model-directed tools from reading unapproved secrets, issuing/widening grants, bypassing protected Git/production actions, or evading cancellation through descendants?

Examine current primary documentation for candidate subscription CLI routes and supported host/tool isolation. Distinguish the authenticated harness process from every model-directed tool path (shell, built-in read/write, network, plugins, subagents). Identify who owns the grant store, how human issuance differs from worker requests, where side effects are authorized, and what the pilot must verify. Do not assume one sandbox flag or a container containing a plaintext login protects credentials from its own agent. APIs and local models are deferred; retain Herdr session operation.

**Intended Outcome:** A concrete recommended enforcement architecture with documented candidate routes, explicit unknowns, compatibility limitations, and a disposable acceptance-probe checklist.

**Done-Criteria:** Report uses current primary sources, distinguishes security properties from claims requiring experiments, and does not certify an untested route.

**Verification Step:** Check source claims, include spoofed human permission, secret reads through multiple tools, direct push/deploy bypass, revoked grants, and descendant/remote continuation scenarios. No credentials, live provider calls, isolation changes, or paid usage.

## Comments

### Research claim — 2026-11-06

Claimed for HinchK to resolve the factual prerequisite of [Set replication, routing, resource, and authority limits](07-replication-and-routing.md). Research artifact will be linked with its throwaway branch and commit. User accepted staged eligibility: only verified routes enter the unattended pilot.

### Encryption consideration from HinchK — 2026-11-06

HinchK suggested encrypting secrets. Evaluate encrypted storage, preferably a platform credential store where compatible, alongside protection of decrypted material during legitimate subscription authentication. This is a design suggestion to investigate, not permission to read, copy, encrypt, migrate, rotate, or handle live credentials.

Explicitly distinguish encryption at rest from isolation of model-directed tools: storing encrypted bytes next to an agent-accessible decryption key or exposing a credential-store retrieval tool does not meet the secret boundary. Identify where authentication material is held, which trusted process can use it, what tools cannot access it, and how logs/checkpoints/handoffs exclude secret values. Retain the human outside-session handoff for adding/changing/recovering/revealing credentials. Existing CLI compatibility may constrain what can be guaranteed.

### Secret-file scope corrected by HinchK — 2026-11-06

HinchK explicitly deferred encrypted-storage work: focus on not reading secrets and leaving them in secure files maintained by the user. This supersedes the preceding encryption investigation as a pilot requirement. Do not design or require a new encrypted store, keyring migration, rotation system, or secret-management service for this pilot.

Research the narrower boundary: user-maintained secret files remain outside model-directed read/write access, prompts, logs, checkpoints, and handoffs. Stampede may use non-secret file references and required variable names; readiness checks must not return values. Existing authenticated provider clients may use their stored credentials internally under the previously agreed exception. Neither file ownership nor a worktree boundary alone proves that the model's tools cannot read files. Identify the minimum supported access controls and eligibility probes needed, without handling real secret material.

### Scoped exposure exception accepted — 2026-11-06

The user subsequently approved an optional per-run mode allowing named credentials to selected agents/providers, with no values in Git/public output/routine logs and a required Stampede-managed cycling pass. The report must distinguish the default no-access boundary from this explicit exception. No encryption project is requested. Research here establishes default isolation and grant enforcement; it must not certify service-specific rotation integrations, which need their own capability checks. The full accepted policy is in [Set replication, routing, resource, and authority limits](07-replication-and-routing.md).

### Research resolution — 2026-11-06

Completed [Subscription-route isolation and user-maintained secret files](../../../docs/findings/2026-11-06-subscription-route-enforcement.md), captured on `research/subscription-route-enforcement` at `947d16717d8e8f07f010ec3641755dfff0e59d2a`. An identical copy is preserved in the canonical checkout. The final report reflects both latest user decisions: no encryption project, and optional scoped agent/provider exposure coupled to verified cycling.

The report recommends a protected controller/administrative entrypoint, an authenticated pinned vendor harness, and restricted model-directed tools. It identifies a Codex subscription route as a candidate based on documented controls, not a certified integration. It details why shell-only isolation, a readable login mounted into a worker, and same-user grant files are insufficient on their own, and provides disposable eligibility probes. Primary-source review confirmed the distinction between shell sandboxing and other tool paths. User-owned secret files stay protected by default; the explicit exposure exception does not relax unrelated secret or grant controls.

No route has passed live eligibility probes, and no service-specific cycling integration is established by this research. No credentials, live provider accounts, rotation APIs, cancellation, or isolation changes were exercised. The grant/controller architecture remains a recommendation for the resource/authority decision; resolving this research does not adopt it on HinchK's behalf or resolve that human decision.

### Architecture recommendation not adopted — 2026-11-06

HinchK subsequently chose the existing Herdr/provider-harness controls and rejected the report's separate protected-controller/isolation recommendation. The source findings and verification limitations remain useful; the research artifact is historical evidence, not the chosen architecture. [Set replication, routing, resource, and authority limits](07-replication-and-routing.md) is authoritative for this decision. No route has been certified by this research.
