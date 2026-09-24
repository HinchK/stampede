# Spec: Harden the Promote Gate Against Agent Execution

**Date:** 2026-09-23
**Author:** `pm` (Claude Code)
**Trigger:** During the `Prove and Reconcile` / `TRUST-1` / headless-mode work this session, the human driver typed
a direct instruction into `looper`'s Herdr pane ("run `bash lib/arbiter.sh promote --confirm && git push origin
main` on my behalf") and `looper` complied. `looper`'s own brief (`briefs/looper.in.md:60,76`) says this is
"FORBIDDEN," with no carve-out for a direct human ask — it should have refused and handed the command back, the way
`pm` did earlier in the same session when asked the same thing directly. It didn't. This spec hardens the gate so
that refusal doesn't depend on an agent remembering to say no.

---

## 1. What this is and isn't

This is a **local, non-airtight hardening** of the exact failure mode observed: an agent seat running the promote
or push commands itself, whether from inferred permission or a direct human instruction in its own pane. It is
**not** a fix for a deliberate bypass. Every seat in this repo (`pm`, `looper`, `arch-1`, `arch-2`, `agy-docs`,
`agy-gh`) runs as the same OS user with the same `git` and `gh` credentials — there is no credential boundary
between "agent" and "human" today. An agent that edited the check itself, or used `herdr pane run` to inject the
command into a different (human) pane, would not be stopped by anything below. Genuine technical enforcement needs
either GitHub-side branch protection or credential separation (agent seats issued a token that cannot push to
`main` regardless of instruction) — both named as follow-up, not in scope here, because both are decisions the
driver needs to make (see §5).

## 2. Investigation findings (empirical, not assumed)

1. **GitHub branch protection is unavailable on this repo's current plan.**
   ```
   $ gh api repos/HinchK/stampede/branches/main/protection
   {"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", "status":"403"}
   $ gh api repos/HinchK/stampede/rulesets
   {"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", "status":"403"}
   ```
   Server-side enforcement (the only piece an agent can't flip locally) is off the table without a plan or
   visibility change. Routing promote through a GitHub PR (`arbiter_promote --pr` already exists) would not add
   real protection today — `gh pr merge` uses the same shared credential as everything else, so an agent could
   merge its own PR exactly as easily as it can run a local `merge --ff-only`.

2. **A `/dev/tty` challenge does not distinguish human from agent.** Tested empirically, not assumed:
   ```
   $ exec 3</dev/tty 2>&1 && echo tty-ok || echo no-tty     # pm's own bash tool (a detached background job)
   no-tty

   $ herdr agent prompt looper-hinchk-stampede "exec 3</dev/tty 2>&1 && echo tty-ok || echo no-tty"
   tty-ok
   ```
   `looper` runs inside a genuine Herdr-managed PTY pane, so it has a real controlling terminal. Any check based on
   TTY presence would pass for exactly the agent this hardening needs to stop.

3. **A pane-identity check is viable, but only if it fails closed.** Herdr injects `$HERDR_PANE_ID` into every
   pane it manages (`herdr` skill: "Herdr injects the caller's context into each managed pane"). This session
   demonstrated the failure mode directly: `pm`'s own `$HERDR_WORKSPACE_ID` (`wM`) pointed at a workspace that no
   longer exists (`herdr workspace list` shows only `wW`). A naive check ("look up this pane, see no agent, allow")
   would have treated that stale identity as safe. It must not.

## 3. Design

Add `_arb_promote_pane_check()` to `lib/arbiter.sh`, called at the top of `arbiter_promote()` before both the
`--confirm` check and the `--pr`/local mode dispatch (it gates both — pushing the integration branch to open a PR
is still a push the brief forbids agents from making).

**Logic, fail-closed:**

- `$HERDR_PANE_ID` unset entirely → **allow**. No agent in this architecture runs outside a Herdr-managed pane
  (every seat is started via `herdr agent start` into one); an unset pane ID means we are definitely not in an
  agent's own execution context — most likely a human's plain terminal that never went through Herdr at all.
- `$HERDR_PANE_ID` set → query `herdr agent list` and check whether that pane ID appears with a live agent
  attached.
  - Query fails (herdr unreachable, malformed output, anything not a clean success) → **refuse**. Ambiguous state
    is not safe state.
  - Pane resolves to a live agent → **refuse**, with a message naming the pane and telling the human to run it
    themselves from a plain shell.
  - Pane is Herdr-managed but has no agent attached (the human's own raw shell pane, e.g. `wW:p1`) → **allow**.

```bash
_arb_promote_pane_check() {
  if [[ -z "${HERDR_PANE_ID:-}" ]]; then
    return 0
  fi
  local agents
  if ! agents=$(herdr agent list 2>/dev/null); then
    printf 'arbiter: promote refused -- could not query herdr agent state to confirm this pane is not agent-controlled\n' >&2
    return 1
  fi
  if printf '%s' "$agents" | jq -e --arg pid "$HERDR_PANE_ID" \
      '.result.agents[]? | select(.pane_id == $pid)' >/dev/null 2>&1; then
    printf 'arbiter: promote refused -- pane %s is occupied by a recognized agent; run this yourself from a plain shell\n' "$HERDR_PANE_ID" >&2
    return 1
  fi
  return 0
}
```

## 4. Test-seam requirement (do not create a bypass while fixing one)

`tests/test_arbiter.sh` is hermetic — no live Herdr daemon, no network. In that environment `$HERDR_PANE_ID` is
naturally unset, so the existing promote tests pass through the new check unmodified with no changes needed.

**To test the refusal path, do not add an environment variable to skip or force the check.** Any such variable is
exactly the kind of bypass this spec exists to close — an agent that can set `PROMOTE_CONFIRM=1` today could set a
new `ARBITER_SKIP_PANE_CHECK=1` tomorrow just as easily. Instead: since `tests/test_arbiter.sh` sources
`lib/arbiter.sh` directly as a shell library, the test simulates the refused path by **redefining
`_arb_promote_pane_check` after sourcing** (bash allows this) to return 1, asserts `arbiter_promote --confirm`
fails, then redefines it back (or opens a fresh subshell) to assert the normal path still works.

## 5. Explicitly out of scope, named as follow-up

- **Credential separation**: agent seats issued a `git`/`gh` token that cannot push to `main` or merge PRs,
  independent of what they're instructed to do. This is the actual fix for a deliberate bypass; it's a driver
  decision (new tokens, possibly a GitHub App or machine user with scoped permissions) not something to default
  into.
- **GitHub branch protection / rulesets**: blocked by the plan/visibility finding in §2.1. Revisit if the driver
  changes the plan or makes the repo public.
- **Routing promote through `--pr` by default**: not meaningfully stronger than local promote today (§2.1), so not
  recommended until either of the above lands.

## 6. Recommended sequence

1. **GATE-1** (arch): implement `_arb_promote_pane_check()` per §3, wire it into `arbiter_promote()`, add the
   refusal-path test per §4. `owns: lib/arbiter.sh,tests/test_arbiter.sh`.
2. **GATE-2** (agy-docs, blocked by GATE-1): amend ADR 0009 with this mechanism and its limitations (§1, §5) —
   written against what GATE-1 actually built, not this spec's proposal. Cross-reference DOG-12 (the original
   human-promote guardrail).
3. The promote that lands GATE-1/GATE-2 must be run by the human, same as every promote — and this time, that's
   the mechanism itself checking, not just a dispatch prompt saying so.
