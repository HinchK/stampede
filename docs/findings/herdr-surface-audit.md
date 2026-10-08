# Herdr Surface Audit — every call site vs installed CLI

**Ticket:** [HERDR-1](../tickets/herdr-1-herdr-surface-audit.md) · **ADR:** [0017](../adr/0017-herdr-native-coordination-primitives.md)
**Date:** 2026-10-07 · **Installed:** `herdr 0.9.3` (`herdr --version`) · **Reference:** installed `--help` output per command group + [Agent automation docs](https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/agent-automation.mdx) (v0.9.3)
**Prior art:** `docs/findings/herdr-semantics.md` (T-001, live probes on 0.9.1 — historical evidence; load-bearing behaviors re-verified against 0.9.3 help output below, not inherited).

**Verdict key:** **keep** = right primitive today · **adopt** = a better/missing primitive exists (pointer to ticket) · **drop** = legacy/contradicts installed contract (pointer to ticket).

---

## 1. Inventory — shell sources

| # | Call site | Invocation today | Verdict | Citation / reason → pointer |
|---|---|---|---|---|
| S1 | `lib/briefs.sh:115` | `agent wait "$seat" --until idle --timeout 15000` (pre-prompt readiness, blind, `\|\| true`) | adopt | `agent prompt --wait` settles submission+wait atomically (`herdr agent` group help: `prompt <target> <text> [--wait] [--until STATUS]... [--timeout MS]`) → **HERDR-4** |
| S2 | `lib/briefs.sh:119-123` | `agent prompt` + `sleep 1` + `agent send-keys enter` (double submission) | drop | 0.9.3 contract: "agent prompt submits text plus encoded Enter and honors bracketed-paste" (agent-automation §control-surface). Removal is receipt-gated on a live per-kind probe (docs vs operational folklore conflict) → **HERDR-4** |
| S3 | `loop-bot-herd.sh:159` | `agent list` (daemon liveness) | keep | Group help; JSON out, jq-consumed |
| S4 | `loop-bot-herd.sh:584` (`looper_notice`) | `agent prompt looper "$1"` — **bare seat name, not slug-namespaced** | adopt | Names must be "unique live agent names" (agent-automation); bare `looper` fails to resolve the moment a second project's swarm runs, and the `\|\| true` swallows it. Violates CONTEXT.md §4 (_Avoid_ bare seat names) → needs ticket (§4, F-3) |
| S5 | `loop-bot-herd.sh:600` (`worker_feedback`) | `agent prompt "$seat" "$msg"` — single submission | keep | Correct per 0.9.3 (prompt self-submits). Note: opposite convention from S2 — one repo, two submission doctrines; HERDR-4's probe receipt must reconcile both |
| S6 | `loop-bot-herd.sh:668` (`harvest_verdicts`) | `agent read "$seat"` — default source `recent` (soft-wrapped), default 80 rows, feeds both REVIEW VERDICT and ARCH DONE grammars | adopt | ADR 0017 keeps the read+grep scan shape (one read serves two anchor grammars), **but**: (a) source should be `recent-unwrapped` — the strict `…$`-anchored grammars (lines 544, 800) can miss a soft-wrapped anchor line entirely; (b) 80-row default is thin for chatty full-screen agents (0.9.3 alt-screen: rows leaving the alternate screen don't enter scrollback; `--lines N` mouse-scroll history exists for idle agents). → needs ticket (§4, F-1) |
| S7 | `loop-bot-herd.sh:974` | `agent prompt "$worker" "BRIEF (file): …"` (headless brief pointer) | keep | Pointer-not-inline complies with ADR 0003; single submission |
| S8 | `loop-bot-herd.sh:579-600` (alerts path) | alerts surface via `looper_notice` + trace stream only | adopt | `herdr notification show <title> [--body] [--sound]` exists (installed group help), zero call sites repo-wide; retrospective's ~90-min quota-stall visibility gap → **HERDR-5** |
| S9 | `lib/layout_engine.sh:16` | `pane split --pane … --direction --ratio --cwd --no-focus` | keep | Matches `pane split` signature exactly (pane group help); `--cwd`+`--no-focus` ordering is ADR 0007's seat-ordering rule |
| S10 | `lib/layout_engine.sh:26-39,53` | `tab list/create`, `pane list` (before/after diff for race detection), `pane layout` | keep | Group help; IDs parsed from JSON responses per agent-automation ("capture IDs from the response") |
| S11 | `lib/layout_engine.sh:65-68` | rescue `tab create` + `pane move --tab` | keep | `pane move <pane_id> --tab <tab_id>` per group help; cramped-seat rescue (geometry config) |
| S12 | `lib/arbiter.sh:334-335` | `agent list` for promote pane-check (fail-closed) | keep | GATE-1 security seam; unchanged contract |
| S13 | `herdr-loop-swarm.sh:281` | `workspace create --cwd --label --no-focus` | keep | Group help; returns `.result.root_pane` (consumed via jq) |
| S14 | `herdr-loop-swarm.sh:418` (`agent_alive`) | `agent list \| grep -q "\"$name\""` (substring match on JSON) | keep* | Works today because names are prefix-namespaced (`headless-<seat>`, HL-LEDGER-1); a suffix-collision (`foo` vs `foo-2`) would false-positive. Hardening note: jq exact match. No ticket chartered; record only |
| S15 | `herdr-loop-swarm.sh:419` | `agent get "$1" \| jq '.result.agent.pane_id'` | keep | Group help; JSON-path consumption per docs |
| S16 | `herdr-loop-swarm.sh:523,526` | `agent start --kind --pane [-- --model]` | keep | Group help (`agent start <name> --kind KIND --pane ID [-- <agent-args>]`); kind list on 0.9.3 includes `opencode`/`agy`/`claude`. (`--model` value drift is a provider-topic, not CLI grammar — see HL findings) |
| S17 | `herdr-loop-swarm.sh:566-567` | `pane rename` (Ops anchor) + `pane run` (telemetry stream) | keep | `pane run` is the documented primitive for ordinary processes (agent-automation §recipes) |
| S18 | `herdr-loop-swarm.sh:602` | critical-seat readiness: `agent wait --until idle --until done --until working --timeout 2000` (poll per seat) | adopt | Lifecycle wait is the right family, but the readiness signal it really wants is "brief-ack output present": `pane wait-output <pane> --regex <ack>` blocks once instead (ADR 0017 D1) → **HERDR-2** |
| S19 | `herdr-loop-swarm.sh:638` | `pane run` (proxy serve cmd) | keep | Ordinary process, correct primitive |
| S20 | `herdr-loop-swarm.sh:653-672` | kickoff: `agent prompt` then `agent focus` (milestone/brainstorm/queue kickoffs) | keep* | Both valid. Note: focusing a seat marks its `done` seen (agent-automation §states) — focus-after-prompt is fine today (agent still working), but if a kickoff ever waits on completion, focus first, prompt after |
| S21 | `lib/lifecycle.sh:60,80,92` | `pane list --workspace`, `workspace list`, `agent list`+cwd jq (physical-cwd workspace resolution) | keep | ADR 0004's strict physical-match teardown; group help |
| S22 | `lib/lifecycle.sh:316,345,475,518,530` | daemon probe, roster reads, `pane close`, `workspace close` | keep | Selective teardown per seat ledger; `pane close <pane_id>` / `workspace close` per group help |
| S23 | `lib/lifecycle.sh:582-587` (`swarm_verify_seats`) | per seat: `agent get` (registered) + `agent wait --until idle/done/working --timeout` (interactive-ready) | adopt | Same shape as S18 — readiness-as-output-wait → `pane wait-output` on the brief-ack anchor, probe-gated fallback (ADR 0017 D1) → **HERDR-2** |
| S24 | `lib/quota.sh:40` (`quota_probe_kind`) | `agent read "$seat" --source recent-unwrapped` (one-shot, no `--lines`) | keep* | One-shot read is right (QUOTA-1's no-signal contract: absent banner → `unknown`, never fabricated). Notes: (a) consider `--lines 200` so an older banner survives chatty tails (alt-screen, S6 caveat); (b) any *blocking* consumer looping this probe should instead `pane wait-output --regex 'Individual quota reached.*Resets in'` → **HERDR-2** |
| S25 | `lib/preflight.sh:69-83` | `command -v herdr` + `workspace list` ×3 (daemon answering) | keep | Fail-closed preflight (ADR 0005) |
| S26 | `lib/headless.sh` (entire) | **zero** herdr calls | keep | By design (ADR 0015: headless never opens panes); `herdr` off PATH proven live by HORIZON-2 |

## 2. Inventory — brief templates (`briefs/*.in.md`)

| # | Call site | Content | Verdict | → pointer |
|---|---|---|---|---|
| B1 | `arch.in.md:27`, `worker-gh.in.md:31`, `looper.in.md:63,77` | guardrail prose *banning* `pane run`/`send-text`/`agent send-keys` cross-pane injection | keep | Policy text citing the 2026-09-24 incident; not usage |
| B2 | `arch.in.md:43` | teaches `agent prompt … && sleep 1 && agent send-keys … enter` (ARCH UPDATE protocol) | adopt | Same double-enter doctrine as S2; follows HERDR-4's probe receipt whichever way it lands (edit travels with ROUTE-3's arch.in.md change or HERDR-4 follow-up) → **HERDR-4** |
| B3 | `reviewer.in.md:71,99` | teaches the same `prompt && sleep 1 && send-keys enter` tail for verdict delivery | adopt | Same as B2 → **HERDR-4** |
| B4 | `looper.in.md:82-…` | AGY quota gate before agy-seat prompts (QUOTA-3/4) | keep | Matches `lib/quota.sh` contract |
| B5 | all briefs | **no wait-hygiene instructions at all**: no `pane wait-output` for anchor waits, no `agent explain` before pane re-reads | adopt | The retrospective's polling loops and pane-guessing live here → **ROUTE-2** (looper brief) with cross-references |

## 3. Inventory — docs, tests, and the zero-surface gap

| # | Call site | Content | Verdict | → pointer |
|---|---|---|---|---|
| D1 | `README.md:213` | `agent wait "$name" --until idle --until done --timeout …` example | keep | Syntax matches installed group help |
| D2 | `docs/user-guide.md:40,341` | `workspace list` as install probe + remediation table | keep | Correct, minimal |
| D3 | `CLAUDE.md`, `CONTEXT.md`, ADRs, findings/audits | prose references and historical receipts | keep | History is evidence; herdr-semantics.md is 0.9.1-dated and marked as such |
| T1 | 10 suites define stub `herdr()` (`tests/test_*.sh`) | stubbed CLI contract, no live herdr | keep* | Correct hermetic design. When HERDR-2/4/5 add probe branches, stubs must answer the probe commands (each ticket's test criterion covers its own stub growth) |
| G1 | — | `pane wait-output`: **0 call sites** | adopt | ADR 0017 D1 → **HERDR-2** (seats S18, S23, S24b) |
| G2 | — | `agent explain`: **0 call sites** | adopt | ADR 0017 D2 → **HERDR-3** (doctor) + ROUTE-2 (brief hygiene) |
| G3 | — | `notification show`: **0 call sites** | adopt | ADR 0017 D3 → **HERDR-5** |
| G4 | — | `agent prompt --wait`: **0 uses** | adopt | → **HERDR-4** (S1) |
| G5 | — | `agent rename`, `agent attach`, `pane report-agent`/`report-metadata` (agent self-report protocol): 0 call sites | keep (unchartered) | Real future options (seats self-signaling state beats pane-text detection); explicitly **not** chartered in this epic — record only |

## 4. New findings needing a ticket (not covered by HERDR-2..5 scopes)

- **F-1 (S6) — harvest read source/wrapping.** `loop-bot-herd.sh:668` reads default `recent` (soft-wrapped) and feeds strict `…$`-anchored grammars (lines 544, 800). A wrapped anchor line is silently unharvestable — not late, *never*. Fix: `--source recent-unwrapped --lines 200` (+ test). `loop-bot-herd.sh` is HERDR-5's `owns:`; either widen HERDR-5 or charter a small **HERDR-6**.
- **F-2 — verdict grammar vs arch brief text.** `loop-bot-herd.sh:800` requires the anchor line to **end** after the sha (`…[0-9a-fA-F]{7,40}[[:space:]]*$`), but `briefs/arch.in.md:42` teaches `ARCH DONE #<T> <sha> — <summary>`. Every summary-suffixed verdict line is dropped by the grammar. Either the grammar tolerates a trailing summary or the brief mandates a bare anchor line (summary on the next line). Cross-cuts `loop-bot-herd.sh` + `briefs/arch.in.md` — suggest folding into the F-1 ticket (same file) plus a one-line ROUTE-3 brief fix.
- **F-3 (S4) — bare `looper` target.** `looper_notice` prompts bare `looper`, not the slug-namespaced live name; it breaks silently (name-not-found + `|| true`) the day a second swarm runs on the machine. Fix alongside F-1 (same file): resolve the configured looper seat name.

## 5. Alternate-screen read assessment (ticket criterion 3)

Every output-reading seam and its exposure under 0.9.3's alternate-screen model (full-screen agents — opencode, claude, agy — render on the alt screen; rows leaving it do **not** enter host scrollback; `--lines N` beyond the viewport mouse-scrolls history for idle agents only):

| Seam | Today | Exposure | Call |
|---|---|---|---|
| Harvest/review read (`loop-bot-herd.sh:668`) | `recent`, 80 rows | anchor lines live at transcript bottom → usually safe; chatty tail + soft wraps are the real hazards | F-1 fix covers both |
| Quota probe (`lib/quota.sh:40`) | `recent-unwrapped`, 80 rows | banner older than 80 rows reads `unknown` (safe, honest) but stale | optional `--lines 200` (HERDR-2 note) |
| Brief-delivery / lifecycle waits | lifecycle waits, no reads | none | — |

## 6. Summary counts

39 graded rows: **28 keep** (4 with hardening notes), **11 adopt/drop** — all mapped to HERDR-2/3/4/5, ROUTE-2/3, or the three new findings F-1..F-3 (one suggested follow-up ticket). Zero surface calls contradict the installed 0.9.3 grammar; the risks are doctrine-level: two submission conventions (S2 vs S5), wrapped-source anchored greps (F-1), and a brief-vs-grammar verdict format mismatch (F-2).
