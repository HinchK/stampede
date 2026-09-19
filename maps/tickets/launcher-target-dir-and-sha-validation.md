---
id: T-016-arch
title: "Launcher Target Directory Argument, Commit SHA Verification, and Verify Relabeling (L2, Rec 2, Rec 6)"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: herdr-loop-swarm.sh,lib/lifecycle.sh,loop-bot-herd.sh
parent: maps/universal-herdr-swarm.md
---

# Launcher Target Directory Argument, Commit SHA Verification, and Verify Relabeling (T-016-arch)

## Question

How can `herdr-loop-swarm.sh` reliably accept a target repository directory as a positional argument (`up [dir] [OPTIONS]` or `[dir] [OPTIONS]`), validate that commit SHAs in supervisor verdicts exist in the Git object database before gating (Recommendation 6), and refine seat verification status messages to clarify "interactive-ready" vs "idle" (Audit L2)?

## Preamble

1. **Intended Outcome**: Enable `herdr-loop-swarm.sh up [dir] [OPTIONS]` or `[dir] [OPTIONS]` by changing directory to target prior to preflight and profile detection; validate commit SHAs in `loop-bot-herd.sh` via `git cat-file -e "${sha}^{commit}"`; and refine `swarm_verify_seats` in `lib/lifecycle.sh` to output `interactive-ready` when agents are responsive.
2. **Explicit Done-Criteria**:
   - `herdr-loop-swarm.sh`:
     - Accepts optional `[dir]` argument on `up [dir] [OPTIONS]` or bare `[dir] [OPTIONS]`. If argument is a directory, executes `cd "$target_dir"` so all downstream operations run against that repository without altering script locations.
     - Preserves existing subcommands (`status`, `down`, `verify`).
   - `loop-bot-herd.sh`:
     - When harvesting `ARCH DONE #N <sha>`, verifies commit existence in the repository:
       `git -C "$REPO_DIR" cat-file -e "${sha}^{commit}" 2>/dev/null`
       If the commit SHA does not exist, logs a warning and skips evaluation instead of running tests against an unrelated or hallucinated commit state.
   - `lib/lifecycle.sh`:
     - In `swarm_verify_seats`, changes the label from `ready` to `interactive-ready` to clarify that the agent CLI is responsive and capable of receiving prompts.
   - Quality checks:
     - `shellcheck herdr-loop-swarm.sh lib/lifecycle.sh loop-bot-herd.sh` passes cleanly with 0 warnings.
3. **Verification Step**:
   - Test directory argument: `./herdr-loop-swarm.sh status "$PWD"` and `./herdr-loop-swarm.sh verify "$PWD" 3000`.
   - Test sha validation in `loop-bot-herd.sh` by simulating a non-existent commit sha vs a real git sha.
   - Shellcheck verification command.
