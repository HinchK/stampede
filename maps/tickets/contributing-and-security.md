---
id: DOG-6
title: "Add CONTRIBUTING and SECURITY for public consumption"
type: wayfinder:task
status: backlog
assignee: agy-docs
owns: CONTRIBUTING.md,SECURITY.md
parent: maps/public-readiness.md
---

# DOG-6 — CONTRIBUTING + SECURITY (WAVE 2)

## 1. Intended Outcome

A first-time contributor can reach a green local gate, and a security reporter
knows where to send a finding.

## 2. Scope

`CONTRIBUTING.md`, short and concrete:

- prerequisites, stating **Python >= 3.11 for tomllib** explicitly
- `make check` as the one command; 0 shellcheck warnings is the bar
- bash 3.2 (macOS system bash) is the platform floor — suites run under `/bin/bash`
- conventional commits referencing a ticket, e.g. `feat: … (#DOG-3)`
- the git safety rules this repo has paid for: never `git stash` (the stash stack
  is shared across worktrees), never `git worktree remove --force`, never move a
  branch that is checked out somewhere, never push or merge to a base branch
  without explicit human approval

`SECURITY.md`: how to report, expected response window, and the honest scope
note — this tool executes model-authored code locally and drives third-party
agent CLIs; it is not a sandbox.

## 3. Done-Criteria

1. Both files exist at the repo root.
2. `CONTRIBUTING.md` names the `>= 3.11` requirement and `make check`.
3. `CONTRIBUTING.md` carries the four git safety rules.
4. `SECURITY.md` gives a contact route and states the not-a-sandbox caveat.
5. No other tracked file is modified.

## 4. Verification Step

```bash
test -f CONTRIBUTING.md && test -f SECURITY.md
grep -c '3\.11'      CONTRIBUTING.md   # want >= 1
grep -c 'make check' CONTRIBUTING.md   # want >= 1
grep -ci 'stash'     CONTRIBUTING.md   # want >= 1
git diff --name-only HEAD~1
```
