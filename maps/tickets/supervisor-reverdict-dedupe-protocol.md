---
id: T-007a-fix
title: "Supervisor Re-Verdict Deduplication Protocol"
type: wayfinder:prototype
status: resolved
assignee: arch
prototype_asset: loop-bot-herd.sh
owns: loop-bot-herd.sh
parent: maps/universal-herdr-swarm.md
resolution:
  commit: dd54248
  verified_by: looper
  date: "2026-09-19"
---

# Supervisor Re-Verdict Deduplication Protocol (T-007a-fix / D2)

## Question

How should `loop-bot-herd.sh` and `briefs/arch.in.md` implement an explicit commit SHA protocol (`ARCH DONE #<n> <sha>`) and deduplicate on `(ticket, sha)` so that identical re-verdict strings after a RED suite gate failure are correctly re-tested when a new commit is produced?

## Preamble

1. **Intended Outcome**: Upgrade verdict harvesting in `loop-bot-herd.sh` to extract and record commit SHAs, deduplicating on `(ticket, sha)` rather than string verdict matching, and update `briefs/arch.in.md` and `briefs/arch.md` to establish the `ARCH DONE #<n> <sha>` protocol.
2. **Explicit Done-Criteria**:
   - `loop-bot-herd.sh`: Extract `sha` from verdict line matching `ARCH DONE #([0-9]+)[[:space:]]+([0-9a-fA-F]{7,40})` if provided; if omitted, extract from `git rev-parse --short HEAD` in `$REPO_DIR` (or "unknown").
   - Include `"sha": "$sha"` in all JSON verdict records appended to `$SESSION_LOG`.
   - In `harvest_verdicts`, replace the exact-string check with `jq -e -s --argjson t "$ticket" --arg s "$sha" 'any(.[]; .ticket == $t and .sha == $s)' "$SESSION_LOG"`.
   - Re-verdicts with a new commit SHA after a RED verdict are evaluated against the suite gate instead of being skipped.
   - Update `briefs/arch.in.md` and `briefs/arch.md` to instruct emitting `ARCH DONE #<ticket> <sha>`.
   - Shellcheck on `loop-bot-herd.sh` passes cleanly.
3. **Verification Step**:
   Run an automated fixture test:
   Write a RED entry for ticket 99 at sha `aaa1111` in a temporary session log.
   Feed an identical verdict text with sha `bbb2222`. Verify that sha `aaa1111` is skipped, but sha `bbb2222` is processed.

## Verification Log

- `loop-bot-herd.sh` updated to extract and log `sha` in every verdict JSON entry.
- Deduplication logic rewritten with `jq` to deduplicate on `(ticket, sha)` rather than raw verdict line strings.
- Standing briefs `briefs/arch.in.md` and `briefs/arch.md` updated with `ARCH DONE #<ticket> <sha>`.
- Verified via automated harness that repeated verdict at same sha is skipped, while re-verdict with a new sha triggers the suite gate again.
- Shellcheck on `loop-bot-herd.sh` passed clean (0 warnings).
- Resolved in commit `dd54248`.
