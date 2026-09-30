---
id: DOG-17
title: "scripts/repo-state.sh: single-command git/gh state summary"
type: wayfinder:task
status: resolved
commit: f78b0a1
assignee: arch
owns: scripts/repo-state.sh,CLAUDE.md
parent: maps/public-readiness.md
blocked_by: []
github_issue: 101
github_url: "https://github.com/HinchK/stampede/issues/101"
synced_at: "2026-09-30T17:16:14Z"
---

# DOG-17 — scripts/repo-state.sh: single-command git/gh state summary (Wave DX-1)

## 1. Intended Outcome

`scripts/repo-state.sh` prints, in one run: current branch, the last N
commits, local branches already merged to `main` (prune candidates), CI
status for the current HEAD (via `gh run list` / `gh pr checks`, degrading
gracefully when `gh` is unauthenticated or offline), and a `git status
--short` dirty-tree summary. Read-only; no writes, no network mutation.

## 2. Problem

Source: this session's own PM audit loop (2026-09-22) ran the same
handful of `git log --oneline`, `git merge-base --is-ancestor`, `git diff
--stat`, and `gh`-adjacent checks by hand across six separate ticket
audits (PUB-11, REV-1..5). A `/insights` usage report flagged this same
pattern across other repos this account works in: Bash calls dwarf every
other tool, and a large share are re-typed git/gh state-inspection
sequences rather than one-off commands. A single entry point turns that
into one call instead of four or five, and gives every seat (arch, pm,
looper) the same view of "where does this repo stand right now."

## 3. Plan

- `scripts/repo-state.sh [dir]`: defaults to `$PWD`, accepts an optional
  target dir like the existing `bin/stampede status [dir]` convention.
- Sections, each header-labeled: `branch`, `commits` (last 10 `--oneline`),
  `merged branches` (`git branch --merged main` minus `main` itself),
  `ci` (best-effort `gh run list -L 5 --branch <branch>`; print `gh:
  unavailable` and continue with rc 0 if `gh` is missing/unauthenticated
  — this is a status readout, not a gate, and must never fail the whole
  script over an optional signal), `dirty tree` (`git status --short`, or
  `clean` when empty).
- No suite/lint gate gets bypassed or replaced by this — it is purely
  informational, in the same spirit as `bin/stampede status`.
- Document it in `CLAUDE.md` under `## Commands` next to the existing
  read-only launcher subcommands, one line, pointing future sessions at
  it instead of ad-hoc `git log`/`gh` sequences.

## 4. Explicit Done-Criteria

- Runs cleanly with no `gh` on `PATH` and with `gh` present but
  unauthenticated — both are degraded-output cases, not failures (exit 0).
- 0 shellcheck warnings.
- Does not write to the repo, does not touch `.herdr-swarm/`, does not
  require network access to produce the `branch`/`commits`/`merged
  branches`/`dirty tree` sections.

## 5. Verification Step

```bash
scripts/repo-state.sh
scripts/repo-state.sh /tmp/some-other-clone
shellcheck scripts/repo-state.sh
make check
```
