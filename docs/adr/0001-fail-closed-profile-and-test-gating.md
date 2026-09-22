# ADR 0001: Fail-Closed Profile Detection and Test Gating Policy

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`
- **Consulted**: [T-002](../../maps/tickets/profile-detection-and-fail-closed-target-policy.md), [T-002-fix](../../maps/tickets/profile-validation-and-safe-slug-emitter.md), [T-INT-1](../../maps/tickets/integrate-profile-into-launcher.md), [PM Herd Audit](../audits/2026-09-19-pm-herd-audit.md)

---

## 1. Context and Problem Statement

The legacy swarm launcher (`herdr-loop-swarm.sh`) was originally developed against a single target repository (`Standard-Pentest/kultivait`). This lineage left two catastrophic failure modes in its default initialization logic:

1. **Silent Foreign Repo Fallback**: If `git remote` inspection failed to detect a repository, the launcher defaulted silently to `REPO="Standard-Pentest/kultivait"` (`herdr-loop-swarm.sh:186`).
2. **Fake-Green Test Suite Bypass**: If no language ecosystem manifest was detected, the launcher defaulted to `TEST_CMD="true"` (`herdr-loop-swarm.sh:142`).

In autonomous queue mode (`a`), executing the swarm in an unrecognized, newly created, or unconfigured local repository caused the swarm to pull backlog tickets from `Standard-Pentest/kultivait` and run its supervisor loop against a fake test suite that always returned exit code 0 (`true`). This presented an unacceptable risk of cross-repository contamination, false-positive ticket verdicts, and unverified code mutations.

Furthermore, early iterations allowed empty interactive inputs to silently cache `TEST_CMD="none"`, allowing subsequent runs to bypass validation without warning.

---

## 2. Decision Drivers

- **Zero Unverified Mutations**: No agent or supervisor should ever claim code is verified unless an actual test runner executed and succeeded.
- **Project Agnosticism**: The swarm launcher must work universally across Python, Rust, Node.js, Go, and generic repositories without hardcoded assumptions.
- **Fail-Closed Security & Correctness**: Any missing dependency, unconfigured remote, or absent test command must stop execution or explicitly require human confirmation rather than making permissive guesses.
- **Repeatable Project Identity**: Repository metadata and test suite definitions should be persisted locally (`.herdr-swarm/profile.env`) to avoid redundant re-prompting while supporting explicit overrides.

---

## 3. Considered Options

- **Option A (Legacy)**: Permissive fallback to `Standard-Pentest/kultivait` and `TEST_CMD="true"`.
- **Option B (Heuristic Fallback)**: Guess repository names from the current folder name and skip testing if no runner is found.
- **Option C (Fail-Closed Architecture with Strict Validation)**: Implement an independent profiling library (`lib/profile.sh`) enforcing fail-closed checks for remotes and test suites, backed by a strict `test_cmd_is_runnable()` gate for autonomous modes.

---

## 4. Decision

We adopted **Option C**. We created [`lib/profile.sh`](../../lib/profile.sh) to establish a universal, fail-closed profiling engine with the following concrete rules:

### A. Fallback and Caching Hierarchy
1. **Explicit Cache Check**: Read `${TARGET_DIR}/.herdr-swarm/profile.env` first for cached configuration (`REPO`, `TEST_CMD`, `ECOSYSTEM`, `DOCS_DIR`).
2. **Remote Resolution (`REPO`)**:
   - Check `git config --get remote.upstream.url`, then `remote.origin.url`.
   - Normalize Git URLs (HTTPS, SSH, `git@github.com:`) into canonical `owner/repo` slugs.
   - If no Git remote exists:
     - **Interactive Mode**: Prompt the operator for the repository slug (permitting an explicit `"none"` for purely local repositories).
     - **Non-Interactive Mode**: Exit immediately with status `1` and print clear remediation instructions (`git remote add origin ...`).
   - Under no circumstances does the system fall back to `Standard-Pentest/kultivait`.
3. **Ecosystem & Test Runner Detection (`TEST_CMD`)**:
   - Scan directory manifests with lockfile awareness:
     - Python: `pyproject.toml` (evaluates `uv run pytest`, `poetry run pytest`, `pytest`), `setup.py`, `requirements.txt`.
     - Rust: `Cargo.toml` (`cargo test`).
     - Node.js: `package.json` (evaluates `pnpm test`, `yarn test`, `npm test` based on lockfiles).
     - Go: `go.mod` (`go test ./...`).
   - If no manifest or test runner is detected:
     - **Interactive Mode**: Prompt the operator. If empty input is entered, the prompt loops and warns; `TEST_CMD="none"` is only accepted if explicitly typed.
     - **Non-Interactive Mode**: Exit immediately with status `1` and actionable guidance.
   - The fake-green default `TEST_CMD="true"` is completely eliminated.

### B. Autonomous Queue Mode Gating (`test_cmd_is_runnable`)
Autonomous execution mode (`a`) is strictly gated by `test_cmd_is_runnable "$TEST_CMD"`:
- Returns non-zero (`1`) if `$TEST_CMD` is empty, `"none"`, or contains literal `"true"`.
- The launcher halts before workspace or agent seating:
  ```bash
  if [[ "$MODE" == "a" ]] && ! test_cmd_is_runnable "$TEST_CMD"; then
    echo "ERROR: Autonomous queue mode requires a runnable test command." >&2
    exit 1
  fi
  ```

### C. Safe Persistence
Configuration is written to `${TARGET_DIR}/.herdr-swarm/profile.env` with sanitized double-quoted escaping (`save_profile_var`) to prevent shell injection and backslash corruption.

---

## 5. Consequences

### Positive
- **Guaranteed Isolation**: Eliminates cross-project pollution and accidental commits against wrong GitHub repositories.
- **Integrity of Verdicts**: Tickets can only be closed or marked `green` if an actual test suite executes and passes.
- **Universal Multi-Language Support**: Seamlessly detects modern toolchains (`uv`, `poetry`, `pnpm`, `cargo`, `go`) across diverse repositories.
- **Zero Faux-Green Runs**: Autonomous runs will refuse to proceed in repos lacking automated verification.

### Negative / Trade-offs
- **Initial Setup Friction**: Operators setting up brand new repositories without git remotes or test configurations must interactively answer prompts or configure `.herdr-swarm/profile.env` manually before autonomous mode can run.
