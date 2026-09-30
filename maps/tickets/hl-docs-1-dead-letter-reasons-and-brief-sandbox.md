---
id: HL-DOCS-1
title: "Document honest dead-letter reasons with log pointers and sandbox external_directory requirements"
type: wayfinder:doc
status: backlog
assignee: arch
owns: docs/findings/headless-mode-design.md,lib/cli/stampede-headless.sh,tests/test_cli.sh
parent: maps/harden-headless-mode.md
---

# HL-DOCS-1 — Honest dead-letter reasons, log pointers, and sandbox configuration documentation

**Severity:** LOW (diagnostic clarity and first-run ergonomics).  
**Found by:** `arch-2-hinchk-stampede` during `#PROVE-HEADLESS-1` (Receipt Findings F2 & F4).

## Root Cause

Two ergonomic and diagnostic gaps in headless batch mode:

1. **Misleading dead-letter reasons (F2)**: In `lib/cli/stampede-headless.sh:220-222`, any ticket that fails to conclude is recorded with the generic reason `"batch wall clock exhausted before a verdict"`, even when the worker process crashed immediately (rc=1), hit an invalid model, or was rejected by permissions. No pointer to `logs/<seat>.log` is printed, hiding the real root cause from the operator.
2. **Sandbox external directory brief rejection (F4)**: Headless worker cwd is the isolated worktree (`.herdr-swarm/worktrees/<seat>`), whereas ticket briefs live in the root checkout (`maps/tickets/`). In run mode, OpenCode's default security sandbox treats the root checkout as an `external_directory` and auto-rejects tool calls unless explicitly configured. Bare target repos without `permission.external_directory: "allow"` fail immediately upon trying to read their assigned brief.

Receipt quotes:
> **Finding F2**: "The unconcluded-path dead-letter reason is wrong and hides the cause. Any worker that dies without a verdict — provider error, invalid config, permission rejection — is recorded as `'batch wall clock exhausted before a verdict'` (lib/cli/stampede-headless.sh:220-222). Nothing in batch output points at `logs/<seat>.log`, where the real error sits. A reason like `worker exited rc=1 without a verdict` plus a log pointer would make attempt 1 self-diagnosing."
> 
> **Finding F4**: "The dispatch protocol points workers at a path their sandbox forbids. Briefs live in the root checkout; the worker's cwd is the worktree — an *external directory* to opencode, which auto-rejects in run mode: `! permission requested: external_directory (/tmp/headless-batch-prove/maps/tickets/*); auto-rejecting`. Today a headless target repo *must* ship `permission.external_directory: 'allow'` in its project config or every worker dies unread. Either the design doc must say so loudly, or the harness should copy the brief into the worktree before spawning."

## Done-Criteria

1. In `lib/cli/stampede-headless.sh`, update the dead-letter reporting so that if a worker process has terminated without a verdict, the reason records `worker exited rc=<status> without a verdict` and prints an explicit pointer to `logs/<seat>.log` on stderr/notices.
2. In `docs/findings/headless-mode-design.md`, clearly document:
   - The project-level OpenCode sandbox configuration requirement (`permission.external_directory: "allow"`) needed for headless workers to access briefs in the root repository.
   - The fallback hazard of unpinned global models in `~/.config/opencode/opencode.json` and the practice of pinning target repo models in `.opencode/opencode.json`.
3. Unit test updates in `tests/test_cli.sh` asserting the honest dead-letter reason and log pointer behavior.
4. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_cli.sh
make lint
```
