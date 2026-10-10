---
type: report
title: Superpowers Installation Verification Report
created: 2026-10-10
tags:
  - superpowers
  - opencode
  - verification
  - install
related:
  - '[[PROVIDER]]'
  - '[[INSTALL_PLAN]]'
  - '[[INSTALL_LOG]]'
  - '[[USER_ACTIONS]]'
---

# Verification Report

- **Provider**: opencode
- **Date**: 2026-10-10

## Provider-level check

- Command run: `opencode run --print-logs "hello" 2>&1 | grep -i superpowers`
- Output (truncated to ~20 lines):

  ```text
  (no matches — grep found zero "superpowers" strings in the 150-line log; full log kept at /tmp/oc_verify.log)
  ```

  The grep heuristic is inconclusive on OpenCode 1.18.35: `--print-logs` at INFO level never names plugins or
  their origin. The only plugin-adjacent log line in a healthy boot is:

  ```text
  timestamp=2026-10-10T10:05:05.121Z level=INFO run=fe3ef662 message=init count=138
  ```

  The plan's documented fallback smoke test (INSTALL_PLAN.md, Automatable Step 2) was therefore used: a fresh
  `opencode run` was asked whether `using-superpowers`, `brainstorming`, `writing-plans`, and
  `using-git-worktrees` are available in its session. Its verbatim answer:

  ```text
  YES — all four load from the superpowers package at
  ~/.cache/opencode/packages/superpowers@git+https:/github.com/obra/superpowers.git/node_modules/superpowers/skills/
  (using-superpowers, brainstorming, writing-plans, using-git-worktrees).
  ```

- Verdict: PASS — the literal grep's empty result is a log-verbosity artifact, not a missing plugin; the documented
  fallback smoke test passes decisively in a brand-new process.

## Config sanity check (opencode)

- File: `/Users/hinchk/.config/opencode/opencode.json`
- Parses as JSON: yes (`python3 -m json.tool` → exit 0)
- `plugin` contains superpowers entry: yes — exactly one entry:

  ```json
  "plugin": [
    "superpowers@git+https://github.com/obra/superpowers.git"
  ]
  ```

  (Full file content deliberately omitted here: the file embeds provider API keys. Top-level keys `$schema`,
  `model`, `small_model`, `mcp`, `provider`, `plugin` are all intact; the plugin entry is the only change made
  by the install, matching INSTALL_LOG.md's receipts.)
- Restart-required: yes in general — OpenCode does not hot-reload plugin config changes. However, see the
  in-session probe below: the session writing this report already started after the config edit, so the
  restart has effectively happened for this agent.

## In-session probe

Probed the current session three ways. (1) Skill exposure: this session's available-skills list contains the
superpowers set — `using-superpowers`, `brainstorming`, `writing-plans`, `using-git-worktrees`,
`test-driven-development`, `executing-plans`, `subagent-driven-development`, `dispatching-parallel-agents`,
`systematic-debugging`, `requesting-code-review`, `receiving-code-review`, `verification-before-completion`,
`writing-skills`, `diagnosing-superpowers` — every one rooted at
`~/.cache/opencode/packages/superpowers@git+https:/github.com/obra/superpowers.git/node_modules/superpowers/skills/`.
(2) On-disk cache: that package directory exists (verified directly —
`skills/using-superpowers/SKILL.md` is present under it), which is OpenCode's plugin install location.
(3) Loaded instructions: the full using-superpowers directive is active in this session's context right now.
Superpowers IS active in this session — no pending reload. This also means USER_ACTIONS.md's restart step is
satisfied: the conversation performing this verification is itself an OpenCode process that started after the
config change (a fresh `opencode run` confirms the same for any new process).

## Final verdict

INSTALLED-AND-ACTIVE

## Notes

- The playbook's grep verification command will keep returning nothing on OpenCode 1.18.35 even when the
  install is perfectly healthy — `--print-logs` INFO output does not mention plugin names. Future re-checks
  should use the behavioral probe (ask a fresh `opencode run` whether it has the superpowers skills) rather
  than the grep.
- The `kultivait/auto` small-model endpoint was unreachable during both test runs ("Cannot connect to API" —
  stream error, session-titling only). Harmless for superpowers, but it is noise in every log.
- USER_ACTIONS.md's suggested verification prompt ("Tell me about your superpowers") should succeed in any
  new OpenCode session; nothing remains blocked on the user.
