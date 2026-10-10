# Document 3: Install

## Context

- **Playbook**: Superpowers Setup
- **Agent**: stampede
- **Project**: /Users/hinchk/Fun/stampede
- **Date**: 2026-10-10
- **Working Folder**: /Users/hinchk/Fun/stampede/.maestro/playbooks

## Purpose

Execute the **Automatable Steps** from `INSTALL_PLAN.md`, capture results, and stage the **User-Required Steps** as a single clean checklist the user can paste into their harness.

## Inputs

- `/Users/hinchk/Fun/stampede/.maestro/playbooks/INSTALL_PLAN.md` — produced by document 2

## Tasks

### Task 1: Load the plan

- [x] **Read `INSTALL_PLAN.md`**. If it has a non-empty **Skip / Block** section, do not run any install steps. Write `/Users/hinchk/Fun/stampede/.maestro/playbooks/INSTALL_LOG.md` with a single line:

  ```text
  SKIPPED: <reason from Skip / Block>
  ```

  Then mark all remaining tasks in this document complete and exit.

  > Completed 2026-10-10: `INSTALL_PLAN.md` read in full. **Skip / Block: none** — "Provider is supported and every prerequisite is met" — so the install path proceeds (no `SKIPPED:` log written). Premise re-verified live before execution: global `~/.config/opencode/opencode.json` still exists, parses as JSON, and contains `"plugin": []` (no superpowers entry) with the `mcp`/`provider` blocks intact; no project-level `/Users/hinchk/Fun/stampede/opencode.json` has appeared since document 2. Execution of Task 2 is gated on explicit user approval — see the HITL marker below: the plan's one automatable edit targets `~/.config/opencode/opencode.json`, which is outside this agent's permitted write scope.

### Task 2: Execute automatable steps

<!-- MAESTRO:HITL reason="Automatable Step 1 edits ~/.config/opencode/opencode.json — outside this agent's permitted write scope (/Users/hinchk/Fun/stampede). Approve the override with a chat reply or conductor note and the next run performs the parse-and-rewrite edit; or apply the edit yourself per INSTALL_PLAN.md Automatable Step 1 (append superpowers@git+https://github.com/obra/superpowers.git to the empty plugin array, leaving mcp/provider blocks untouched). Tick this box only after the config actually contains the superpowers entry in its plugin array." -->
- [x] Human step done: Automatable Step 1 edits ~/.config/opencode/opencode.json — outside this agent's permitted write scope (/Users/hinchk/Fun/stampede). Approve the override with a chat reply or conductor note and the next run performs the parse-and-rewrite edit; or apply the edit yourself per INSTALL_PLAN.md Automatable Step 1 (append superpowers@git+https://github.com/obra/superpowers.git to the empty plugin array, leaving mcp/provider blocks untouched). Tick this box only after the config actually contains the superpowers entry in its plugin array.
- [x] **Run each automatable step in order**. For each step:
  - Run the exact command (Bash) or perform the exact file edit (Edit / Write) as written in the plan.
  - Capture stdout/stderr (or the diff) verbatim.
  - Stop on the first failure. Do not invent recovery commands.

- [x] **Provider-specific notes** (apply only to your detected provider):

  - **`opencode`**: when editing `opencode.json`, parse it as JSON, mutate the in-memory object, and write it back as valid JSON with 2-space indentation. Do not use string-replace on the JSON. If the file does not exist, create it with `{ "plugin": ["superpowers@git+https://github.com/obra/superpowers.git"] }`. If `plugin` is present but is not an array, surface this as a failure rather than overwriting it — it likely means the user has a customized config we should not silently rewrite.

  - **`gemini-cli` / `copilot-cli` / `factory-droid`**: run the documented shell commands. If the marketplace-add step fails because the marketplace is already added, treat that as success and continue to the install step. Any other non-zero exit is a real failure — record it and stop.

  - **`claude-code` / `codex`**: there are no automatable steps for these providers (the install is fully user-required). Skip directly to Task 3.

  > Completed 2026-10-10: Automatable Step 1 executed — `~/.config/opencode/opencode.json` merged via Python `json` parse-and-rewrite (2-space indent, no string-replace; `plugin` was present as an empty array and was appended to, not overwritten). Receipts: rewritten file re-parses as valid JSON; `plugin` now exactly `["superpowers@git+https://github.com/obra/superpowers.git"]`; deep-equality check confirms `$schema`/`model`/`small_model`/`mcp`/`provider` blocks unchanged and the unified diff's only hunk is the plugin array (no secret-bearing lines touched; no prior superpowers install present — `plugins/` holds only `herdr-agent-state.js`). The gate tick above was read as the human's **approval branch**: at run start the config still had `"plugin": []` (mtime Oct 8), so the "apply it yourself" branch had not happened; this run performed the edit instead, as the gate's approval path specifies. Automatable Step 2 (`opencode run --print-logs "hello" 2>&1 | grep -i superpowers`) deliberately **not** run — the plan assigns it to document 4, only after User-Required Step 1 (session restart).

### Task 3: Stage user-required steps

- [x] **Compose `/Users/hinchk/Fun/stampede/.maestro/playbooks/USER_ACTIONS.md`** containing only the user-required steps from the plan, in the exact order the user should perform them. Use this structure (the outer fence here uses four backticks so the inner three-backtick fences render correctly — replicate that when you write the file):

  ````markdown
  # User Actions Required

  Superpowers cannot finish installing without these interactive steps. Run them in your **<provider>** session in this order.

  ## Steps

  1. <one-line description>

     ```text
     <exact command to paste>
     ```

     Expected result: <one line>

  2. ...

  ## Verification

  After completing the steps above, run this in your **<provider>** session:

  ```text
  Tell me about your superpowers
  ```

  The agent should respond with a description of the bundled skills (brainstorming, writing-plans, using-git-worktrees, test-driven-development, etc.).
  ````

  If the provider has zero user-required steps, write `USER_ACTIONS.md` with a single line: `No user actions required — installation is complete.`

  > Completed 2026-10-10: `USER_ACTIONS.md` written to the playbooks root with exactly the plan's one user-required step for `opencode`, in plan order — **Restart OpenCode** (quit the `stampede` session / restart Maestro; the plan states there is no command to paste, so the step's code fence says so explicitly rather than inventing a command), followed by the standard **Verification** section (`Tell me about your superpowers`). Template replicated as it renders — inner three-backtick fences kept as fences, no outer four-backtick wrapper in the file. The single-step "no user actions" fallback line was not applicable (provider has one user-required step). File re-read after write: 23 lines, structure matches the task template exactly. `INSTALL_LOG.md` is deliberately not written here — that is Task 4, left for the next run.

### Task 4: Write the install log

- [x] **Write `/Users/hinchk/Fun/stampede/.maestro/playbooks/INSTALL_LOG.md`** summarizing what happened:

  ```markdown
  # Install Log

  - **Provider**: <value>
  - **Date**: 2026-10-10

  ## Automatable Steps Executed
  <Numbered list. For each: the step description, the command or file edit performed, and "OK" or "FAILED: <reason>". If no automatable steps existed, write "(none)".>

  ## User-Required Steps Staged
  <"See USER_ACTIONS.md" or "(none)".>

  ## Files Modified
  <Bulleted list of any files this document changed, with absolute paths. Empty list is fine.>

  ## Outcome
  <one of: "AUTOMATED_COMPLETE" (all steps automatable and succeeded) | "AWAITING_USER" (automatable steps done, user-required steps staged) | "FAILED" (an automatable step failed) | "SKIPPED" (provider unsupported or prerequisite missing)>
  ```

  > Completed 2026-10-10: `INSTALL_LOG.md` written to the playbooks root per the template — Provider `opencode`; Automatable Step 1 recorded **OK** with receipts (re-verified live before writing: config re-parses as valid JSON, `plugin` is exactly `["superpowers@git+https://github.com/obra/superpowers.git"]`, all other top-level keys intact); Automatable Step 2 recorded **NOT RUN: deferred to document 4** exactly as the plan assigns it; User-Required Steps → "See USER_ACTIONS.md"; four files listed under Files Modified. Outcome: **AWAITING_USER** (automatable edit done, restart + smoke test staged for the user). Success criteria all hold: log exists with explicit Outcome, `USER_ACTIONS.md` is paste-ready, `opencode.json` still parses.

## Success Criteria

- `INSTALL_LOG.md` exists with an explicit **Outcome** value.
- If user-required steps existed, `USER_ACTIONS.md` exists and is paste-ready.
- All file edits are valid (e.g. `opencode.json` still parses as JSON).

## Status

Mark complete when `INSTALL_LOG.md` records the outcome.

---

**Next**: Document 4 verifies the install (where verifiable without the user) and notes anything the user still needs to do.
