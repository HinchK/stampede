---
id: T-008
title: "Preflight Dependency and Daemon Verification"
type: wayfinder:prototype
status: closed
assignee: arch
prototype_asset: lib/preflight.sh
owns: lib/preflight.sh
parent: maps/universal-herdr-swarm.md
---

# Preflight Dependency and Daemon Verification

## Question

What exact set of daemon checks, CLI binary dependencies, GitHub authentication probes, and agent runner verifications must be executed before workspace initialization to prevent partial swarm startup failures, and how should remediation steps be formatted for the human operator?

## Preamble

1. **Intended Outcome**: Implement robust preflight validation in `lib/preflight.sh` checking for herdr daemon responsiveness, required CLI binaries (`jq`, `gh`, `python3`), agent CLIs (`agy`, `claude`, `opencode`), git repository state, and GitHub authentication.
2. **Explicit Done-Criteria**:
   - Checks herdr daemon status (`herdr workspace list`).
   - Checks core binaries: `jq`, `python3` (validating `tomllib` availability), `git`, `gh`.
   - Checks GitHub CLI authentication status (`gh auth status`).
   - Inspects installed agent CLIs (`agy`, `claude`, `opencode`).
   - Supports `--quiet` and `--json` modes.
   - Shellcheck passes with 0 warnings.
   - Returns exit 0 when dependencies are satisfied; exits non-zero with explicit remediation hints when core tools are missing.
3. **Verification Step**: Run `shellcheck lib/preflight.sh && ./lib/preflight.sh && (PATH=/usr/bin:/bin ./lib/preflight.sh >/dev/null 2>&1 && exit 1 || exit 0)`.

## Resolution

Implemented and validated in [`lib/preflight.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/preflight.sh):
1. **Multi-Stage Validation Matrix:** Inspects 9 discrete requirements across daemon liveness (3 retries with 1s backoff), core CLIs (`jq`, `git`, `python3` validating `tomllib` module), GitHub authentication (`gh auth status`), agent executables (`agy`, `claude`, `opencode`), and git repository presence.
2. **Dual-Mode Execution & Shell Portability:** Exposes public functions (`preflight_run`, `preflight_report_text`, `preflight_report_json`, `preflight_exit_code`) for sourcing into `herdr-loop-swarm.sh`, with robust guards (`${BASH_SOURCE[0]:-}`) ensuring seamless sourcing in both Bash 3.2+ and Zsh.
3. **Machine-Readable & Quiet Flags:** Supports `--json` for automated health logging and `--quiet` for silent gate assertions. Exits 0 on clean environments and exits 1 with human-actionable remediation instructions when mandatory tools are absent.

