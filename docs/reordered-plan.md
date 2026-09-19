# Reordered Plan: Universal Herdr Swarm (`herd-swarm`)

**Author:** `pm` · **Date:** 2026-09-19 · **Reviewed against:** `main` @ `b1169ff`
**Inputs:** `maps/universal-herdr-swarm.md`, `maps/tickets/*`, `STATE.md`, `docs/findings/*`,
`docs/audits/2026-09-19-pm-herd-audit.md`, and independent runs of the new libs.

---

## 1. Review of the updated milestones

In about 30 minutes the herd closed eight map tickets (T-014, T-001, T-009-spike, T-002, T-007a, T-003, T-006, T-011).
The research is strong. T-001 in particular replaced guesses with probes. But **"Decisions so far" is being read as
"shipped", and it isn't.**

### 1.1 What I verified

| Ticket | Map claim | PM verification | Status |
|---|---|---|---|
| T-014 git baseline | Done | `95044cc` present | ✅ Done |
| T-001 herdr semantics | V1/V3 resolved | Findings are probe-backed. V1 applies only to `--current` (launcher doesn't use it). V3 confirmed global. `·` illegal. | ✅ Done, and it changes T-005 (see 1.3) |
| T-002 profile, fail-closed | "Validated" | Ran `ensure_profile` in a no-remote, no-manifest dir: **exit 1**. Cached REPO + no tests: **exit 1**. `detect_test_cmd` generic: **exit 1**. | ✅ Lib works. ⚠ Not integrated. ⚠ Interactive "none" gap (D3). |
| T-007a supervisor fixes | Dedupe + `note` fixed | `note`/`step` defined. `jq` exact-match dedupe replaces substring grep. | ⚠ **Partial.** Identical re-verdict still skipped (D2). |
| T-003 TOML config | "Implemented" | `config_dump_env` emits namespaced `SEAT_*` exports | ⚠ Slug not sanitized, unquoted interpolation (D4). Not integrated. |
| T-006 brief templating | "Implemented" | `lib/briefs.sh` + `briefs/*.in.md` exist | ⚠ Not integrated; launcher still does `cat "$brief_file"` inline (`herdr-loop-swarm.sh:302`). |
| T-011 lifecycle | "Implemented" | Read `swarm_down` | ❌ **Unsafe teardown (D1).** Not integrated. |
| T-009 telemetry | Schema spike only | `docs/findings/telemetry-schema.md` | ✅ Spike done; wiring still open. |

### 1.2 The integration gap: the headline finding

`herdr-loop-swarm.sh` is **unchanged since 2026-09-17**. It sources only `layout_engine.sh`. Nothing sources
`profile.sh`, `config.sh`, `briefs.sh`, or `lifecycle.sh` except each other. So the entrypoint the driver actually runs
**still has every original defect**:

- `:186` `REPO="${REPO:-Standard-Pentest/kultivait}"`: wrong-repo default is still live
- `:142` `TEST_CMD="true"`: always-green gate still live (with `:186`, mode `a` can still drive kultivait's backlog ungated)
- `:302` inline brief delivery; `:255` un-namespaced `agent_alive` greps

The herd built the parts for the fix but never swapped them into the launcher. **Integration is now the critical path**, not more library work.

### 1.3 Plan drift between the two sources of truth

`maps/universal-herdr-swarm.md` and `STATE.md` disagree, and STATE is stale:

- STATE §1 still records the decision as `arch·<slug>`. T-001 proved `·` is rejected by herdr. The map correctly says `-`/`_`.
- STATE §2 still shows the original M1/M2/M3 split (T-002 in M2, T-013/T-004/T-005 in M1).
- STATE §3 lists T-007a/T-003/T-006/T-011 as candidates; they're already committed.

**Rule going forward:** the map is the plan of record; STATE.md is a short checkpoint that links to it and restates nothing.

---

## 2. New defects in the fresh code

Evidence key: **[probed]** = reproduced by running code; **[inspection]** = read from source, not executed.

| ID | Sev | Where | Defect | Fix |
|---|---|---|---|---|
| **D1** | **HIGH** | `lib/lifecycle.sh:28` `find_workspace_by_cwd` | `$HERDR_WORKSPACE_ID` wins over the `dir` argument. `lifecycle.sh down ~/other-repo` run from any herd pane **closes the live swarm workspace** (every pane, including the driver's shells), with no confirmation. The label fallback matches on `basename`, so same-named repos collide. **[probed premise]** a seated pane (`pm`, `wM:p4`) exports `HERDR_WORKSPACE_ID=wM`, so branch 1 fires. `down` itself was not run (destructive). | Resolve **only** by the `dir` argument (cwd match on the workspace, then agents). Never use the env var for `down`. Require the typed workspace label or `--yes` before `workspace close`. Close only panes the herd seated (record pane IDs in `.herdr-swarm/seats.json` at `up`). |
| **D2** | MED | `loop-bot-herd.sh:105` | After RED, a re-verdict whose text is **identical** (e.g. `ARCH DONE #42`) matches "exact verdict line already evaluated" and is skipped forever. The fix works only if arch changes its wording. **[inspection]** | Make the verdict protocol carry the commit: `ARCH DONE #<n> <sha>`. Dedupe on `(ticket, sha)`. Add this to the arch brief template. |
| **D3** | MED | `lib/profile.sh:197-199` | Interactive prompt: **pressing Enter** saves `TEST_CMD="none"` ("skip suite gates") and caches it in `profile.env` permanently. Nothing downstream defines `none` yet. If a consumer treats it as "skip", the fake-green path comes back through the prompt. **[inspection]** | Empty input re-prompts. `none` is allowed only as an explicit typed value, and **mode `a` (auto-queue) and the supervisor gate must refuse to run when `TEST_CMD=none`**. |
| **D4** | MED | `lib/config.sh:94-99` | `slug` and `toml_path` are pasted into Python source inside `'…'` (quote-breaking), and emitted `export` lines carry unescaped TOML values meant for `eval`. **[probed]** `config.sh dump MyApp` → `SEAT_NAME_arch="arch-MyApp"` (uppercase is illegal per T-001 §C); `config.sh dump "a'b"` → Python `SyntaxError: unterminated string literal`. The slug isn't normalized to herdr's grammar `[a-z][a-z0-9_-]*`, so dirnames like `MyApp` or `loop.bot` produce `invalid_agent_name` at seat time. | Pass slug/path via `sys.argv`. Emit with `shlex.quote`. Add `slugify()` (lowercase, `[^a-z0-9_-]`→`-`, prefix a letter if one is needed) in one place, reused by config, briefs, lifecycle and the supervisor. |
| D5 | LOW | `loop-bot-herd.sh:24-25,112` | Supervisor still hardcoded to kultivait + `uv run pytest` | Expected; this is T-007b. |

---

## 3. Reordered plan

Principle: **make the thing people run safe first, then make it general, then make it nice.** Nothing ships until it's
wired into the entrypoint and exercised end to end.

### M1 — Safe entrypoint (critical path)

| Order | Ticket | Scope | Done when |
|---|---|---|---|
| 1 | **T-011-fix (D1)** | Make `down` resolve by dir only, require confirmation, close only recorded seat panes | `down <other-dir>` from inside `wM` touches nothing in `wM`; a scratch-workspace probe shows only seat panes closed |
| 2 | **T-002-fix (D3)** + **slugify (D4)** | Empty prompt re-asks; `none` blocks mode `a`; shared `slugify()`; argv-safe config emitter | Probe: Enter doesn't cache `none`; `MyApp` → `myapp`; slug `a'b` doesn't break the emitter |
| 3 | **T-INT-1: integrate profile** | Launcher calls `ensure_profile`. **Delete** the `:186` default and the `:142` `true` fallback. Workspace keyed on cwd (the residual T-004). | `grep -n 'Standard-Pentest\|TEST_CMD="true"' herdr-loop-swarm.sh` is empty; launching in a no-remote dir exits 1 before any pane is split |
| 4 | **T-007a-fix (D2)** | `ARCH DONE #n <sha>` protocol + `(ticket, sha)` dedupe | Fixture: RED → same-text re-verdict with a new sha → gated again |
| 5 | **Exercise the gate** | `loop-bot-herd.sh once` against kultivait with one real verdict | `session-verdicts.jsonl` exists with a green record whose sha matches HEAD |
| 6 | **T-015a: README truth** | Strike unshipped claims (telemetry, circuit breakers, "self-healing") | Every README claim maps to a file that the launcher actually runs |

**M1 exit:** the launcher can no longer target the wrong repo, gate on `true`, or close the wrong workspace, and
the supervisor gate has run once for real.

### M2 — Generalize (config-driven, namespaced)

| Order | Ticket | Notes |
|---|---|---|
| 7 | **T-INT-2: integrate config (T-003)** | Launcher seats from `SEAT_*` exports; delete hardcoded seat lines `:308-319`. Refresh stale model IDs in `swarm.config.toml` in the same change, since this is when they go live. |
| 8 | **T-005: namespacing** | Now justified (T-001 B1). Use `<seat>-<slug>` via `slugify()`. Record seated pane IDs in `.herdr-swarm/seats.json` (feeds D1's teardown). |
| 9 | **T-INT-3: integrate briefs (T-006)** | Launcher renders and delivers by file path; delete `cat "$brief_file"`. |
| 10 | **T-007b: supervisor genericize** | `STATE_DIR`, `REPO_DIR`, and the suite command from `profile.env`; seats from config. |
| 11 | **T-008: preflight** | Before any workspace mutation. |

**M2 exit:** `up` in two different repos seats two independent, namespaced herds, each gating on its own suite.

### M3 — Lifecycle & observability

| Order | Ticket | Notes |
|---|---|---|
| 12 | T-INT-4: `up`/`down`/`status` subcommands | Wire `lifecycle.sh` (post-D1) into one entrypoint |
| 13 | T-010: seat verification | `agent start` already waits for readiness (`--timeout`); add brief-acknowledged check only |
| 14 | T-009: telemetry wiring | Implement the spike's `domain.action` schema; move logs off `/tmp` into `.herdr-swarm/` |
| 15 | T-015b: README/user guide | Full rewrite after behavior settles |

### Deferred / cut

- **T-012 ops-tab expansion** (reviewer on by default, status-board pane): **deferred.** New capability, not correctness.
  Re-propose after M3 with evidence that the reviewer catches something.
- **T-013 full bats + `HERDR_FAKE` shim:** **right-sized.** Add shellcheck to a `make check` now. Add bats only for
  `profile.sh`, `slugify()`, and the config emitter, the pure functions where the D3/D4 bugs lived. No herdr mock
  until M3 proves one is needed.
- **NFR "p95 `up` < 60s":** **cut.** No evidence it's a problem.
- **Map "Not yet specified" items** (parallel worktree fan-out, cross-LLM quota probing, GitHub two-way sync): stay parked until M2 exits.

---

## 4. Process corrections for looper

1. **Done means integrated.** A ticket that adds a lib closes only when the launcher or supervisor calls it and the
   old code path is deleted. Add "old path removed: `grep` returns empty" to every T-INT done-criterion.
2. **Destructive commands need a probe receipt.** Any ticket touching `pane close` / `workspace close` must include a
   scratch-workspace probe log (as T-001 did) before it closes.
3. **One plan of record.** Update the map; reduce STATE.md to a checkpoint that links to it. Fix the `arch·<slug>` line now.
4. **Pace:** eight tickets in ~30 minutes, with no one exercising them, is how D1–D4 got through. Put pm (or reviewer)
   on a verification pass after every two closed tickets during M1.

---

## 5. Decisions needed from the driver

1. **Approve this ordering**, and specifically D1 as the top priority, before any `down` is run.
2. **Entry-point identity:** confirm the launcher plus supervisor is the product, with the parallel Claude variant parked
   (unchanged recommendation from the audit).
3. **`TEST_CMD=none` semantics:** should a project with no test suite be allowed to run the herd at all? Recommended:
   seat-only (`s`) and interactive modes yes; auto-queue (`a`) and resume (`r`) no.
