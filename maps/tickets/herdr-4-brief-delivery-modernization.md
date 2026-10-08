---
id: HERDR-4
title: "Brief delivery submits exactly once (drop legacy double-enter)"
type: wayfinder:task
status: backlog
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
