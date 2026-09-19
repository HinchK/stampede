---
id: T-008
title: "Preflight Dependency and Daemon Verification"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: lib/preflight.sh
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
