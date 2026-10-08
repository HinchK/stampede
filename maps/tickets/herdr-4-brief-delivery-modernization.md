---
id: HERDR-4
title: "Brief delivery submits exactly once (drop legacy double-enter)"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/briefs.sh, tests/test_briefs.sh
parent: maps/herdr-native-and-seat-utilization.md
blocked_by: [HERDR-1]
---

# HERDR-4 -- one submission path for brief delivery

## Intended Outcome

`deliver_brief_nonce` (lib/briefs.sh:105-126) submits the standing-brief pointer
prompt exactly once per delivery: `herdr agent prompt` alone where the installed
Herdr's prompt provably submits (encoded Enter), and a **receipted** decision for the
`sleep 1 && herdr agent send-keys enter` follow-up (keep-or-drop per agent kind), with
delivery failures surfaced instead of swallowed.

## Background

ADR 0017 Decision 4. Herdr 0.9.3 docs: "`agent prompt` … sends text plus encoded Enter
and honors the terminal's live bracketed-paste mode", and rejects a blocked agent
before sending. Operational folklore (AGENTS.md wt integration) still instructs a
manual follow-up enter "because it often types the text and never submits it". Both
cannot be universally true; the delta is probably version- or kind-specific. A live
probe settles it — this is exactly the class of claim this repo requires receipts for.

## Done-Criteria

1. **Live probe first**, against a scratch Herdr session (never the live herd): for
   each agent kind the swarm seats (`opencode`, `claude`, `agy`), deliver a
   throwaway pointer prompt with `agent prompt` only and observe whether it submits
   (pane output shows the agent received it). Record the per-kind result table in the
   ticket and in the probe findings file under `docs/findings/` (that file may be
   co-owned with HERDR-1's audit — keep filenames distinct).
2. Where prompt provably submits: remove the `sleep 1 && send-keys enter` follow-up.
   Where it provably does not (kind/version): keep it, gated on the same probe, with a
   comment citing the probe receipt.
3. Adopt `agent prompt --wait` (settled-state wait) in place of the blind pre-send
   `agent wait --until idle --timeout 15000` where the probe shows it is equivalent
   or better; handle `agent_blocked` by reporting, not retrying.
4. Replace the `|| true` swallows on the prompt/wait calls with logged failures
   (delivery result visible in the function's output line: delivered / FAILED:reason).
5. Tests: new `tests/test_briefs.sh` (registered in the suite runner like the others)
   with a stubbed `herdr` asserting: single-submission path on probed-support,
   follow-up path on probed-absent, failure surfaced not swallowed,
   `Makefile`/suite count updated wherever suites are enumerated.

## Verification Step

`make check` green (suite count updated everywhere the repo counts suites). Receipt:
the per-kind probe table pasted in the ticket resolution.

## Notes

The double-enter hazard is not hypothetical: a stray `enter` on an opencode pane can
resubmit the previous prompt — for a worker seat that means a duplicate run of its
last dispatch.

## Resolution (2026-10-07)

Live probe ran first (scratch workspaces `wZ`/`w0`/`w11`-`w13`, never the live
herd; full method + receipts in `docs/findings/brief-delivery-probe.md`):

| Kind | Fresh-dir startup | `agent prompt` alone submits | `prompt … --wait` |
|---|---|---|---|
| opencode | clean | **yes** (marker 6 s) | rc=0, settled state in reply |
| claude | blocked: trust dialog, cursor defaults to "No, exit" (plain Enter exits; `down`+`enter` accepts) | **yes** | rc=1 `agent_prompt_stalled` — **spurious**: marker still appeared (submitted + answered) |
| agy | first contact blocked, one Enter cleared; later idle | **yes** (marker 0 s) | rc=0, settled state in reply |

Implemented per the table: the `sleep 1 && send-keys enter` follow-up is dropped
for every kind (probe-proven submission); `agent prompt --wait --timeout 15000`
(options after the text — the CLI arg parser rejects them before it, a probe
byproduct recorded in the findings) replaces the blind pre-send
`agent wait --until idle`; `agent_blocked` is reported and never retried;
`agent_prompt_stalled`/`timeout` degrade to a bounded pane-read verification of
the `STANDING BRIEF` marker (claude's false negative) before reporting
delivered/`FAILED:<code>`; every failure path surfaces on stderr and returns 1 —
no `|| true` swallows left. `--wait` adoption is itself capability-probed once
per process (`_briefs_prompt_has_wait`) with a prompt-only legacy path.

Incidental findings recorded (outside owns, not fixed here): claude fresh-dir
trust dialog defaults to declining — the launcher's `agent start … || warn`
quietly drops such seats into fallback; worth a ticket if pm seats land in
fresh dirs.

Tests: new `tests/test_briefs.sh` (18 assertions) — missing-file hard fail,
single-submission argv on probed support (one prompt, `--wait --timeout 15000`,
no send-keys, no pre-wait), capability cache across deliveries, legacy
prompt-only path, `agent_blocked` reported-not-retried, stall→pane-verified
delivered, stall-unverified→FAILED with exactly three bounded reads, hard
failures surfaced. Suite count updated everywhere current: CLAUDE.md (20 +
list entry), CONTRIBUTING.md sample list; STATE.md historical counts left
as history.

Receipts: `make check` → `All suites green (20)`, `Lint clean`;
`ls tests/*.sh | wc -l` → 20.
