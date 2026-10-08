# Herdr-Native Coordination & Seat Utilization

Chartered: 2026-10-07, human driver direct-to-`arch-1` brainstorm charter
("Direction → Design → PRD → Tickets"), from the session retrospective at
`~/Fun/Agathokakological/stampede-notes-10072026.md`.

---

## Direction

Two pillars, one theme: **stop paying coordination taxes Herdr already abolished, and
make every seat pull its hitch.**

1. **Ride Herdr native.** The swarm polls where Herdr can block (`pane wait-output`),
   guesses where Herdr can explain (`agent explain`), and whispers where Herdr can
   notify (`notification show`). Adopt the primitives at the seams that hurt — the
   retrospective shows the cost in polling loops, misread panes, and a ~90-minute
   incident-to-human delay. Decided in [ADR 0017](../docs/adr/0017-herdr-native-coordination-primitives.md).
2. **Right-seat routing.** `agy-gh` is the session's most underused seat — its brief
   covers issue bookkeeping but not the GitHub/git *research* looper keeps doing
   itself; and `looper` (agy/gemini-pro) does heavy diagnosis and archaeology that the
   opencode GLM arch seats exist to carry. Rebalance: GitHub research + gh/git
   read-only archaeology → `agy-gh`; heavy analysis, diagnosis, spikes, and all
   implementation → arch seats; `looper` thins to orchestration-only. Routing policy
   lives in standing briefs; utilization becomes measurable so the rebalance is
   falsifiable.

**Stated interpretation (driver may veto):** "work with github/git → agy-gh" is scoped
as *research and operations* (issue/CI lifecycle, `gh api` exploration, read-only git
archaeology, release mechanics). Write-path git (worker commits, arbiter merges,
promotion) stays with arch seats and the arbiter — moving implementation commits to
`agy-gh` would invert the review/gate topology this repo is built around.

---

## Design

### Pillar 1 — herdr-native primitives (ADR 0017)

| Friction (evidence) | Primitive | Seam |
|---|---|---|
| Timeout-and-recheck loops waiting for worker anchors | `pane wait-output --regex` | launcher seat-verify wait; `lib/quota.sh` probe block; looper/arch standing-brief wait instructions |
| Pane-state confusion diagnosed by re-reads (`focused:true`, stale scrollback) | `agent explain --verbose` | `stampede doctor`; seat-verify failure path; brief hygiene rule ("explain before the third re-read") |
| Human-visible incidents seen only in Ops pane | `notification show` | supervisor alert seam (quota defer, dead letters, `ALERT_BLOCKED`, RED) |
| `agent prompt` + `sleep 1 && send-keys enter` double-submission | prompt-native encoded Enter | `lib/briefs.sh` deliver_brief_nonce (after live per-kind probe) |

Guardrails baked into every adoption: capability probe first, fail-soft fallback to
current behavior, one-time degradation log. The supervisor's multi-anchor harvest scan
stays `agent read` + anchored grep (one read serves `ARCH DONE` and `REVIEW VERDICT`
grammars; wait-output would serialize it) — a documented keep, not an oversight.

### Pillar 2 — right-seat routing

- **`agy-gh` research mandate** (ROUTE-1): brief gains a research/intake duty — GitHub
  issue & CI-log research, `gh api` exploration, read-only git archaeology on request —
  with a findings-file protocol (`.herdr-swarm/research/<topic>.md`) and a
  `RESEARCH DONE <path>` anchor so dispatches have a harvestable completion line
  without fabricating a test-gated verdict.
- **`looper` thin orchestration** (ROUTE-2): no self-serve git/gh research or defect
  diagnosis; a dispatch-budget heuristic (more than one round of git/gh archaeology or
  a non-trivial diagnosis → it is a dispatch, not a side quest); herdr hygiene rules
  (wait-output for anchor waits, explain before third re-read).
- **arch seats heavier lifting** (ROUTE-3): arch brief gains a research/diagnosis
  dispatch mode — read-only investigation tickets that deliver a findings file and
  `ARCH DONE` normally; docs/findings-only outputs ride the REV-06 fast path.
- **Measure it or it didn't happen** (ROUTE-4): `stampede status --rich` gains a
  per-seat activity panel (dispatch counts from traces, commit share from
  `git shortlog` over a window) so under-utilization is a number, not a retrospective
  surprise.

---

## PRD

### User stories

- As the **human driver**, I see quota stalls and blocked-review escalations as native
  notifications within minutes, not when I next read the Ops pane.
- As the **human driver**, I never see `agy-gh` idle for a week while `looper` runs gh
  research itself; GitHub facts arrive as cited findings files from `agy-gh`.
- As **`looper`**, I wait on worker anchors with one blocking call instead of polling
  loops, and my transcript spends its tokens on orchestration decisions.
- As **`arch-1/2`**, I receive diagnosis and research dispatches (not only
  implementation), keeping the opencode GLM seats the herd's heavy-lifting engines.
- As **any seat operator**, `stampede doctor` tells me *why* Herdr classifies a seat
  `unknown`/misfocused, with the detection rule that fired.

### Functional requirements

| Req | Statement | Ticket |
|---|---|---|
| FR-1 | Every standing `herdr` invocation in the repo is audited against the installed CLI + 0.9.3 reference, each with a keep/adopt/drop verdict and receipt | HERDR-1 |
| FR-2 | Single-target output waits (seat-verify, quota probe) block on `pane wait-output` with probe-gated fallback; briefs instruct agents to prefer it for anchor waits | HERDR-2 |
| FR-3 | `stampede doctor` surfaces `agent explain --verbose` output for ambiguous seats | HERDR-3 |
| FR-4 | Brief delivery submits exactly once (native prompt Enter), probe-receipt-gated, failures logged not swallowed | HERDR-4 |
| FR-5 | Supervisor human-visible alerts additionally emit `herdr notification show` (probe-gated) | HERDR-5 |
| FR-6 | `agy-gh` brief mandates GitHub/git research with findings-file protocol + `RESEARCH DONE` anchor | ROUTE-1 |
| FR-7 | `looper` brief forbids self-serve gh/git research & diagnosis past a dispatch budget; adds herdr hygiene rules | ROUTE-2 |
| FR-8 | `arch` brief defines research/diagnosis dispatch mode (findings file, normal verdict, REV-06 fast path for docs-only) | ROUTE-3 |
| FR-9 | `stampede status --rich` shows per-seat dispatch and commit-share activity | ROUTE-4 |

### Non-goals

- No socket-API event-subscription rewrite of the supervisor daemon (deferred; ADR 0017 alternatives).
- No change to verdict/gate/arbiter topology — routing rebalances *who researches and
  implements*, not how changes integrate.
- No new seats, no provider/quota changes.

### Success metrics

1. Looper transcripts: anchor-wait polling loops replaced by single `wait-output`
   calls (qualitative transcript check; traces keep `dispatch` events countable).
2. `agy-gh` ≥ 1 dispatched research/ops task per active day (ROUTE-4 panel).
3. Arch seats carry the majority of non-bookkeeping commits per week (ROUTE-4 panel).
4. Quota-stall-class incidents reach the driver via native notification in < 5 min
   (retrospective baseline: ~90 min).

---

## Tickets

| Ticket | Seat | Status | Blocked by | Synopsis |
|---|---|---|---|---|
| **HERDR-1** | arch-1-hinchk-stampede | **resolved** (e8cb014) | — | Herdr surface audit: every call site vs installed CLI, keep/adopt/drop receipts (`docs/findings/herdr-surface-audit.md`) |
| **HERDR-2** | arch-2-hinchk-stampede | **resolved** (ad42801) | HERDR-1 | `pane wait-output` adoption: seat-verify wait + quota probe block, probe-gated fallbacks (integrated at `b150257`) |
| **HERDR-3** | arch-1-hinchk-stampede | **resolved** (0773203) | HERDR-1 | `agent explain` diagnostics in `stampede doctor` (integrated at `c3dd3f7`) |
| **HERDR-4** | arch-2-hinchk-stampede | **resolved** (2225e2c) | HERDR-1 | Brief delivery single-submission (drop double-enter after live per-kind probe; integrated at `8eae776`) |
| **HERDR-5** | arch-1-hinchk-stampede | **resolved** (cb26aaf) | HERDR-1 | Supervisor alerts via `herdr notification show` (integrated at `cb26aaf`) |
| **ROUTE-1** | arch-2-hinchk-stampede | **resolved** (6d13160) | — | `agy-gh` research mandate + findings-file protocol (`RESEARCH DONE` anchor; integrated at `b1a6f1a`) |
| **ROUTE-2** | arch-2-hinchk-stampede | **resolved** (6b2b697) | — | `looper` thin-orchestration brief: dispatch budget, no self-serve research, herdr hygiene (integrated at `6b2b697`) |
| **ROUTE-3** | arch-1-hinchk-stampede | **resolved** (efb08ea) | — | `arch` brief research/diagnosis dispatch mode (integrated at `b7411e4`) |
| **ROUTE-4** | arch-1-hinchk-stampede | **resolved** (6a19bd1) | — | Seat-utilization activity panel in `stampede status --rich` (integrated at `c2752ec`) |
| **ROUTE-5** | arch-2-hinchk-stampede | **resolved** (5330cae) | — | `agy-docs` post-integration docs sweep mandate; owns `briefs/worker-docs.in.md` (`DOCS DONE` anchor; integrated at `ceaaecf`) |

All tickets in the epic are resolved and integrated on `swarm/stampede/integration` (promoted to `main` at `8eae776`).

## Decisions so far

- 2026-10-07 (charter): ADR 0017 accepted — block/explain/notify adoption is
  probe-gated and fail-soft; supervisor multi-anchor harvest scan explicitly kept as
  `agent read` + grep.
- 2026-10-07 (charter): "git work → agy-gh" scoped to research/operations; write-path
  git stays with arch + arbiter (stated interpretation, driver may veto).
- 2026-10-07 (charter): double-enter removal is receipt-gated on a live per-kind probe
  (HERDR-4) — docs and operational folklore disagree; a probe settles it.
- 2026-10-07 (charter): routing policy is brief-level (accepted best-effort limit,
  same class as QUOTA-4) plus a measurable dashboard (ROUTE-4) so drift is visible.
- 2026-10-07 (execution): HERDR-1 resolved (e8cb014) — 39 call sites audited, receipts in `docs/findings/herdr-surface-audit.md`.
- 2026-10-07 (execution): ROUTE-1 resolved (6d13160) — `agy-gh` research mandate with `RESEARCH DONE` anchor.
- 2026-10-07 (execution): ROUTE-3 resolved (efb08ea) — arch brief research/diagnosis mode established.
- 2026-10-07 (execution): ROUTE-5 resolved (5330cae) — `agy-docs` post-integration sweep mandate with `DOCS DONE` anchor.
- 2026-10-07 (execution): ROUTE-2 resolved (6b2b697) — looper thin orchestration and wait hygiene integrated.
- 2026-10-07 (execution): ROUTE-4 resolved (6a19bd1) — seat-activity panel in `stampede status --rich` integrated.
- 2026-10-07 (execution): HERDR-2 resolved (ad42801) — `pane wait-output` single-target wait integration.
- 2026-10-07 (execution): HERDR-3 resolved (0773203) — `stampede doctor` ambiguous seat explanation via `agent explain`.
- 2026-10-07 (execution): HERDR-5 resolved (cb26aaf) — supervisor human-visible alerts emit `herdr notification show`.
- 2026-10-07 (execution): HERDR-4 resolved (2225e2c) — brief delivery single submission via `agent prompt --wait`. Epic fully integrated and promoted to `main` at `8eae776`.
