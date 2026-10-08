---
id: CI-FIX-3
title: "test_standby uses BSD 'sed -i \"\"' — fails on ubuntu CI, main red again after FALLBACK-1"
type: wayfinder:task
status: backlog
assignee: arch
owns: tests/test_standby.sh
parent: maps/dispatch-safety-and-review-policy.md
---

# CI-FIX-3 -- make test_standby portable (third CI bug of this class)

## Intended Outcome

`make check` passes on `ubuntu-latest` again. Run `37772778703` (main @ `4384971`,
FALLBACK-1 promote) is red on ubuntu, green on macOS.

## Background (receipts, PM audit 2026-10-08)

`gh run view 37772778703 --log-failed`: `✖ FAILED: tests/test_standby.sh`; cases [2],
[3], [3a]-[3e], [4] fail with
`standby: [seats.looper_standby] is disabled in config — enable it (enabled = true) first`.
`tests/test_standby.sh:111`: `sed -i '' 's/^enabled = false$/enabled = true/' "$CFG"`.
`sed -i ''` is BSD/macOS-only; GNU sed (ubuntu) does not apply the edit, so the seat
stays disabled and every downstream case fails. The suite was green locally (macOS), so
local green is again not evidence for CI. Third occurrence after CI-FIX-1/2.

## Done-Criteria

1. Replace with a portable edit (write to a temp file and `mv`, or `sed ... > tmp`), no
   `-i` at all. Bash 3.2 floor applies.
2. Sweep `tests/` and `lib/` for any other `sed -i` / BSD-only flag use (`stat -f`,
   `date -r`, `readlink -f`, etc.) and state the result in the hand-off.
3. Process fix, mandatory in the hand-off: say how this class gets caught BEFORE promote
   (e.g. `scripts/ci-local.sh` running the suite under a GNU-userland container, or an
   ubuntu CI run on the integration ref prior to promote). A promote that turns main red
   three times is a gate gap, not bad luck.

## Verification Step

`make check` green locally; after promote, `gh run list -L 1` shows `completed success`
on BOTH `make check (ubuntu-latest)` and `make check (macos-latest)`.
