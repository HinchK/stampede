# Phase 2 Advisory — Parallel Worktree Swarm Fan-Out (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `903fb2d` · **Inputs:** `loop-bot-herd-claude/herdr-loop-claude-pm.sh` (reference
variant), `herdr-loop-swarm.sh` seat ledger, `lib/lifecycle.sh`, `swarm.config.toml`, T-001 findings.
**Evidence:** empirical probes on git 2.55.0 in a scratch repo (12 concurrent workers). Nothing ran against a real repo.

## Recommendation in one paragraph

Build it, but treat **worktrees as disposable per-task sandboxes owned by the supervisor**, not as extra seats. Commits inside
separate worktrees are safe in parallel (measured). What is *not* safe is anything that shares a mutable target: one ref, one
index, one ledger file, one branch name. Phase 2 therefore needs three structural rules before any parallel code:
(1) **only the arbiter writes shared refs, and only with compare-and-swap**; (2) **`seats.json` becomes a locked, atomically
rewritten v2 ledger that owns worktree lifecycle**; (3) **teardown never deletes work it can't prove is merged or checkpointed.**
Everything else is configuration.

---

## 1. Git index and ref concurrency hazards

### 1.1 Measured (12 concurrent workers, scratch repo)

| Scenario | Result | Verdict |
|---|---|---|
| N× parallel `git worktree add -b swarm/tN` | 0/12 failures, 13 worktrees listed | ✅ Safe |
| N× parallel commits, one worktree and branch each, 20 rounds | 0/240 failures; `git fsck` clean | ✅ Safe (each worktree has its own index and HEAD) |
| N× `git update-ref` on **one shared ref** (no old value) | 0/12 errors; **only the last write survives. 11/12 updates silently lost.** | ❌ **Silent data loss** |
| Same, with CAS (`update-ref <ref> <new> <old>`) | 1 winner, 10 loud rejections | ✅ Safe; losers retry |
| Two agents `git add` in the **same checkout** | 4/6 fail: `index.lock: File exists` | ❌ Collides (this is today's herd: all 5 seats share one checkout) |
| Same branch checked out in a 2nd worktree | `fatal: already used by worktree` | ✅ Git refuses |
| `worktree remove` on a dirty tree | refused without `--force` | ✅ Safety net; never pass `--force` automatically |
| `rm -rf` worktree dir, then `worktree prune` | admin entry pruned, **branch survives** | ✅ Work recoverable from the branch |
| `worktree lock --reason seated`, then `prune` | survives; `remove` refused | ✅ Use the lock as the "live seat" marker |
| pytest in main with a worktree at `.herdr-swarm/wt/t1` | nested failing test **not collected** (pytest skips dot-dirs) | ⚠ Ecosystem-dependent; see H4 |

### 1.2 Hazards and required mitigations

| ID | Sev | Hazard | Mitigation (required for Phase 2) |
|---|---|---|---|
| **H1** | **HIGH** | **Lost integration updates.** Workers or arbiters that move a shared branch (`integration`, `main`) with plain `update-ref`, `branch -f`, or merge-then-update race silently. | Workers **never** touch shared refs; they commit only to `swarm/<slug>/<task>`. A single **arbiter** integrates, using `git update-ref <ref> <new> <expected-old>` (CAS) with retry, or a `mkdir` lock around merge+update. Base branch is never written (PR only, as today). |
| **H2** | **HIGH** | **Shared-index collisions** whenever two agents operate in one checkout. Today looper, arch and agy-docs all commit in the herd root. Killed agents also leave stale `index.lock`. | Every committing seat gets its own worktree. The coordinator seat (looper) is read-only in the root. Clearing a stale `index.lock` requires no live git process on that worktree; it is never a blind `rm`. |
| **H3** | MED | **Branch-name reuse.** The reference variant falls back to `worktree add "$wt" "$br"`, which silently reuses a stale `swarm/<id>` from a previous run with old commits. | Branch names carry the run: `swarm/<slug>/<run_id>/<task>`. A pre-existing branch is an error unless the run is a `resume` whose ledger names it. |
| **H4** | MED | **Nested worktrees inside the repo.** The reference variant uses `$REPO/.swarm/wt/<id>`. pytest and `go ./...` skip dot-dirs (measured / documented), but `jest`/`vitest` roots, `tsc` `include: ["**/*"]`, linters, and IDE file watchers may crawl N copies of half-edited code. The suite gate in main could run workers' code. | Default `worktree_root` **outside** the repo: `<repo>/../.<repo>.herd-worktrees/<run_id>/<task>`. Allow in-repo only via explicit config, and then under the already-ignored `.herdr-swarm/`. |
| **H5** | MED | **Suite-gate cross-talk.** N gates at once share ports, `/tmp` paths, caches (`.pytest_cache`, `node_modules/.cache`), local DBs, and the Ollama backend. | Gate inside the worker's worktree with `TMPDIR` set per worktree. `max_parallel` caps concurrent gates separately from concurrent workers (`gate_concurrency`, default 1 until proven). |
| **H6** | MED | **Shared stash, config and hooks.** `git stash` is repo-global across worktrees. `git config` writes and hooks apply to all. | Brief rule: no `git stash` (use WIP commits). No `git config` writes from agents. Hooks run per worktree, which is fine but slows N-way commits. |
| **H7** | LOW | **Auto-gc / fetch contention.** Concurrent `git gc --auto` or `git fetch` contend on `gc.pid` and remote-ref locks, producing sporadic "cannot lock ref" failures. | Supervisor does one `fetch` before fan-out. Workers don't fetch. Set `gc.auto=0` for the run, and gc at `down`. |
| **H8** | LOW | **Stall checkpoint `git add -A`** (reference variant, stall path) commits whatever is lying around (artifacts, `.env`-like files). | Checkpoint via `git add -u` plus task-owned paths only. Never `-A`. |

**Carry-over from the reference variant:** keep the *file-ownership partition check*. Two tasks may not own the same path.
It is the cheapest merge-conflict prevention there is, and it makes the arbiter's job mostly fast-forwards.

---

## 2. Lifecycle and state in `.herdr-swarm/seats.json`

Today's ledger is `{workspace_id, seats:[{name,kind,pane}]}`, written once at `up` by truncating redirect
(`herdr-loop-swarm.sh:452-458`). Phase 2 mutates it continuously (spawn, verify, retire), so it must be versioned, locked and atomic.

### 2.1 Schema v2

```json
{
  "version": 2,
  "workspace_id": "wM",
  "run_id": "20260919-0630-a1b2",
  "repo_root": "/abs/path/repo",
  "base": {"branch": "main", "sha": "903fb2d"},
  "worktree_root": "/abs/path/.repo.herd-worktrees/20260919-0630-a1b2",
  "seats": [
    {"name": "arch-repo", "kind": "opencode", "pane": "wM:p5", "role": "persistent"},
    {"name": "w-t3-repo", "kind": "agy", "pane": "wM:pC", "role": "worker",
     "task": "t3", "owns": ["lib/profile.sh"],
     "worktree": "/abs/.../t3", "branch": "swarm/repo/20260919-0630-a1b2/t3",
     "base_sha": "903fb2d", "head_sha": "4e5f6a7",
     "state": "seated|working|verifying|green|red|integrated|abandoned",
     "created_at": "…", "updated_at": "…"}
  ]
}
```

### 2.2 Write discipline

- **One writer function** (`ledger_update` in `lib/lifecycle.sh`): `mkdir .herdr-swarm/seats.lock` spin-lock (portable to bash 3.2 / macOS,
  no `flock`) → `jq` transform → write `seats.json.tmp` → `mv` (atomic rename) → `rmdir` lock. Remove the lock if stale after 30 s,
  but only when its recorded pid is dead.
- Write order for spawn: **ledger entry `seated` → `worktree add` → `worktree lock --reason "herd:<run_id>"` → pane split → agent start**.
  On any failure, roll back in reverse. A crash then leaves a ledger entry that `status` can reconcile. It never leaves an
  untracked worktree.
- `status` reconciles three sources and prints drift: ledger ↔ `git worktree list --porcelain` ↔ `herdr agent list`.

### 2.3 Safe pruning semantics for `swarm_down`

Pruning is decided **per worker, by state**, never by blanket `--force`:

| Worker state at `down` | Action |
|---|---|
| `integrated` (branch is ancestor of the integration ref, verified by `merge-base --is-ancestor`) | close pane → `worktree unlock` → `worktree remove` → delete branch |
| `green`/`red`, clean tree | close pane → unlock → `worktree remove`; **keep branch** (not yet integrated) |
| dirty tree (uncommitted changes) | close pane → **checkpoint commit** (`add -u` + owned paths, message `herd: checkpoint at down`) → keep worktree **locked** and keep branch; list it under "retained work" |
| `abandoned` / unknown to git (dir gone) | `worktree prune` (branch survives, per probe) |
| worktree not in ledger | **never touched**, only reported (it could be the human's own worktree) |

Additional rules:
- `down` only touches worktrees under the ledger's `worktree_root` whose `branch` matches `swarm/<slug>/<run_id>/…`. Both must match.
- The confirmation plan (already in `swarm_down`) lists worktrees and branches to be removed vs. retained, just as it lists panes today.
- `--keep-workspace` keeps worktrees too. A new `--purge` flag is the only path that deletes retained branches, and it requires the
  interactive typed-label confirmation.
- `down` finishes with `git worktree prune` and `gc.auto` restored.

---

## 3. Integration roadmap

### 3.1 `swarm.config.toml`

A per-seat `worktree = true` flag is the right *toggle*, but not the right *unit*. Phase 2 parallelism is per **task**, not per
persistent seat. Recommended shape:

```toml
[fanout]
enabled = false                 # Phase 2 is opt-in
max_parallel = 3                # concurrent worker seats
gate_concurrency = 1            # concurrent suite gates (H5)
worktree_root = "../.{repo}.herd-worktrees"   # H4: outside the repo by default
branch_prefix = "swarm/{slug}/{run_id}"       # H3
integration_ref = "refs/heads/swarm/{slug}/{run_id}/integration"
arbiter_seat = "arbiter"
stall_secs = 600
max_relaunch = 1

[fanout.routing]               # tier → seat template (from the reference variant's route_kind)
code = "arch"
docs = "docs"
mechanical = "docs"
hard = "pm"

[seats.arch]
# … existing keys …
worktree = true                # this seat's workers run in worktrees (templates spawn w-<task>-<slug>)

[seats.looper]
worktree = false               # coordinator stays read-only in the root (H2)

[seats.arbiter]
name = "arbiter"
default_kind = "claude"
worktree = true                # the arbiter integrates in its own worktree on integration_ref
enabled = false                # enabled only when fanout.enabled
```

`lib/config.sh` must emit these via the existing argv-safe emitter (`FANOUT_*`, `SEAT_WORKTREE_<key>`), with defaults so the
Phase-1 herd behaves identically when `[fanout]` is absent.

### 3.2 Tickets (in order)

| # | Ticket | Scope | Done when |
|---|---|---|---|
| P2-0 | **Fix today's H2** | Give arch and agy-docs their own worktrees now; looper read-only | No `index.lock` collisions in a 30-minute herd run; `git worktree list` shows per-seat trees |
| P2-1 | `lib/worktree.sh` | `wt_create/lock/checkpoint/remove/reconcile` with H3/H4/H8 rules | bats on a scratch repo: create N in parallel, dirty-remove refused, locked survives prune |
| P2-2 | Ledger v2 + `ledger_update` | Schema, lock, atomic rename, v1→v2 upgrade on read | 12-way concurrent `ledger_update` → no lost entries (same probe as H1) |
| P2-3 | Config `[fanout]` | Parse, defaults, `--plan` shows fan-out topology | `[fanout]` absent ⇒ byte-identical Phase-1 `--plan` |
| P2-4 | Task intake + partition check | Port `partition_check` from the reference variant; source = map tickets or tasks file | Overlapping `owns` rejected before any worktree exists |
| P2-5 | Worker spawn/watch in supervisor | `loop-bot-herd.sh` gains `fanout` loop: spawn ≤`max_parallel`, gate in worktree, verdict via nonce file (post-H1 fix) | 3 toy tasks → 3 green branches, ledger states correct, telemetry `worker.*` events |
| P2-6 | Arbiter integration | CAS updates of `integration_ref`, merge in dependency order, suite gate on integration, **one PR** | 3 branches integrated; a forced concurrent update is rejected, not lost |
| P2-7 | `down`/`status` v2 | §2.3 pruning table, reconcile drift view, `--purge` | Scratch run: integrated trees removed, dirty tree checkpointed and retained, foreign worktree untouched |
| P2-8 | Launcher | `up --fanout` / `-m f`; preflight adds `git ≥ 2.31` (porcelain `prunable` field used by reconcile), disk-space check (N × repo size) | `up --fanout --plan` walk; live scratch run receipt |

The two ⚠ items from the M3 audit are **prerequisites**, not Phase 2 work: re-seat this herd with the new `up` (proves namespacing
and the ledger v1), and put one genuine verdict through the gate.

---

## 4. Risks to track

- **Cost amplification:** N workers × frontier models. `max_parallel` defaults to 3; route `docs`/`mechanical` tiers to flash models.
  Record tokens per task in telemetry before raising the cap.
- **Merge-conflict debt:** the partition check prevents file-level overlap, not semantic overlap. Two tasks can still both change one
  API's contract. The arbiter's integration suite gate is the backstop. Expect integration failures, and budget arbiter time for them.
- **Disk:** each worktree is a full checkout (no object duplication, but `node_modules`/`.venv` per tree). Preflight should check free space.
- **Human legibility:** 3+ worker panes plus an arbiter overflow the 80×20 floor. Workers belong in a dedicated `workers` tab, which the geometry
  guard already supports.

## 5. Decisions needed from the driver

1. **Task source for fan-out:** Wayfinder map tickets (reuse the frontier) or an explicit tasks file (reference-variant style)? Recommended: map tickets
   with an `owns:` field, with the tasks file kept as a manual override.
2. **Worktree location default:** outside the repo (recommended, H4) vs. `.herdr-swarm/wt/` (simpler, depends on the ecosystem).
3. **Do P2-0 now?** It fixes a live hazard in today's sequential herd, independent of whether Phase 2 goes ahead.
