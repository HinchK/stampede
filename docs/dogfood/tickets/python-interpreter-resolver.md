---
id: DOG-1
title: "Resolve a tomllib-capable interpreter instead of bare python3"
type: wayfinder:defect
status: backlog
assignee: arch
owns: Makefile,lib/pyenv.sh,lib/config.sh,lib/briefs.sh,loop-bot-herd.sh,lib/preflight.sh,tests/test_profile.sh
parent: maps/public-readiness.md
---

# DOG-1 — Interpreter resolver (WAVE 1, RUNS ALONE)

## 1. Intended Outcome

Every `python3` invocation resolves through one shared resolver that picks an
interpreter with `tomllib`, and fails with an actionable message when none
exists. `make check` and `./loop-bot-herd.sh status` behave identically whether
or not `/usr/bin/python3` wins the PATH race.

## 2. Problem (reproduced, not theorised)

macOS ships `/usr/bin/python3` = 3.9.6. `tomllib` is 3.11+. Where `/usr/bin`
precedes Homebrew on PATH:

```
$ make check
==> tests/test_async_gate.sh
✖ FAILED: tests/test_async_gate.sh        # prints NOTHING, exits 1

$ ./loop-bot-herd.sh status
ModuleNotFoundError: No module named 'tomllib'
RC=1
```

`lib/preflight.sh:88-99` already contains a correct capability probe — but
`make`, the suites, and `loop-bot-herd.sh status` never call preflight, so the
guard covers none of the paths a new user hits first.

**The trap:** `Makefile:29` (`make lint`) runs `python3 -m py_compile`, which
does NOT need tomllib. So `make lint` passes green under 3.9 while `make test`
dies. That call site is the easiest to miss precisely because it never complains.

## 3. Scope

1. New `lib/pyenv.sh` exporting `PYTHON_BIN` via `resolve_python()`: honour
   `$PYTHON_BIN` if set and capable, else probe
   `python3.14 python3.13 python3.12 python3.11 python3` — first that imports
   `tomllib` wins.
2. On failure exit 1 naming the found version, its path, and the remedy
   (`brew install python@3.12`, or `export PYTHON_BIN=...`).
3. Replace every bare `python3` with `"$PYTHON_BIN"` in `Makefile` (**both**
   `test` and `lint`), `lib/config.sh`, `lib/briefs.sh`, `loop-bot-herd.sh`,
   `lib/preflight.sh`.
4. Suites source `lib/pyenv.sh` so they fail with the message, not a traceback.
5. `lib/preflight.sh` reports the resolved interpreter path, not just "ok".

## 4. Done-Criteria

1. `grep -rn 'python3' Makefile lib/*.sh loop-bot-herd.sh herdr-loop-swarm.sh`
   shows no bare invocation outside `lib/pyenv.sh`.
2. `PATH=/usr/bin:/bin make check` fails with the actionable message, **not** a
   `ModuleNotFoundError` traceback — **and** `make lint` fails too, not just `test`.
3. `PATH=/opt/homebrew/bin:$PATH make check` — all 5 suites green, 132 assertions.
4. `PYTHON_BIN=/usr/bin/python3 make check` gives the same actionable message.
5. `shellcheck lib/pyenv.sh` clean.

## 5. Verification Step

```bash
env -i PATH=/usr/bin:/bin HOME="$HOME" make check ; echo "want non-zero + message: $?"
env -i PATH=/usr/bin:/bin HOME="$HOME" make lint  ; echo "want non-zero too: $?"
PATH=/opt/homebrew/bin:$PATH make check           ; echo "want 0: $?"
shellcheck lib/pyenv.sh
```

Receipt MUST quote the stderr text from the degraded run. A traceback in that
output is a failed ticket.

## 6. Notes

This unblocks the swarm's own ability to run. It touches `loop-bot-herd.sh`, the
supervisor, so it runs alone with nothing dispatched concurrently.
