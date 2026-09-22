# PM Recommendations — Herd Audit & Multi-Provider PRD Review

**Author:** `pm-hinchk-stampede` (Claude, root seat)
**Date:** 2026-09-22
**Scope:** Response to looper's request for review of `maps/public-multi-provider.md`
(`a85755d`), disposition of untracked audit/dogfood docs, CLAUDE.md suite-count
refresh, and the `OVERSEE: audit the herd` standing task.

---

## 1. Herd audit (empirical)

`make check` this session: **8/8 suites green, 205/205 assertions, 0 shellcheck
warnings.**

```
test_arbiter      38   test_config      18   test_gh_sync   27
test_partition    29   test_worktree    42   test_profile   18
test_pyenv        16   test_async_gate  17
```

GitHub: 0 open issues, 0 open PRs, `main`↔`origin/main` in sync (0/0), repo
private (intentional). `maps/tickets/` has one active ticket
(`dispatch-partition-lease-wiring.md`, DOG-16, dispatched to `arch-2`), zero
others in flight. Five tickets sit parked pre-dogfood-pivot — worth a look
before the next wave to confirm they're still wanted.

**Fixed directly** (root-seat write, `CLAUDE.md` is in-bounds — root docs, not
on the forbidden-path list): the `Commands` suite table was stale (6 suites /
132 assertions listed; live reality is 8 / 205, with `test_config.sh` and
`test_gh_sync.sh` undocumented entirely). Corrected in `22bbcda`.

## 2. Public-readiness review disposition (`docs/audits/2026-09-21-public-readiness-review.md`)

Verified against current HEAD: **every Tier-1 and nearly every Tier-2 finding
in that review is already resolved** (LICENSE, CI, `lib/pyenv.sh` resolver,
`seats.pi` disabled, `lib/gh_sync.sh` tested, 473→53 and 439→3 name/link hits
— all remaining hits are in audit/ADR history, correctly preserved as record).
The review is now historical, not a live punch list.

**Recommendation:** commit the review file as-is — it's accurate evidence of
what closed. Commit `docs/dogfood/` alongside it as a record of a two-clone
dogfooding plan that was drafted but never actually run (the
`~/Fun/stampede-dogfood` clone on disk is a synced mirror at `main`'s current
HEAD, not a divergent run — the backlog got worked directly against this repo
instead). Add one line to `STATE.md` noting that deviation. Neither file is
blocking.

## 3. Multi-Provider PRD review (`maps/public-multi-provider.md`, `a85755d`)

Currently sitting on `arch-1`'s worktree branch (clean, single commit), not
yet on `main`.

**Scope boundaries: sound.** Provider-blindness stays confined to pane-seating
and brief-delivery, consistent with the actual architecture. Tenet 5
("instrument before claiming") directly forecloses repeating the
public-readiness review's §3 finding (unsupported "80%+ token reduction"
claim).

**Wave/hazard check — verified `owns:` disjointness across all 11 tickets:**

- Wave 8 (PUB-1, alone), Wave 9 (PUB-2/3/4/5, parallel): file-disjoint, confirmed.
- Wave 10 (PUB-6, alone): owns `herdr-loop-swarm.sh`/`lib/config.sh`/
  `swarm.config.toml`. Correctly sequenced alone, after DOG-16 — the map's own
  hazard note flags this. Good call given this project's history with exactly
  this class of coupling bug (BASH32-FLOOR, PROFILE-MAKE).
- Wave 11 (PUB-7/8/9/10, parallel), Wave 12 (PUB-11, alone): disjoint,
  dependencies correctly gated.
- All target paths (`bin/`, `lib/cli/`, `examples/`, `VERSION`,
  `CHANGELOG.md`, `lib/providers.sh`, `lib/quota.sh`, `docs/user-guide.md`)
  confirmed absent on disk — genuinely additive, zero collision risk.
  `briefs/reviewer.in.md` (PUB-8) already exists and extends the existing
  disabled `seats.reviewer` — consistent, not a conflict.
- Minor cosmetic gap: the map's "Dependency edges" prose line omits PUB-6's
  and PUB-10's `blocked_by` (both correct in ticket frontmatter). Not worth
  blocking on — `blocked_by` isn't machine-enforced anywhere in this project.

**Verdict: approve as charted.** No scope creep, no unmitigated file-ownership
hazard.

**Concurrency call:** `arch-1` is idle right now (last commit was this PRD
chart) while `arch-2` works DOG-16. PUB-1 has zero file overlap with DOG-16,
so it's technically safe to release Wave 8 in parallel. **Recommend holding
anyway** — `partition_check` has no caller yet (DOG-16 is what wires it in),
so nothing but human/looper discipline enforces disjointness right now.
Running a second backlog concurrently with the ticket that fixes the
enforcement mechanism is exactly the hope-based concurrency this project has
paid scars to avoid (BASH32-FLOOR, P3-FLAKE-1).

## 4. Recommended sequence for looper

1. Let DOG-16 finish on `arch-2`; keep `arch-1` idle rather than releasing
   Wave 8 early.
2. On DOG-16's green verdict + integration, merge `a85755d` (multi-provider
   PRD) onto `main`, then release Wave 8 (`PUB-1`) to `arch-1`.
3. In the same pass as the DOG-16 integration commit: commit
   `docs/audits/2026-09-21-public-readiness-review.md` and `docs/dogfood/`,
   with a one-line `STATE.md` note on the dogfood-plan deviation (§2 above).
4. Before opening Wave 8, re-check the five parked pre-dogfood tickets
   (`arbiter-batch-integration`, `cross-llm-quota-and-credit-probing`,
   `launcher-target-dir-and-sha-validation`,
   `safe-workspace-targeting-in-launcher`,
   `worktree-config-and-ledger-integration`) — confirm still wanted post-rename
   or formally retire them.

No forbidden-path work required from me here; all of the above stays within
`docs/`/`maps/`/`STATE.md` or is arch-seat scoped (DOG-16, PUB-1..11).
