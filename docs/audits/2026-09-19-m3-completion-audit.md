# M1–M3 Completion Audit — 2026-09-19 (`pm`)

**Against:** `docs/reordered-plan.md` · **Reviewed:** `main` @ `74e8b81` (25 commits, 05:46–06:18)
**Method:** read every changed path, ran every non-destructive entry point, re-ran the D1–D4 probes.
Evidence key: **[probed]** = executed; **[inspection]** = read, not run. `down` was not run against a live workspace.

## Verdict

**Code-complete, and the prototype's defects are gone. Not yet field-proven.** Between 05:40 and 06:18 the herd went from
"libraries built next to a fragile launcher" to one entrypoint (`up · status · verify · down`) that is profile-driven, fails closed,
emits telemetry, and has 0 shellcheck warnings. But the new `up` path has **never seated a herd**: the live seats are still the
unnamespaced ones from the old launcher. The supervisor's only real run recorded **two false GREEN verdicts** (H1). Closing M3 is fine;
declaring the universal swarm shipped is not, yet.

## Transition: prototype → universal swarm

| Concern | Prototype (09-17) | Now (`74e8b81`) | Evidence |
|---|---|---|---|
| Wrong-repo default | `REPO=…kultivait` | Removed; `ensure_profile` fails closed | [probed] no-remote dir → exit 1; `grep Standard-Pentest` empty |
| Fake-green gate | `TEST_CMD="true"` | `test_cmd_is_runnable` rejects `""`/`none`/`true`; mode `a` aborts | [probed] + [inspection] `herdr-loop-swarm.sh:319` |
| Teardown | closed `$HERDR_WORKSPACE_ID` blindly | strict cwd match, confirm gate, seat ledger | [probed] unrelated dir → no workspace, nothing closed; herd root → `wM` |
| Agent names | global `arch` | `<seat>-<slug>` via `slugify` | [probed] `MyApp→myapp`, `a'b→arch-a-b` (no crash), `9lives→s-9lives` |
| Brief delivery | inline `cat` | rendered templates + file/nonce path | [inspection] `cat "$brief_file"` gone |
| Supervisor | kultivait + pytest hardcoded | profile-bound `REPO_DIR`/`TEST_CMD`, `(ticket, sha)` dedupe | [inspection] no `seeds/_KULT_`/`uv run pytest` |
| Preflight | none | 9-check matrix | [probed] `9 ok, 0 warn, 0 error` |
| Seat verification | none | `verify` subcommand | [probed] 5/5 ready |
| Telemetry | dead module | `telemetry.py log/stream`, wired into launcher + supervisor | [probed] event round-trips to JSONL with the T-009 schema |
| Decisions | tribal | ADR 0001–0005 + `CONTEXT.md` | present |

## Ticket checklist

| Ticket | Commit | Status |
|---|---|---|
| T-011-fix (D1) | `52f9937` | ✅ [probed] |
| T-002-fix (D3/D4) | `44c0d56` | ✅ [probed]; empty prompt re-asks |
| T-INT-1 profile | `b6237a0` | ✅ |
| T-007a-fix (D2) | `dd54248` | ✅ [inspection]; sha from the verdict line, falls back to HEAD |
| T-015a README truth | `d3e2c80` | ✅ |
| T-INT-2 config + **T-005** + **T-INT-3** | `2455bc5` | ✅ one combined commit (acceptable; but it makes bisecting harder) |
| T-007b supervisor | `c308f2b` | ✅ |
| T-INT-4 preflight/subcommands | `5ca2049` | ✅ [probed] `status`, `verify`, preflight |
| T-010 seat verification | `33a07b3` | ✅ [probed]; see L2 |
| T-009-impl telemetry | `8b059f2` | ✅ [probed] engine; ⚠ no live trace yet (`.herdr-swarm/traces/` empty) |
| **M1 step 5: exercise the gate** | none | ❌ **Not done properly.** See H1. |

## Library wiring

| lib | Wired from | Exercised |
|---|---|---|
| common, profile, config, briefs, lifecycle, preflight, layout_engine | launcher (+ supervisor for common/profile/config) | profile, config, lifecycle, preflight: [probed]; briefs and layout: live `up` only |
| telemetry.py | launcher + supervisor | [probed] standalone |
| **agent_guard.sh** | **nothing** | ❌ orphan. `verify` superseded it. Delete it, or give it a caller. |

## Findings

**H1 — HIGH [probed]: the supervisor turns pane text into verdicts.** `loop-bot-herd.sh:178` greps `ARCH DONE #[0-9]+`
*anywhere* in a seat's scrollback. The only real run (05:58, `~/.kultivait/loop-bot/session-verdicts.jsonl`) filed:

```
ticket 99 GREEN  verdict: "Careful: sha regex on the verdict line — ARCH DONE #99 aaa1111 → capture aaa…"
ticket 42 GREEN  verdict: "VERDICT_LINE='ARCH DONE #42 ddd4444' … resetsAt …"
```

These were arch's *test fixtures and discussion* on screen, not completions. The "green" was the kultivait suite passing, unrelated
to either ticket. The looper was then told the verdicts were filed. Under the current code, a green or skipped record permanently retires the ticket.
**Fix:** stop scraping the screen. Read verdicts from the nonce reply file (`.herdr-swarm/channel/…`) that T-INT-2 already built, or at
minimum anchor the pattern `^ARCH DONE #[0-9]+ [0-9a-f]{7,40}$` on a whole line. Purge the two bogus records.

**M1 — MED: resume mode (`r`) is ungated.** Only mode `a` checks `test_cmd_is_runnable`. `r` also drains tickets on its own
(the plan's §5.3 recommendation covered both). [inspection] `herdr-loop-swarm.sh:300-315` (and its kickoff at `:518`).

**M2 — MED: "skipped" is treated as filed.** With a non-runnable `TEST_CMD` or `gate-off`, the supervisor records `skipped`, permanently
retires the ticket, and tells the looper "filed verdict (skipped)". A skipped ticket should go to the human, not be closeable.
[inspection] `loop-bot-herd.sh:142,163-166,176`.

**M3 — MED: the new `up` path has never run.** No `profile.env`/`seats.json` in the herd repo; live seats are `looper`, `arch`… (not
`arch-<slug>`). Namespacing, seat ledger, brief render/nonce delivery, layout under config, and live telemetry are unproven end to end.

**L1 — LOW:** the gate tests the working tree at `REPO_DIR` HEAD, not the verdict's sha. If there's no git, the sha falls back to `"unknown"`, so every
sha-less verdict dedupes together (the D2 bug returns in non-git repos).
**L2 — LOW:** `verify` reports `ready` for seats whose status is `working` (looper, pm). "Ready" means *interactive*, not *idle*. Label it that way.
**L3 — LOW:** an old ad-hoc `~/.herdr-loop-swarm/traces/traces.jsonl` and the pre-T-007b state dir `~/.kultivait/loop-bot/` still exist.
Retire them so there's one telemetry sink.

## Recommendations (before calling the swarm shipped)

1. **H1 first:** replace scrollback scraping with nonce-file verdicts. Purge tickets 99 and 42 from the verdict log.
2. **Dogfood `up`:** run it in a scratch repo (`s` mode), then `verify`, `status`, and `down --yes` on the *scratch* workspace. Attach
   the transcript as a receipt. Then re-seat this herd with the new `up` so the live seats carry `-<slug>` names and a `seats.json`.
3. **Exercise the gate for real (M1 step 5 redo):** one genuine `ARCH DONE #n <sha>` through the nonce channel. Record the result in
   `.herdr-swarm/session-verdicts.jsonl` with a matching sha and a telemetry `suite.verdict` event.
4. **M1 + M2:** gate mode `r` like `a`, and route `skipped` verdicts to the human instead of the looper.
5. **Cleanup:** delete `agent_guard.sh` (or wire it in), retire the legacy trace and state dirs, and relabel `verify`'s "ready".
6. **Pace note:** 11 tickets in 38 minutes is fast and mostly clean. The one real miss (H1) happened because nothing checked
   that a GREEN corresponded to the ticket it was filed for. Add "a verdict's sha exists and touches the ticket's files" to the gate.
