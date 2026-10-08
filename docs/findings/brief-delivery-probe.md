# HERDR-4 Brief-Delivery Probe — `agent prompt` submission per agent kind

- **Date**: 2026-10-07
- **Prober**: arch-2 (scratch Herdr workspaces `wZ`/`w0`/`w11`-`w13`, scratch dirs under `$HOME/.herdr4-probe-scratch`; never the live herd)
- **Ticket**: [HERDR-4](../../maps/tickets/herdr-4-brief-delivery-modernization.md) · **ADR**: [0017](../adr/0017-herdr-native-coordination-primitives.md) Decision 4
- **Installed Herdr**: 0.9.3 (`agent prompt --wait` present; rejects blocked agents with `agent_blocked` pre-send; `agent_prompt_stalled` if no working/blocked state is observed within 5000 ms of an accepted submission)

## Method

For each kind the swarm seats (`opencode`, `claude`, `agy`): start an agent in a
scratch workspace pane, wait for a stable post-boot state, send one throwaway
pointer prompt — `herdr agent prompt <name> "Probe. Reply with exactly: <MARKER>"`
with **no** manual Enter — then poll `herdr agent read <name> --source
recent-unwrapped --lines 200` for the marker. Marker in pane output ⇒ the prompt
was submitted and processed. A second prompt with `--wait --timeout 90000`
(options after the text — options *before* the text are rejected by the CLI
arg parser: `unknown option`) probed settled-state semantics.

## Per-kind results

| Kind | Fresh-dir startup | `agent prompt` alone submits | `agent prompt … --wait` |
|---|---|---|---|
| opencode | clean (`idle`) | **yes** (rc=0, marker in 6 s) | rc=0, settled state in reply (`done`) |
| claude | **blocked**: trust dialog, cursor defaults to **“No, exit”** — plain Enter kills the session (`gone`); `down` + `enter` accepts ⇒ `idle` | **yes** (rc=0, marker observed) | rc=1 `agent_prompt_stalled` — **spurious**: the marker still appeared, i.e. the prompt was submitted and answered; herdr observed no working/blocked state within 5000 ms |
| agy | blocked on first contact (one `enter` cleared it); `idle` on a re-created dir the same night | **yes** (rc=0, marker in 0 s) | rc=0, settled state in reply (`done`) |

## Verdicts adopted by `deliver_brief_nonce`

1. **The legacy `sleep 1 && send-keys enter` follow-up is dropped for every
   kind.** `agent prompt` provably submits (encoded Enter) on opencode, claude,
   and agy under Herdr 0.9.3. The AGENTS.md folklore ("it often types the text
   and never submits it") is version-stale here — and the follow-up is not
   harmless: a stray Enter on an opencode pane can resubmit the previous
   prompt, i.e. a duplicate worker dispatch.
2. **`--wait --timeout 15000` replaces the blind pre-send
   `agent wait --until idle --timeout 15000`.** It rejects a blocked agent
   before sending (`agent_blocked` — reported, never retried) and returns the
   settled state on success.
3. **`agent_prompt_stalled` / `timeout` are indeterminate, not failures**
   (claude's false negative above). The delivery degrades to a bounded pane
   read verifying the `STANDING BRIEF` marker before reporting delivered;
   unverified ⇒ `FAILED:<code>`.
4. On a Herdr without `--wait` (capability-probed once per process), delivery
   is prompt-only with the herdr rc surfaced — no Enter, no swallowing.

## Incidental operational findings (not fixed here — outside HERDR-4's owns)

- **Claude fresh-dir trust dialog defaults to “No, exit”**: `herdr agent start`
  returns `agent_not_ready` (blocked during startup) and a naive Enter kills
  the session. The launcher's `agent start … || warn` path drops such seats
  quietly into seat-fallback. Accepting requires `send-keys <seat> down` then
  `enter` (or pre-trusting the directory). Worth a ticket if pm seats ever
  land in fresh directories.
- `herdr agent prompt` parses options only *after* the `<TEXT>` positional —
  `prompt <target> --wait <text>` is an `unknown option` error. Call sites
  must order `prompt <target> <text> --wait --timeout <ms>`.
- agy showed a first-contact startup dialog in a brand-new directory that a
  single Enter cleared; the re-created directory booted clean the same night
  (state remembered per path).
