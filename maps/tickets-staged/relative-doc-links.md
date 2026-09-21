---
id: DOG-9
title: "Convert 439 absolute file:///Users/hinchk links to repo-relative"
type: wayfinder:task
status: backlog
assignee: arch
owns: README.md,CONTEXT.md,STATE.md,docs/,maps/universal-herdr-swarm.md,maps/public-readiness.md
parent: maps/public-readiness.md
---

# DOG-9 — Relative links (WAVE 5, RUNS ALONE)

## 1. Intended Outcome

Every intra-repo link resolves on GitHub and in any clone, not only on one laptop.

## 2. Problem

Measured: **439** occurrences of `file:///Users/hinchk/Fun/loop-bot-herd-agy/...`
across **44** files. On GitHub every one renders as a dead link into a stranger's
filesystem. `README.md` alone carries 35; `maps/universal-herdr-swarm.md` carries 46.

## 3. Scope

Mechanical, whole-repo: rewrite
`file:///Users/hinchk/Fun/loop-bot-herd-agy/<path>` to `<path>` relative to the
linking file's own directory.

- `README.md` to `lib/profile.sh`
- `docs/adr/0006-*.md` to `../../lib/worktree.sh`
- `maps/tickets/foo.md` to `../../docs/adr/0001-*.md`

Write a script, run it, then **verify every produced link resolves**. Do not
hand-edit 44 files.

If a link points at something that does not exist, **report it — do not invent a
target.** That is a finding, not a defect to paper over.

## 4. Done-Criteria

1. `grep -rn 'file:///Users' . --include='*.md' | grep -v '^./maps/tickets'`
   returns **0** hits. Hits remaining under `maps/tickets/` are out of scope.
2. Every converted link resolves to an existing path, proven by script.
3. No prose outside link targets is altered — the diff is links only.
4. `make check` green.

## 5. Verification Step

```bash
grep -rn 'file:///Users' . --include='*.md' | grep -vc '^./maps/tickets'  # want 0
grep -rn 'file:///Users' . --include='*.md' | grep -c  '^./maps/tickets'  # record, do not fix

"$PYTHON_BIN" - <<'PY'
import re, pathlib, sys
bad = []
for p in pathlib.Path('.').rglob('*.md'):
    if '.git' in p.parts: continue
    for m in re.finditer(r'\]\(([^)#]+)\)', p.read_text(encoding='utf-8')):
        t = m.group(1).strip()
        if t.startswith(('http://','https://','mailto:')): continue
        if not (p.parent / t).exists(): bad.append(f'{p}: {t}')
print('\n'.join(bad) if bad else 'all relative links resolve')
sys.exit(1 if bad else 0)
PY
```

## 6. Notes

Touches nearly every markdown file. Runs alone, last of the automated tickets,
and must land after DOG-5 so the two do not fight over `README.md`.

**`maps/tickets/` is deliberately excluded from `owns:`.** Those files also carry
`file:///Users/...` links, but the looper writes into `maps/` during ticket
retirement — it ticks the map checkbox and appends to "Decisions so far". Two
writers in one directory is how a retirement gets clobbered. Convert the ticket
files' links in the DOG-10 human pass, with the floor down.

If the verification script below reports surviving hits under `maps/tickets/`,
that is expected and is **not** a failure of this ticket — record the count in the
receipt and leave them.

Does **not** rename the project — that is DOG-10, and it is human-gated.
