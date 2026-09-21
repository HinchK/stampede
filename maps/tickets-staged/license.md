---
id: DOG-2
title: "Add an OSI license — the repo is currently legally unusable"
type: wayfinder:task
status: backlog
assignee: agy-docs
owns: LICENSE
parent: maps/public-readiness.md
---

# DOG-2 — LICENSE (WAVE 2)

## 1. Intended Outcome

A `LICENSE` file at the repo root so the project may legally be used.

## 2. Problem

No `LICENSE`, no SPDX header, no license field anywhere. Absent a license,
default copyright applies and nobody may use, modify, or redistribute this.
Every other item in this backlog is a quality issue; this one is a permission
issue, and it is the hardest blocker to publication.

## 3. Scope

Add `LICENSE` — **Apache-2.0** unless the human driver says otherwise (the
patent grant is worth having for a tool that orchestrates vendor CLIs). Verbatim
upstream text. Copyright line: `Copyright 2026 HinchK`.

Do **not** add SPDX headers to every source file here — that is churn across
files other tickets own, and would collide.

## 4. Done-Criteria

1. `LICENSE` exists at the repo root with unmodified upstream Apache-2.0 text.
2. Copyright and year filled in; no `[yyyy]` or `[name of copyright owner]`
   placeholders remain.
3. No other tracked file is modified.

## 5. Verification Step

```bash
test -f LICENSE && head -2 LICENSE
grep -c 'yyyy\|name of copyright owner' LICENSE   # want 0
git diff --name-only HEAD~1                       # want exactly: LICENSE
```
