# P2-4 Spec — Arbiter Branch Merge and PR Reconciliation (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `0cfae5d`
**Reviewed:** ADR 0006 §4.E, `docs/worktree-swarm.md` §7 (Arbiter Rules 1–3), ADR 0007, `lib/gh_sync.sh`, `lib/worktree.sh`,
P2-3 spec (verdict schema). **Evidence:** git 2.55.0 probes in a scratch repo, quoted inline.

## 0. Summary and one blocking prerequisite

The arbiter is a **deterministic, serialized shell process** (`lib/arbiter.sh`), not an LLM seat, for the happy path. It integrates
exactly the **gated sha** into a dedicated **integration branch** using compare-and-swap, gates the *combined* result, and stops there.
Moving `main` is a **human promotion step** (local `--ff-only` in the root, or a PR). LLM seats are used only to *resolve* conflicts,
and that happens on the worker's own branch, never inside the arbiter.

This narrows `docs/worktree-swarm.md` §7 Rule 1 ("fast-forward merge or squash into `main`"). The reasons are measured in §2.3.

### Blocking prerequisite (live on `main`): `-B` re-seat still wipes seat branches

ADR 0007 §C adopted the stale-branch gate, but it was never implemented. `lib/worktree.sh:56` still runs
`git worktree add -B "$branch" … "$base_ref"`, and since P2-2 the launcher calls it on every `up` (`herdr-loop-swarm.sh:426`, base `HEAD`).
Probe (P2-3 spec): a seat branch with 20 unmerged commits goes to **0** on re-seat.
`swarm.config.toml:42` sets `worktree = true` on arch, and no `swarm/*` branch exists yet, so **the hazard is armed but has not fired.**
The arbiter's whole premise is that un-integrated work waits safely on the seat branch. **Fix ADR 0007 §C before the next `up` and before P2-4:**
`-b` for new branches; for existing ones attach without reset, and only if `rev-list --count <integration-or-base>..<branch> == 0`
or `--adopt-branches` (and then *attach*, never reset).

---

## 1. Triggering

**Source of truth:** `.herdr-swarm/session-verdicts.jsonl` (P2-3 schema). A record is **integration-eligible** iff all hold:

| Field | Condition |
|---|---|
| `suite` | `"green"` |
| `isolated` | `true` (root-seat work is already on the base branch; nothing to integrate) |
| `sha` | full 40-char sha (P2-3 §3.2 expands it); V1–V3 provenance passed |
| `own_commits` | ≥ 1 |
| not yet in `.herdr-swarm/integration.jsonl` with status `integrated` or `superseded` for the same `(ticket, sha)` |

**Mechanism:** after writing a green isolated record, the supervisor calls `lib/arbiter.sh enqueue <ticket> <seat> <sha>`, which appends
`{status:"queued"}` to `integration.jsonl`. `arbiter.sh drain` runs from the supervisor's poll loop. It processes the queue **oldest first,
one at a time**, under a `mkdir .herdr-swarm/arbiter.lock` (bash 3.2-safe, pid-stamped, stale after process death).
`drain` is idempotent: re-running it after a crash resumes from the last record.

**Supersession:** if a newer green `(ticket, sha')` for the same ticket arrives while `(ticket, sha)` is still queued, the older record becomes
`superseded`. The arbiter integrates the latest gated state of a ticket, not every intermediate one.

**Control:** `loop-bot-herd.sh arbiter-on|arbiter-off` in `control.json`, **default off** (same pattern as `frontier_drain`). Human opt-in
for the first sessions.

---

## 2. Merge safety

### 2.1 Refs and working copies

| Ref / tree | Owner | Written how |
|---|---|---|
| `swarm/<slug>/<seat>` (seat branch) | the worker only | worker commits in its worktree. **The arbiter never writes it.** |
| `swarm/<slug>/integration` | arbiter only | `git update-ref <ref> <new> <expected-old>` (CAS) |
| arbiter worktree `.herdr-swarm/worktrees/arbiter-<slug>` | arbiter only | **detached HEAD**, so it never has a branch checked out that someone else might move |
| `main` (base) | **human** | promotion (§2.4) |

The integration branch is created from the base at the first integration of a run, with the ledger's `base_sha` recorded in `integration.jsonl`.

### 2.2 Integrating one queued record

```
lock → I0 = rev-parse swarm/<slug>/integration
1. if is-ancestor(I0, sha):                          # fast-forward case
       candidate = sha
   else:                                             # diverged: build a merge commit off-branch
       arbiter worktree: checkout --detach I0
       git merge --no-ff --no-edit -m "integrate #<ticket> (<seat> @ <sha7>)" <sha>
         conflict → git merge --abort → record {status:"conflict", files:[…]} → §2.5 → next record
       candidate = HEAD
2. gate the candidate: arbiter worktree checkout --detach <candidate>; clean-tree precheck; TEST_CMD (P2-3 §2 rules, TMPDIR per arbiter)
       RED → record {status:"integration_red", candidate, log} → §2.5 (do NOT advance the ref)
3. git update-ref refs/heads/swarm/<slug>/integration <candidate> <I0>        # CAS
       CAS failure → record {status:"retry"} and loop to 1 with the new tip (max 3, then "blocked")
4. record {status:"integrated", sha, merge_sha:candidate, integration_before:I0, gate:{…}} → telemetry arbiter.integrated
unlock
```

Why this shape:
- **Each branch passing doesn't mean the combination passes.** Two green branches can break each other. The combined result is gated (step 2)
  *before* the ref moves, so `integration` only ever points at a gated tree.
- **Integrate the gated sha, not the branch tip.** The worker may have moved on since the verdict. The sha is what was tested.
- **`--no-ff` on divergence** keeps a merge commit per ticket, so a single `git revert -m 1 <merge_sha>` backs one ticket out. Squash is not
  used by the arbiter because it breaks P2-3's V2/V3 provenance checks for later verdicts on the same branch. Squash stays an option at human promotion time.
- **CAS (step 3):** plain `update-ref` loses 11/12 concurrent updates silently. CAS rejects the losers loudly (advisory §1.1). The arbiter is
  serialized by its lock, so CAS is defence in depth against a human or a second arbiter.

### 2.3 Why the arbiter never moves `main` (probed)

With `main` checked out in the root (looper, pm and the human stand there):
- `git branch -f main X` → **refused**: `cannot force update the branch 'main' used by worktree`.
- `git update-ref refs/heads/main X` → **accepted silently**, and the root then shows the integrated file as a **staged deletion** (`D  w6`).
  The next commit anyone makes in the root would silently revert the integration.

So a checked-out branch must never be moved from outside its worktree. That rules out the "fast-forward into `main`" path in
`docs/worktree-swarm.md` §7 Rule 1 as an unattended arbiter action.

### 2.4 Promotion to the base branch (human gate)

`lib/arbiter.sh promote [--pr]`, run by the human, or by the looper only after an explicit human "go":

| Mode | Preconditions | Action |
|---|---|---|
| local (no remote, e.g. this repo) | root on `base_branch`, `git status --porcelain` empty, `is-ancestor(main, integration)` | `git -C <root> merge --ff-only swarm/<slug>/integration`, run **in the root worktree**, so the index moves with the ref |
| `--pr` (remote exists) | push approval (existing invariant) | `git push <remote> swarm/<slug>/integration` → `gh pr create --base <base> --head swarm/<slug>/integration --title "herd: integrate <run_id>" --body-file <generated>` |

If `main` has moved independently, so the ff precondition fails, **promotion refuses**. The arbiter can re-base the *integration branch* by merging
`main` into it (a normal §2.2 cycle with `main`'s tip as the "sha", gated). It never rebases onto `main` in place.

The generated PR body lists, per integrated ticket: ticket id, seat, gated sha, merge sha, gate result and log path, and a
`Closes #<github_issue>` line when the ticket's frontmatter has one (§4).

### 2.5 Conflicts and integration-RED

Conflicts are resolved **on the worker's branch by the worker**, so the gate and provenance chain stay intact:

1. The arbiter records `conflict` (files) or `integration_red` (log), and prompts the owning seat through the nonce channel:
   `ARBITER: #<ticket> conflicts with integration @ <I0-sha7> on <files>. In your worktree run: git merge swarm/<slug>/integration,
   resolve, run the suite, commit, then re-verdict ARCH DONE #<ticket> <new-sha>.`
2. The worker's new sha goes through P2-3 again. Its V2/V3 checks still hold, because the merge commit is on the seat branch and has own_commits ≥ 1.
3. It becomes a new queued record, and the old one is marked `superseded`.
4. Two consecutive `conflict`/`integration_red` results for the same ticket ⇒ `blocked`, and the arbiter escalates to the human and looper (mirrors the looper brief's flake guard).

The arbiter **never** resolves conflicts itself, never uses `-X ours/theirs`, and never rewrites a seat branch.

---

## 3. Seat branch lifecycle after integration

| Moment | Seat branch | Worktree |
|---|---|---|
| integrated | **retained, not rewritten** | stays; the seat continues |
| before the seat's next ticket | the arbiter prompts a **sync**: in its worktree, `git merge --ff-only swarm/<slug>/integration` if `is-ancestor(seat_tip, integration)`; otherwise `git merge swarm/<slug>/integration` (the worker resolves any conflicts) | same |
| `up` re-seat (after the `-B` fix) | attach **without reset**. Staleness is judged against `integration` when it exists, else the base: `rev-list --count integration..branch == 0` ⇒ clean attach | re-provisioned |
| `down` | never deleted (ADR 0007 A1) | removed if clean, else retained and locked |
| `down --purge` (human) | deleted **only if** `is-ancestor(branch, main)` (promoted) **and** ledger `branch_created: true` | removed |

Rebasing a seat branch is **not** used anywhere: it rewrites shas that P2-3 records and verdicts reference. Syncing is always a merge.

The integration branch lives until `promote` succeeds. After promotion, `integration` is fast-forwarded to `main` at the start of the next run, or deleted by `--purge`.

---

## 4. Reconciliation with `lib/gh_sync.sh`

`gh_sync.sh` today: local `maps/tickets/*.md` ↔ GitHub **issues**, matched by frontmatter `github_issue` or a `[ID]` title prefix. It has
closed-status set `{resolved, closed, done}`, defaults to dry-run, and writes only with `--apply`. It has no PR awareness.

### 4.1 Ticket status semantics (new values, backward compatible)

| Local `status` | Set by | Meaning | gh_sync treats as |
|---|---|---|---|
| `in_progress` | looper | worker assigned | open |
| `integrated` | **arbiter** (after §2.2 step 4) | on `swarm/<slug>/integration`, not yet on base | **open** (not in the closed set) |
| `resolved` | **promotion** (local mode) or gh_sync pull (PR mode, see 4.2) | on base | closed |

The arbiter adds frontmatter keys `integrated_sha`, `merge_sha`, `integration_ref`, and after `--pr` also `pr_url`. The arbiter
writes local files only. It never calls `gh`.

### 4.2 Closing issues: let GitHub do it

- **PR mode:** the promotion PR body carries `Closes #N` for every integrated ticket that has a `github_issue`. When the human merges the PR,
  GitHub closes the issues. The next `gh_sync.sh --direction pull` hits the existing branch
  "Remote #N was closed on GitHub → Update local status to resolved" (`gh_sync.sh:337-346`). **No new remote write path is needed.**
- **Local mode (no remote):** `promote` sets `status: resolved` directly. gh_sync has nothing to do.
- **Guard to add in gh_sync:** in `--direction push`, a local `integrated` ticket must **not** trigger "close remote" (it isn't in the
  closed set, which is correct today). Add a regression test so nobody "helpfully" adds `integrated` to the closed set later.

### 4.3 External PRs

A new read-only report, `gh_sync.sh --prs`, runs `gh pr list --state open --json number,title,headRefName,files` and flags:
- PRs whose changed files intersect any in-flight seat's `owns` (the partition invariant, extended to humans). The looper must not dispatch
  overlapping tickets until the PR lands.
- PRs whose body `Closes #N` references a ticket the herd has `in_progress`. That's a duplicate-work warning.

It is report-only. The herd never comments on, approves, or merges PRs it didn't open.

### 4.4 Verdict-to-ticket mapping gap

The verdict protocol is `ARCH DONE #<digits>`, but this herd's tickets are local ids (`P2-1`, `T-017`). Integration needs `ticket → file`.
Rule: `#<n>` means the GitHub issue number, resolved through frontmatter `github_issue == n`. A verdict whose `n` maps to no ticket
file is integrated but reported as `unmapped` (no frontmatter update). A protocol extension (`ARCH DONE <TICKET-ID> <sha>`) is a follow-up.

---

## 5. Records and telemetry

`.herdr-swarm/integration.jsonl` (append-only, `jq -cn`):
`{ts, run_id, ticket, seat, sha, status: queued|integrated|conflict|integration_red|retry|blocked|superseded|promoted, integration_before, merge_sha, files, gate:{exit_code,duration_s,log}, promoted_to, pr_url}`

Telemetry events: `arbiter.queued`, `arbiter.integrated`, `arbiter.conflict`, `arbiter.red`, `arbiter.blocked`, `arbiter.promoted`,
each with ticket, seat, sha7, and the integration tip before/after.

`herdr-loop-swarm.sh status` gains an **Integration** block: integration tip vs `main` (ahead N), and queued/blocked counts. Workers'
commits land on seat branches and reach `main` only at promotion, so without this block the herd will look like it lost work (P2-2 risk).

## 6. Acceptance (scratch repo; receipt attached)

1. Two isolated seats, disjoint files, both green → integration = merge of both, **combined gate green**, CAS logged; `main` untouched.
2. Two green branches that break each other (the second changes an API the first relies on) → second record `integration_red`; ref **not** advanced; seat prompted.
3. Textual conflict → `conflict` with file list; `merge --abort` leaves the arbiter worktree clean; the worker merges integration, re-verdicts → integrated.
4. Worker commits after its verdict → the arbiter integrates the **gated sha**, not the tip; the later commits stay on the seat branch.
5. A concurrent manual `update-ref` on integration during a drain → CAS fails → retry from the new tip; no lost update.
6. `promote` with a dirty root → refused. With `main` moved independently → refused. Clean and ff-able → root and `main` advance together, `git status` clean.
7. `--pr` mode dry run → PR body contains `Closes #N` for mapped tickets; after a (simulated) merge, `gh_sync --direction pull` flips them to `resolved`.
8. Re-run `up` after integration (post `-B` fix) → seat branch attaches without reset; `rev-list integration..branch` = 0.

## 7. Out of scope

Parallel integration, cross-repo PRs, auto-merging PRs, release tagging, LLM-driven conflict resolution inside the arbiter, and squash policy at
promotion (the human chooses in the GitHub UI).
