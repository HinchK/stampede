# Marshal & Archon vs Stampede — 2026-11-12

**Date:** 2026-11-12 · **Author:** human-driver research dispatch (ZCode session) · **Scope:** external
comparison of [chiruu12/marshal](https://github.com/chiruu12/marshal) (listed on mcpmarket as
"marshal-fleet-workflows") and [coleam00/Archon](https://github.com/coleam00/Archon)
([archon.diy](https://archon.diy/)) against stampede at HEAD `a05e282` (v0.6.1) · **Status:** report
only; changes nothing (research dispatch). Companion to
[2026-11-07 prior-art survey](../findings/2026-11-07-agent-orchestration-prior-art.md), which
predates both systems' current shapes and does not cover either.

**Method:** primary sources only — shallow clones of both repos at their default branches
(marshal `main`, pushed 2026-11-02; Archon `dev`, pushed 2026-11-12) into `/tmp/{marshal,archon}-research`
(ephemeral), plus each project's own docs and, for stampede, `CONTEXT.md`, `README.md`, and
`STATE.md` at HEAD. mcpmarket's listing was used only to locate the primary source. Star counts
from the GitHub API on 2026-11-12. Every quote below is verbatim from the cited file.

---

## The three one-liners

| | **Stampede** | **Marshal** | **Archon** |
|---|---|---|---|
| What it is | A Bash swarm harness on the Herdr multiplexer: a standing team of seated agents, a supervisor daemon that re-executes the project's test suite on exact worker commits, and a CAS arbiter that tests the *combined* tree before a human promotes it to `main`. | A Python engine + MCP server + Skills that lets **one driver LLM** (e.g. Claude Code) spawn a **fleet of headless coding CLIs**, each in its own worktree, and read back diffs and per-run cost. YAML "workflows" are sugar over four safe primitives. | A self-hosted TypeScript "factory builder": YAML workflow DAGs with agent nodes, script nodes, loops, and human `wait` gates, driven by **queues** (intake → build → review → merge queue) that take an issue to a merged PR with the human only answering attention items. |
| Maturity (2026-11-12) | v0.6.1, 34 test suites green, in-repo ADRs | ★3, solo author, created 2026-06, MIT, Python/uv | ★23.9k, ~3.5k forks, created 2025-02, MIT, TypeScript/Bun, pushed same day |
| Who is the orchestrator | `loop-bot-herd.sh` supervisor daemon + bounded one-decision-per-turn looper agent | The driver LLM (a human's Claude Code session); skills teach it judgment | The workflow engine + queue sweeps; "a run comes to you only when it needs a decision you own" (`README.md`) |

---

## 1. Marshal — mechanism layer for a driver LLM

Sources: repo README, `docs/design.md`, `docs/mcp-tools.md`,
`skills/marshal-workflow/SKILL.md`, `src/marshal_engine/orchestration/workflow.py`,
`examples/workflows/review.yaml` (all in the clone at its `main`).

**Architecture.** "Marshal sits between a driver agent and a fleet of headless coding CLIs. The
driver plans; Marshal creates worktrees, runs backends with timeouts, records usage to an immutable
ledger, and returns diffs for review." (`docs/design.md`). Layered package
(`interfaces → orchestration → backends → {runtime, accounting} → core`) with the layering
AST-enforced by test. Fleet state lives in the long-lived MCP server, persisted to disk, with a
subtle liveness model (supervisor-pid vs agent-pid; a run is abandoned only when both are gone).
Backends: cursor, opencode, codex, claude-code, command-code, goose, antigravity, zcode, copilot.

**What mcpmarket lists** is the `marshal-workflow` skill — one of eight skills
(`marshal-orchestrate`, `-adversarial-review`, `-panel`, `-plan-consensus`, `-review-gate`,
`-benchmark`, `-dev-cycle`). A workflow is "a named recipe stored as YAML under
`<repo>/workflows/`" with four phase kinds — `fan_out` (goal across N clients in parallel),
`agent` (one client), `collect` (read-only diff aggregation), `integrate` (merge candidates) —
run by name via the `run_workflow` MCP tool. The safety claim: "A workflow **adds no new
execution path**. Each phase is exactly a call you could make yourself … so every run still gets
an isolated git worktree, a hard timeout + kill, and a usage-ledger entry." Integration is gated
off by default (`auto: false` reports candidates; only `auto: true` merges).

**Fleet geometry — the key contrast.** The skill's own authoring tip: "Keep clients in a
`fan_out` working on the **same** target - they're alternatives to compare, or a review you'll
merge once. Independent *parallel* edits to different files belong in marshal-orchestrate."
Marshal's parallelism is **N models racing on one target** (compare-and-pick); stampede's is **N
workers on disjoint targets** (`owns:` partitions + leases, CONTEXT.md §10). These are orthogonal
fleet shapes.

**Integration model.** `integrate` "Merge a run's worktree branch into the workspace's current
branch … Integrate one diff run at a time" (`docs/mcp-tools.md`), driven by the human reviewing
diffs. There is a per-run `verify:` gate (status `verify_failed` when "the workspace's `verify:`
gate rejected them"), but there is **no serialized queue, no combined-tree re-test, and no
standing reviewer** — the merge judgment is the driver LLM's/human's, reading diffs. Marshal's
own epistemic line mirrors stampede's: "`exited_clean` means the process exited 0, not that the
work is correct."

**Marshal's genuine differentiator:** per-provider usage accounting — "per-run cost you can
trust, with unknown costs shown as unavailable, never faked" (README); `report(task_id)` /
`usage()` compare what each client cost on the same task. Stampede records looper usage
(`.herdr-swarm/looper-usage.jsonl`) but has nothing comparable for worker seats.

**Relation to stampede:** complementary layer, like OpenRig was. Marshal is a *mechanism*
library (spawn/collect/integrate + cost ledger) with policy delegated to the driver LLM; stampede
is a *policy-first harness* (verdict protocol, suite gate, reviewer loop, arbiter) whose
mechanism is deliberately dumb Bash. Things stampede could borrow: the usage ledger with
provenance states (`native | admin-api | unavailable`); `marshal drift` (detect when third-party
CLI versions changed since adapter verification — stampede's preflight checks presence, not
drift); validation-before-spawn (`marshal workflows` validates the whole recipe against
`fleet.config.yaml` "before any agent spawns").

## 2. Archon — the closest shipped neighbour yet

Sources: repo README, `.archon/packs/sdlc.yaml`,
`.archon/workflows/sdlc/{review,merge-queue,intake,ship,pr}/archon-*.yaml` (the repo dogfoods its
own SDLC pack), `packages/` layout, [archon.diy](https://archon.diy/) landing.

**Architecture.** TypeScript/Bun monorepo (server + web + CLI + packages: core, workflows,
isolation, git, forge, providers, adapters, chat-slack; plugins: `forge-github`,
`provider-claude/-codex/-pi`, `chat-slack`). Self-hosted, SQLite by default / PostgreSQL
optional; "every run logged locally" with "a full event log and transcript for every run, and
the cost of every run, all stored in your own database" (README). Dispatch surfaces: CLI, web,
Slack, Telegram, GitHub comments. Runs get a git worktree by default.

**Workflow model.** A DAG of nodes: `prompt` (agent), `loop` with `until_bash: "bun run test"`
and `max_iterations` — *code* decides when the loop is done, not the agent's claim — plus
`wait` (human attention item with `form: approval`), `when` conditions over node outputs, and
`cancel`. The README's own framing is almost stampede's vocabulary: "The workflow fixes the
steps, the checks and the gates. The agent supplies the judgment inside each step."

**The SDLC pack** is the part that overlaps stampede most directly — it is a shipped,
queue-driven version of stampede's supervisor→suite-gate→reviewer→arbiter pipeline:

- **Intake/triage** (`archon-intake`): "checks it against the current code and decides what it
  needs: a plan, an investigation, straight to delivery, or a maintainer's look."
- **Build queue** (`archon-build-queue`): "claims the next ready issue, writes the brief and
  runs `archon-ship`: plan, implement, review through specialist lenses, fix the findings, wait
  for CI."
- **Review** (`archon-review`): substantially more elaborate than stampede's reviewer loop —
  "parallel specialist lenses" (seams, code, tests, errors, docs, ux) chosen per-round by a
  route agent; each acceptance item "met with cited evidence or raised as a blocking finding";
  "three independent verifiers judge each blocking finding, and one most of them reject is
  demoted: a pre-existing defect to a discovery, an unreal one to disproved"; verdict pinned to
  an exact commit — "publish refuses a report about any other commit." Advisory and read-only:
  "it judges, it never edits."
- **Merge queue** (`archon-merge-queue`): serialized one-at-a-time merges "through a gate that
  refuses unless the trusted review verdict says Ready at the head, what the pack's ci setting
  trusts passes there (green checks, or a recorded validation), the head contains the default
  branch or merges into it cleanly, and the default branch's CI is not red, and merges pinned to
  that head. … The queue never pushes and never waits for CI: a conflict, a stale verdict or red
  the change caused goes back to the build queue."

**Where Archon and stampede genuinely diverge:**

1. **Who promotes.** Archon's merge queue **lands merged PRs autonomously** once its gates pass;
   the human owns only the attention items (and protected paths — e.g. this repo's own pack
   manifest: "A change to the pack itself never merges on the auto lane: a maintainer reads it
   first"). Stampede's promote is sovereign-human by construction (`promote --confirm` or a
   TTL-bounded session grant that "an agent seat can never grant itself," CONTEXT.md §13).
   Archon trusts the gate; stampede trusts the human behind the gate.
2. **Combined-tree testing.** Archon's gate checks CI *at the PR head* + clean merge + base-not-red,
   and explicitly "never waits for CI" — default-branch CI *after* a merge is "the next sweep's
   first fact" (reactive). Stampede's `arbiter drain` mechanically **re-executes the project's
   test suite on the serialized combined tree** in a detached worktree before anything can be
   promoted (proactive). Archon is GitHub-merge-queue-shaped (trust forge CI); stampede is
   bors-shaped (own the verification). Note the prior-art survey's §4 lesson holds: Archon's
   "the next sweep's first fact" is exactly the red-main detection stampede gets *before*
   promotion, not after.
3. **Substrate & visibility.** Archon is a server + web/chat surfaces; stampede is a terminal
   multiplexer with live panes you can watch and type into (`stampede up`), plus a headless CI
   mode (ADR 0015). Archon's runs are transient workflow executions; stampede's seats are
   long-lived agents with briefs, a seat ledger, and salvage on teardown.
4. **Partitioning.** Archon avoids collisions by *queues claiming one ready item at a time* and
   per-repo run isolation; stampede's `owns:` frontmatter + lease-held-until-integration gives
   explicit disjoint-path dispatch for concurrent workers (CONTEXT.md §10).
5. **Determinism framing.** Archon fixes the *process* (steps, gates) and lets agents supply
   judgment inside steps; stampede fixes the *verification protocol* (exact-SHA verdicts,
   fail-closed suite gate, max-2 reviewer rounds) and lets the looper make bounded dispatch
   decisions. Both reject agent self-certification; they differ in what is code vs agent.

**Relation to stampede:** nearest shipped competitor/sibling, far closer than anything in the
2026-11-07 survey (Vibe Kanban has since sunset; dev-3.0 lacks the integration machinery).
Stampede's unclaimed ground against Archon, per the prior-art survey's "open ground" section,
mostly still holds: mechanical combined-tree re-execution owned by the harness (vs trusting forge
CI), sovereign-human promote as the default posture, salvage epistetics, and path-partitioned
concurrency. Archon is ahead on: multi-surface dispatch (Slack/Telegram/GitHub), per-run cost +
event log + transcript in a database, the verifier-panel review design, plugin ecosystem
(providers/forges/chat as first-class seams), and community scale.

## 3. Side-by-side mechanism coverage

| Mechanism | Stampede | Marshal | Archon |
|---|---|---|---|
| Worktree isolation per worker | ✅ per seat (ADR 0006) | ✅ per run | ✅ per run |
| Parallel fleet geometry | disjoint targets (`owns:`+leases) | same target, N clients (compare) | queues claim items; runs parallel |
| Tests re-executed by harness on exact commit | ✅ Suite Gate (fail-closed) | ⚠️ per-run `verify:` gate | ✅ `until_bash` loops + CI trust at head |
| Adversarial review before integration | ✅ reviewer loop, max 2 rounds | — (driver judges diffs) | ✅ specialist lenses + 3-verifier demotion panel |
| Serialized integration queue | ✅ CAS fast-forward onto integration ref | — (one-at-a-time human merges) | ✅ merge queue, one at a time |
| **Combined-tree** re-test before promote | ✅ `arbiter drain` | — | — (head CI + clean merge + base-not-red; post-merge reactive) |
| Human promotion gate | ✅ default; `--confirm`/TTL grant | ✅ default; `auto: true` opt-in | ⚠️ gates decide; attention items + protected paths |
| Blocked/question semantics | ✅ blocked pauses ticket; grillings human-only | — (driver is the conversation) | ✅ `wait` nodes; answer written back as new scope |
| Usage/cost accounting | ⚠️ looper only | ✅ core differentiator, per-provider ledger | ✅ per run, in database |
| Agent-claim distrust | ✅ verdict = exact SHA + independent suite run | ✅ "exited_clean ≠ correct" | ✅ "code decides when it is done"; review pinned to commit |
| Dispatch surfaces | terminal/panes + headless CI | MCP/CLI/library (driver LLM) | CLI/web/Slack/Telegram/GitHub |
| Persistence | on-disk `.herdr-swarm/` ledgers | MCP-server state, disk-backed | SQLite/Postgres |
| Language | Bash + Python bits | Python 3.11+/uv, Pydantic v2 | TypeScript/Bun |

✅ shipped and core · ⚠️ partial/adjacent · — absent.

## 4. Cheapest borrows, ranked

1. **From Archon: verifier-panel review demotion.** Stampede's reviewer loop is one reviewer
   seat, PASS/BLOCK, max 2 rounds. Archon's "three independent verifiers judge each blocking
   finding, and one most of them reject is demoted" is a direct upgrade to the existing
   `reviews.json` state machine — cheap because it reuses the same verdict plumbing.
2. **From Marshal: usage ledger with provenance.** Record per-seat token/cost per run beside
   verdicts in `.herdr-swarm/`, with marshal's three-state honesty (native / admin-api /
   unavailable-never-faked). The looper-usage file already proves the pattern.
3. **From Marshal: adapter drift check.** `marshal drift` re-verifies backend CLIs when their
   versions change; stampede preflight checks presence once. A stored version snapshot +
   fail-closed drift re-check on `stampede up` is small and matches ADR 0001.
4. **From Archon: attention-item framing for gates.** "One attention item: what it is, why it
   matters, a recommendation and the choices" is a better render of `blocked` tickets and
   grillings than the current alert text — pure briefs/UX change, no mechanism.

## Method notes and limits

- Marshal clone: `main` @ push 2026-11-02 (commit not pinned; shallow). Archon clone: `dev` @
  push 2026-11-12 (shallow). Both are moving projects; line numbers not cited for that reason.
- mcpmarket's listing describes the skill accurately but its "3 stars" author page is the
  secondary source; the repo is canonical.
- Archon's README describes the merge gate's *intended* contract; I read the workflow YAML's
  description but did not execute the engine, so behavior-vs-spec drift is unverified.
- Stampede side read at HEAD `a05e282` only (CONTEXT.md/README/STATE + prior audits); no code
  re-audit was performed, so mechanism claims inherit those documents' accuracy.
- Star/fork counts are API snapshots on 2026-11-12 and will be stale on read.
