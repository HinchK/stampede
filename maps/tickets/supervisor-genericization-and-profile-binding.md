---
id: T-007b
title: "Supervisor Genericization and Profile Binding"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: loop-bot-herd.sh
parent: maps/universal-herdr-swarm.md
---

# Supervisor Genericization and Profile Binding (T-007b)

## Question

How should `loop-bot-herd.sh` be genericized to operate in arbitrary repositories, loading `REPO` and `TEST_CMD` from `.herdr-swarm/profile.env`, sourcing seats from `swarm.config.toml`, storing session state in `.herdr-swarm/`, and executing the project's detected test runner rather than hardcoded `uv run pytest`?

## Preamble

1. **Intended Outcome**: Genericize `loop-bot-herd.sh` to supervise arbitrary projects by loading `REPO`, `TEST_CMD`, and project metadata from `.herdr-swarm/profile.env`, deriving seats from `swarm.config.toml` (via `lib/config.sh`), and running the project's actual `TEST_CMD` instead of hardcoded `uv run pytest`.
2. **Explicit Done-Criteria**:
   - `loop-bot-herd.sh`: `REPO_DIR` defaults to `${REPO_DIR:-$PWD}`.
   - Sourcing `${REPO_DIR}/.herdr-swarm/profile.env` loads `REPO`, `TEST_CMD`, `ECOSYSTEM`.
   - `STATE_DIR` defaults to `${STATE_DIR:-${REPO_DIR}/.herdr-swarm}`.
   - `EXPECTED_SEATS` loads from `swarm.config.toml` (or `SEAT_KEYS`) rather than hardcoded kultivait seats.
   - The suite gate executes `eval "$TEST_CMD"` (or `(cd "$REPO_DIR" && timeout "$SUITE_TIMEOUT_S" $TEST_CMD >/dev/null 2>&1)`) instead of `uv run pytest`.
   - `grep -n 'Standard-Pentest\|_KULT_\|uv run pytest' loop-bot-herd.sh` returns empty.
   - Shellcheck on `loop-bot-herd.sh` passes cleanly with 0 warnings.
3. **Verification Step**: Run:
   `grep -n 'Standard-Pentest\|_KULT_\|uv run pytest' loop-bot-herd.sh && exit 1 || true`
   and
   `shellcheck loop-bot-herd.sh && echo "PASS: supervisor genericization"`
