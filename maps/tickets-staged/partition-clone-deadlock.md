---
id: DOG-11
title: "partition_check treats every historical ticket as an active lease in a fresh clone"
type: wayfinder:defect
status: backlog
assignee: arch
owns: lib/partition.sh,tests/test_partition.sh
parent: maps/public-readiness.md
---

# DOG-11 — Fresh-clone partition deadlock

> Found while bootstrapping the dogfood clone, **before the loop ran**. This is
> a latent defect: `partition_check` has no callers today, so nothing is broken
> right now. It becomes a hard deadlock the moment the next planned task lands.

## 1. Intended Outcome

`partition_check` behaves identically in a fresh clone and in the repo it was
developed in — a ticket whose work is already in the base does not hold a lease.

## 2. Problem

`lib/partition.sh:190-197` treats `resolved|done|closed` as **active** unless the
ticket is proven integrated:

```bash
resolved|done|closed)
  if [[ "$owns_present" == 0 || -f "$integ" ]] \
     && jq -e -s --arg t "$id" 'any(.[]; (.ticket|tostring) == $t and
        (.status == "integrated" or .status == "promoted"))' "$integ" >/dev/null 2>&1; then
    return 1
  fi
  return 0
  ;;
```

The proof lives in `$repo/.herdr-swarm/integration.jsonl`. **`.herdr-swarm/` is
gitignored** (`.gitignore:2`), so that file never travels with a clone. When it
is absent, `jq` fails, the guard falls through, and the ticket is active.

Measured on a fresh clone of HEAD `924619d`:

```
$ ls .herdr-swarm/integration.jsonl
No such file or directory

$ grep -lc '^status: \(resolved\|done\|closed\)$' maps/tickets/*.md | wc -l
38

$ bash lib/partition.sh check maps/tickets/<any-new-ticket>.md .
BLOCKED by active ticket TEST-AGG (status=resolved)
  makefile ∩ makefile
BLOCKED by active ticket P3-3 (status=resolved)
  loop-bot-herd.sh ∩ loop-bot-herd.sh
...
rc=1
```

Every one of the 38 historical tickets holds its declared paths forever. Any new
ticket touching a file that has *ever* been touched is permanently blocked.

The intent is right and documented — a lease is held until the ticket
**integrates**, not until its verdict is green, because releasing at green would
let the next worker branch from a base missing that work. The bug is the
*evidence source*: in a clone, that work is already in the base, and the only
artifact that could say so is untracked.

## 3. Why this is urgent despite having no callers

`STATE.md` §3 lists the next task as: *"Wire `partition_check` / `lease_acquire`
into the launcher's dispatch path."* Wiring it as written deadlocks dispatch on
any clone — including a contributor's first checkout and the CI runner.

## 4. Scope

Decide where integration evidence comes from when the ledger is absent. Options,
in preference order:

1. **Trust the git base.** A `resolved|done|closed` ticket whose `commit:` sha is
   an ancestor of the current base is integrated by definition
   (`git merge-base --is-ancestor`). This needs no new state, works in any clone,
   and is strictly more truthful than the JSONL.
2. **Treat an absent ledger as "history integrated".** A missing file means a
   fresh clone, not an in-flight swarm. Cheap, but weaker than (1).
3. Commit the ledger. **Rejected** — it is per-machine runtime state and would
   conflict constantly.

Prefer (1), fall back to (2) for tickets carrying no `commit:`.

## 5. Done-Criteria

1. In a fresh clone with no `.herdr-swarm/`, `partition_check` on a new ticket
   overlapping only historical work returns 0.
2. A genuinely in-flight `in_progress` ticket still blocks.
3. A `resolved` ticket whose `commit:` is **not** an ancestor of the base still
   blocks (the real lease case is preserved).
4. New assertions in `tests/test_partition.sh` covering all three, including a
   scratch repo with **no** `integration.jsonl`.
5. `make check` green; `shellcheck lib/partition.sh` clean.

## 6. Verification Step

```bash
/bin/bash tests/test_partition.sh ; echo "rc=$?"

tmp=$(mktemp -d) && git clone -q . "$tmp/clone" && rm -rf "$tmp/clone/.herdr-swarm"
bash lib/partition.sh check "$tmp/clone/maps/tickets/<new-ticket>.md" "$tmp/clone"
echo "want rc=0"
rm -rf "$tmp"
```

Receipt must show the fresh-clone probe returning 0 **and** an `in_progress`
ticket still returning 1 — proving the fix did not simply disable the check.
