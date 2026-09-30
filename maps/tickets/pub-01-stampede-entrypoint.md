---
id: PUB-1
title: "bin/stampede unified entrypoint and lib/cli subcommand convention"
type: wayfinder:task
status: resolved
assignee: arch
owns: bin/stampede,Makefile,README.md,tests/test_cli.sh
parent: maps/public-multi-provider.md
blocked_by: DOG-10
github_issue: 90
github_url: "https://github.com/HinchK/stampede/issues/90"
synced_at: "2026-09-30T17:16:14Z"
---

# PUB-1 — `bin/stampede` entrypoint + CLI convention (Wave 8, runs alone)

> Amendment at execution (receipted here, not silently): `owns` grew
> `tests/test_cli.sh` — a dispatcher without a hermetic suite would violate
> the repo's own receipts rule.

## 1. Intended Outcome

One command, `bin/stampede`, fronts the whole product. `up|down|status|verify`
(and bare invocation) delegate to `herdr-loop-swarm.sh` **unchanged**; any
other first argument dispatches to `lib/cli/stampede-<cmd>.sh` if that file
exists; unknown commands print usage and exit `1`.

## 2. Problem

The public surface is two script names (`herdr-loop-swarm.sh`,
`loop-bot-herd.sh`) that say nothing about the product, and every new
user-facing command today means editing the launcher — a hotspot every
earlier wave had to schedule around.

## 3. Plan

- `bin/stampede` resolves its own location (`$SCRIPT_DIR` — never `$PWD`,
  the DOG-13 lesson) and the orchestrator root from it.
- Pass-through: `exec "$ROOT/herdr-loop-swarm.sh" "$@"` for the four
  lifecycle subcommands — delegation, not reimplementation.
- Convention dispatch: for any other `<cmd>`, source
  `$ROOT/lib/cli/stampede-<cmd>.sh` and call `stampede_cmd_<cmd> "$@"`;
  missing file → usage + exit `1`. The dispatcher never knows the full
  command list.
- `make lint` covers `bin/`; README CLI section rewritten around
  `bin/stampede` with the old names documented as stable aliases.

## 4. Explicit Done-Criteria

- `bin/stampede status` and `./herdr-loop-swarm.sh status` produce
  identical output; pass-through is `exec`, zero behavioural fork.
- Unknown subcommand exits `1` with usage; a scratch
  `lib/cli/stampede-hello.sh` is discovered with no dispatcher edit.
- `shellcheck bin/stampede` 0 warnings; `make lint` includes `bin/`.
- README documents the convention for future command authors.

## 5. Verification Step

```bash
bin/stampede status >/dev/null && echo PASS-status
bin/stampede definitely-not-a-cmd; echo "rc=$? (want 1)"
make check
```
