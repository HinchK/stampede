# P2-2 Spec — Config & Ledger Integration for Worktree Isolation (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `b518c40`
**Implements:** ADR 0006 §4.A–C (topology, ledger, provisioning) · **Depends on:** P2-1 `lib/worktree.sh` (`worktree_provision`)
**Related:** `docs/audits/2026-09-19-phase2-worktree-advisory.md` (measured hazards H1–H8)

## 0. Scope

In scope: the config flag, its shell binding, the ledger fields, and the launcher call order. **Out of scope:** the
teardown implementation (only its *contract* over these fields is fixed here, §3.4), fan-out/arbiter, and task partitioning.

Two corrections and two ADR amendments are part of this spec (§5). The most important one for implementers:
**`herdr agent start` has no `--cwd`** (`agent start --help`: `--kind`, `--pane`, `--timeout` only). An agent inherits the cwd
of the pane it is started in, and the pane's cwd is fixed at `herdr pane split --cwd`. So the worktree must exist **before
the pane is split**, not merely before `agent start`.

---

## 1. TOML schema — `swarm.config.toml`

```toml
[swarm]
worktree_root = ".herdr-swarm/worktrees"   # optional; relative to TARGET_DIR (ADR 0006 default)
base_branch   = ""                          # optional; "" = current branch of TARGET_DIR at `up`

[seats.arch]
# … existing keys …
worktree = true          # boolean, default false

[seats.looper]
worktree = false         # root anchor (ADR 0006 §4.A); may be omitted
```

Rules:
- `worktree` is a **TOML boolean**. Absent ⇒ `false`. Any non-boolean (`"true"`, `1`) is a **config error**: the emitter exits non-zero
  naming the seat and key. There is no truthiness coercion, because a mistyped flag must not silently share the root checkout (H2).
- Root anchors (`looper`, `pm`) must not set `worktree = true`. The emitter rejects this for any seat whose `role`/`name` is `looper` or
  `pm` (ADR 0006 §5.1: the root is never driven by a task branch; looper coordinates from the root).
- `worktree_root` must resolve inside `TARGET_DIR` **and** under a gitignored path. The launcher checks this with
  `git check-ignore -q "$worktree_root"`, and failing it is fatal. The ADR default `.herdr-swarm/worktrees` satisfies both, because `.herdr-swarm/` is ignored. (An
  out-of-repo root, the advisory's H4 preference, stays possible later by relaxing this check. It is not required for P2-2.)
- Seat keys must match `[A-Za-z_][A-Za-z0-9_]*`, since they become shell variable suffixes. The emitter rejects others (today's keys comply).

**Initial config change:** set `worktree = true` on `seats.arch` only (P2-0 from the advisory: this removes today's shared-index
collisions). `docs`/`gh` stay `false` until P2-2 has run cleanly for one session.

---

## 2. Shell binding — `lib/config.sh`

Extend `config_dump_env` (same argv-safe, `shlex.quote` emitter):

```python
wt_root = swarm.get('worktree_root', '.herdr-swarm/worktrees')
emit('SWARM_WORKTREE_ROOT', wt_root)
emit('SWARM_BASE_BRANCH', swarm.get('base_branch', ''))

for k in enabled_seats:
    s = seats[k]
    wt = s.get('worktree', False)
    if not isinstance(wt, bool):
        sys.exit(f"config error: seats.{k}.worktree must be a boolean (got {type(wt).__name__})")
    if wt and (k in ('looper', 'pm') or s.get('name') in ('looper', 'pm')):
        sys.exit(f"config error: seats.{k} is a root anchor and cannot set worktree = true (ADR 0006 §4.A)")
    emit(f'SEAT_WORKTREE_{k}', 1 if wt else 0)
```

Contract:
- `SEAT_WORKTREE_<key>` is **always emitted** for every enabled seat, as `1` or `0`. Consumers read it with
  `${SEAT_WORKTREE_<key>:-0}`, so an old config with no flag behaves exactly as today.
- `config_plan_preview` (`--plan`) adds a `Worktree` column showing `root` or `<worktree_root>/<seat_name>` on `swarm/<slug>/<seat_key>`.
- A config error aborts `up` **before** any workspace, pane, or worktree is created (same fail-closed position as the profile).

Acceptance:
1. No `worktree` keys ⇒ `--plan` output identical to `b518c40` except the new column (all `root`).
2. `worktree = "true"` ⇒ exit ≠ 0, message names `seats.<key>.worktree`.
3. `[seats.looper] worktree = true` ⇒ exit ≠ 0.
4. `shellcheck` stays at 0 warnings.

---

## 3. Ledger schema — `.herdr-swarm/seats.json`

### 3.1 Shape (v2, compatible with ADR 0006 §4.B)

```json
{
  "version": 2,
  "workspace_id": "wM",
  "target_dir": "/abs/repo",
  "base_branch": "main",
  "base_sha": "b518c40",
  "seats": [
    {"name": "looper-repo", "kind": "agy", "pane": "wM:p1",
     "isolated": false, "worktree_dir": "/abs/repo", "branch": "main"},
    {"name": "arch-repo", "kind": "opencode", "pane": "wM:p5",
     "isolated": true,
     "worktree_dir": "/abs/repo/.herdr-swarm/worktrees/arch-repo",
     "branch": "swarm/repo/arch",
     "branch_created": true,
     "provisioned_at": "2026-09-19T13:40:00Z"}
  ]
}
```

- `worktree_dir` and `branch` are **present on every seat**. Root seats record `TARGET_DIR` and its current branch, with `isolated: false`.
  This keeps one code path for "where does this seat work".
- `worktree_dir` is an **absolute physical path** (`pwd -P`), matching `lifecycle.sh`'s strict-cwd comparison.
- `branch_created` records whether *this* `up` created the branch (`true`) or attached to an existing one (`false`). Teardown uses it (§3.4).
- `base_sha` is the base commit at `up`; the supervisor uses it to show how far each worker has diverged.

### 3.2 Reading v1 ledgers

A ledger without `version` is v1. Readers (`lifecycle.sh`, `status`, `verify`) treat every v1 seat as
`isolated: false, worktree_dir: <target_dir>`. v1 ledgers are never rewritten in place; the next `up` writes v2.

### 3.3 Writing (replaces the `|`-split pipeline at `herdr-loop-swarm.sh:472-474`)

- Build each seat with `jq -n --arg …` (no `|`-delimited strings, since paths may contain any character), accumulate into a JSON array,
  and write via **temp file + `mv`** in `.herdr-swarm/`.
- P2-2 writes the ledger **once**, at the end of `up`, as today. Concurrent mutation (spawn/retire during fan-out) needs the locked
  `ledger_update` from the advisory §2.2 and belongs to the fan-out ticket, not here.
- **Crash window:** if `up` dies after `worktree_provision` but before the ledger write, a worktree exists that no ledger records.
  To close that window, `worktree_provision` also sets `git worktree lock --reason "herd:<workspace_id>:<seat_name>"`. `status`
  lists locked `herd:` worktrees that are missing from the ledger as **orphans**. Nothing deletes orphans automatically.

### 3.4 Teardown contract over these fields (implementation: next ticket)

| Seat | `down` action |
|---|---|
| `isolated: false` | close pane only. **Never** any worktree command against `target_dir`. |
| `isolated: true`, clean tree | close pane → `worktree unlock` → `worktree remove` (no `--force`) → `worktree prune`. **Branch kept.** |
| `isolated: true`, dirty tree | close pane → leave worktree **locked and in place**, and report it under "retained work". No `--force`. |
| worktree path not under `SWARM_WORKTREE_ROOT`, or not in ledger | never touched |

Branches are never deleted by `down` (ADR 0006 §4.D.4). `branch_created` exists so a future `--purge` can delete only branches
the herd itself created.

---

## 4. Launcher integration contract — `herdr-loop-swarm.sh`

### 4.1 Call order per seat (seat loop, today `:394-441`)

```
for seat_key in $SEAT_KEYS:
  1. agent_alive "$seat_name"            → already seated: read existing ledger entry, carry it forward, SKIP 2–5
  2. if SEAT_WORKTREE_<key> == 1:
        seat_cwd=$(worktree_provision "$TARGET_DIR" "$PROJECT_SLUG" "$seat_key" "$seat_name" "$BASE_BRANCH")
          || { record seat failure; continue }        # fail this seat, not the herd
     else:
        seat_cwd="$TARGET_DIR"
  3. seat_pane=$(split_pane <anchor> <dir> 0.5 "$seat_cwd")   # cwd is fixed HERE
  4. herdr agent start "$seat_name" --kind … --pane "$seat_pane"
  5. append seat record {name, kind, pane, isolated, worktree_dir: seat_cwd, branch, branch_created}
```

### 4.2 `worktree_provision` interface (P2-1 must satisfy this)

```
worktree_provision TARGET_DIR SLUG SEAT_KEY SEAT_NAME BASE_BRANCH
  stdout: one line, the absolute physical worktree path
  also exports: WT_BRANCH, WT_BRANCH_CREATED (1|0)
  exit 0 on success; non-zero with a one-line reason on stderr
```

Behaviour:
- Path: `${TARGET_DIR}/${SWARM_WORKTREE_ROOT}/${SEAT_NAME}`. Branch: `swarm/${SLUG}/${SEAT_KEY}` (ADR 0006).
- **Idempotent:** if the path is already a registered worktree on the expected branch, return it (re-running `up` must not fail or duplicate).
- **Existing branch, no worktree:** attach **only if** it is not stale:
  `git rev-list --count "$BASE_BRANCH..$branch"` is `0` (nothing unmerged), **or** the previous `seats.json` for this target lists
  that exact branch for this seat (a genuine resume). Otherwise fail that seat with
  `stale branch swarm/<slug>/<seat> (N commits not on <base>); pass --adopt-branches or delete it`. (Amendment A2, §5.)
  Git itself refuses if the branch is checked out in another worktree; surface that error verbatim.
- Sets `git worktree lock --reason "herd:<workspace_id>:<seat_name>"` (§3.3).
- Never runs `git stash`, `git checkout`/`switch` in `TARGET_DIR`, or any command with `--force`.

### 4.3 Brief rendering

`lib/briefs.sh` adds template variables `{{WORKTREE_DIR}}` and `{{BRANCH}}`. The arch brief template gains:
"You work only in `{{WORKTREE_DIR}}` on `{{BRANCH}}`. Never `cd` to the repo root and never switch branches. Report
`ARCH DONE #<n> <sha>` with a sha from this branch."

### 4.4 Supervisor touch point (minimal, for P2-2)

`loop-bot-herd.sh` resolves the suite-gate directory from the ledger: the verdict's seat → `worktree_dir` (fallback `REPO_DIR`).
Without this, a green gate would test the root, not the worker's code, which would be a false-green (M3 audit H1 class).

### 4.5 Acceptance (scratch repo, receipt attached to the ticket)

1. `worktree = true` on arch only: `up -m s` → `git worktree list` shows the root plus `.herdr-swarm/worktrees/arch-<slug>` on `swarm/<slug>/arch`;
   `herdr agent get arch-<slug>` → `cwd` equals that path; the ledger has v2 fields for all seats.
2. Re-run `up`: no new worktree, no error, ledger unchanged except timestamps.
3. `git -C <root> status --porcelain` is empty after `up` (the worktree lives under an ignored path).
4. arch commits in its worktree while agy-docs commits in the root at the same moment → no `index.lock` error (reproduces the advisory's H2 fix).
5. Pre-create a stale `swarm/<slug>/arch` with an extra old commit → `up` fails that seat with the stale-branch message; other seats come up.
6. `worktree = "yes"` → `up` aborts before any pane is created.
7. `down --yes` on the scratch workspace with a dirty arch worktree → worktree retained and reported; the root is untouched.

---

## 5. Corrections and ADR 0006 amendments

| # | Item | Why |
|---|---|---|
| C1 | "Pass the worktree as agent cwd" is implemented at **`split_pane`**, not `agent start` | `agent start` has no `--cwd`; the agent inherits the pane's cwd. |
| C2 | The suite gate must resolve `worktree_dir` from the ledger (§4.4) | Otherwise isolated work is gated against the root, which is a false green. |
| **A1** | ADR 0006 §4.D.3 `git worktree remove --force` → **remove without `--force`; dirty worktrees are retained and locked** | `--force` discards uncommitted work, contradicting the ADR's own "work is never lost" goal. git's refusal on a dirty tree is the safety net (measured, advisory §1.1). |
| **A2** | ADR 0006 §4.C.2 "if branch exists, attach" → **attach only if not stale (or `--adopt-branches`)** | Seat-scoped branch names persist across runs. Silent re-attach hands arch another run's leftover commits (advisory H3). |

Recommend that `agy-docs` record A1/A2 as ADR 0006 amendments (or ADR 0007) in the same PR as P2-2.

## 6. Risks

- **Environment bootstrap:** the arch worktree has no `.venv`/`node_modules`. The first suite gate there may fail for environmental reasons,
  not code reasons. P2-2 acceptance #1 must include one gate run in the worktree. If it fails for missing deps, ADR 0006 §3's bootstrap step moves into P2-1.
- **Human confusion:** arch's commits now land on `swarm/<slug>/arch`, not `main`. Nothing reaches `main` until integration (arbiter/PR). Say so in the
  arch brief and in `status`, or the herd will look like it lost work.
