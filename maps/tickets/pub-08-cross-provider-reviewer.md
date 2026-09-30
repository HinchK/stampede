---
id: PUB-8
title: "Cross-provider review lane: implementer and reviewer never share a kind"
type: wayfinder:task
status: resolved
assignee: arch
owns: briefs/reviewer.in.md,docs/user-guide.md
parent: maps/public-multi-provider.md
blocked_by: PUB-3
github_issue: 97
github_url: "https://github.com/HinchK/stampede/issues/97"
synced_at: "2026-09-30T17:16:14Z"
---

# PUB-8 — Cross-provider review lane (Wave 11)

## 1. Intended Outcome

The `reviewer` seat (disabled today) becomes a documented one-flip lane:
with ≥2 providers, the guide shows seating the reviewer with a *different*
kind than the implementer, auditing the gated sha before human promote.
The reviewer brief is rewritten to the house contract: read the ticket +
gated sha in the integration worktree, report findings to `looper` /
the human, never merge, never gate.

## 2. Problem

Provider-diverse review catches provider-shared blind spots — the same
laziness biases are not identical across vendors. The seat exists, the
brief is stale, and the cross-provider story is undocumented. This is the
cheapest killer feature in the PRD: it needs no pipeline change because
review is advisory — the Suite Gate stays the only gate.

## 3. Plan

- `briefs/reviewer.in.md`: standing brief in brief-template grammar
  (renderable by `lib/briefs.sh`), covering: scope (the gated sha, not the
  branch tip), method (read tests first, then diff), emission (findings as
  a structured report to looper; `REVIEW DONE #<ticket> <sha>` as its
  advisory anchor), and the two nevers (never merge, never self-verify).
- `docs/user-guide.md`: new section "Cross-provider review" — enable
  `reviewer` in config with a kind different from the implementer chain,
  wire it into the promote step as a human-facing audit, note explicitly
  that reviewer approval does not retire tickets.
- No `swarm.config.toml` edit here (single-writer wave — PUB-7 owns it);
  the guide's flip instructions are the mechanism.

## 4. Explicit Done-Criteria

- Brief renders through the real template engine in a scratch repo
  (receipted in the ticket body, not asserted).
- Guide section runnable against the demo repo by a two-provider reader.
- Zero claims that review replaces the gate.

## 5. Verification Step

```bash
bash lib/briefs.sh render reviewer <scratch-slug> && test -s <rendered-path>
make check
```

## 6. Resolution (2026-09-22, `eda9042`)

- `briefs/reviewer.in.md`: Rewritten standing brief to the house contract — reviews gated commit sha only via read-only git plumbing (`git show <sha>`, `git diff <base>..<sha>`); never checks out or mutates refs in shared root; tests-first review methodology; structured cited findings (`file:line`); advisory anchor `REVIEW DONE #<ticket> <sha>`; two nevers: never merge, never self-verify.
- `briefs/reviewer.md`: Tracked generic render regenerated from template matching other tracked briefs.
- `docs/user-guide.md`: Added Section 9 "Cross-provider review (optional lane)" with one-flip activation instructions, cross-model diverse bias rationale, and clear advisory contract (Suite Gate remains only gate, human promote remains only merge).
- Verification: Real template engine render verified in scratch demo repo with 0 leftover placeholders; 0 shellcheck warnings; `make check` 14/14 suites green (323 assertions, 0 failed).

