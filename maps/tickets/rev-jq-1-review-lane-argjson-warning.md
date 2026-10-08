---
id: REV-JQ-1
title: "Review lane jq --argjson error on unquoted or empty findings count"
type: wayfinder:task
status: resolved
assignee: arch
owns: loop-bot-herd.sh
parent: maps/pick-up-where-we-left-off.md
---

# REV-JQ-1 -- harden review verdict telemetry against empty/malformed findings counts

## Intended Outcome

Review verdict telemetry emission in `loop-bot-herd.sh` safely tolerates empty, non-numeric, or missing findings counts without emitting `jq: parse error` stderr warnings or suppressing telemetry events.

## Background

In `loop-bot-herd.sh:558-569`:
```bash
fp="${STATE_DIR}/reviews/${ticket}-${sha}.md"
fc=0
if [[ -f "$fp" ]]; then
  fc=$(grep -cE '^\[(BLOCK|CONCERNS)\]' "$fp" 2>/dev/null || printf '0')
fi

local dirs rc=0
dirs=$(review_loop_on_review_verdict "$ticket" "$sha" "$verdict" "$STATE_DIR" 2>/dev/null) || rc=$?
"$PYTHON_BIN" "$SCRIPT_DIR/lib/telemetry.py" log "$SESSION_ID" review.verdict "$seat" "$ticket" \
  "$(jq -cn --arg t "$ticket" --arg h "$sha" --arg v "$verdict" --arg r "$round" --argjson f "$fc" \
    '{ticket:$t, sha:$h, verdict:$v, round:($r|tonumber), findings_count:$f, summary:("review " + $v + " for #" + $t + " (round " + $r + ", " + ($f|tostring) + " findings)")}')" \
  --trace-dir "${STATE_DIR}/traces" >/dev/null 2>&1 || true
```

If `$fc` evaluates to an empty string, whitespace, or non-numeric output (e.g. if `grep` encounters an edge-case output or empty return before fallback), `jq --argjson f "$fc"` fails with:
`jq: error: ... parse error: Expected JSON value`.
Because `set -e` is active or piped, or stderr is redirected, this emits unhandled warnings and causes the telemetry payload generation to fail silently. Furthermore, `$round` from `reviews.json` is parsed with `jq -r '.reviews[$t].round // 0'` which can evaluate to null or empty string if the key structure is malformed.

## Done-Criteria

1. Ensure `$fc` is strictly normalized to an integer (e.g. `${fc:-0}` with non-digit stripping, or passed via `--arg f "$fc"` and cast defensively in jq via `($f | tonumber? // 0)`).
2. Ensure `$round` is defensively normalized to an integer fallback before or during jq payload generation (`($r | tonumber? // 0)`).
3. Verify `jq -cn` execution never fails or emits parse errors when review evidence file is missing, empty, or contains unconventional findings markers.
4. Add unit test coverage in `tests/test_async_gate.sh` or `tests/test_review_loop.sh` verifying that malformed review findings counts do not crash or corrupt verdict telemetry.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_async_gate.sh && make check
```
## Resolution (2026-10-08)

Resolved in commit `2fe4963714860e531b9bf1e8bc54aa8396d6ebba` (`2fe4963`), implemented by `arch-1-hinchk-stampede`.

Root cause (stronger than the ticket suspected): `grep -c` prints `0` AND exits 1 on zero
matches, so `fc=$(grep -cE ... || printf '0')` concatenated a SECOND count —
`fc=$'0\\n0'` — which `jq --argjson` parse-rejected, reproducing the live supervisor warning
byte-for-byte. This fired on every zero-findings evidence file, not merely exotic corruption.

1. Shell-side normalization in `loop-bot-herd.sh`: both `$fc` and `$round` pass through
   `tr -cd '0-9'` + `${var:-0}`; the grep arm uses `|| true` (its own `0` output is the count).
2. jq-side backstop: payload switched from `--argjson` to `--arg` with
   `($r|tonumber? // 0)` / `($f|tonumber? // 0)` — malformed input degrades to 0, never kills the payload.
3. Tests `[13f]`/`[13f2]`/`[13g]`/`[13g2]` in `tests/test_async_gate.sh` (73 passed): zero-findings
   evidence emits `findings_count: 0`; corrupt string round degrades to 0; state machine unaffected.
4. Seeded-regression receipt: both telemetry assertions verified RED against the pre-fix supervisor
   (scratch tree from `git archive`), green on the fix.
5. `make check` green (21 suites), 0 ShellCheck warnings. Verdict anchor emitted 2026-10-08;
   supervisor harvest/integration pending at sweep time.
