---
id: HL-CFG-1
title: "swarm.config.toml headless knobs clobber environment variable overrides"
type: wayfinder:defect
status: backlog
assignee: arch
owns: lib/config.sh,tests/test_config.sh
parent: maps/harden-headless-mode.md
---

# HL-CFG-1 — swarm.config.toml headless knobs clobber environment variable overrides

**Severity:** LOW-MED (silent override defeat; impedes per-run tuning in CI/testing).  
**Found by:** `arch-2-hinchk-stampede` during `#PROVE-HEADLESS-1` (Receipt Finding F7).

## Root Cause

In `lib/config.sh:151-158`, `config_dump_env` unconditionally emits `CONFIG_HEADLESS_MAX_ATTEMPTS` and `CONFIG_HEADLESS_WORKER_TIMEOUT_S` from `swarm.config.toml` whenever configuration is sourced by the supervisor. Because this dump executes unconditionally, any runtime environment variable overrides supplied on the command line (e.g., `CONFIG_HEADLESS_WORKER_TIMEOUT_S=120 bin/stampede headless ...`) are silently clobbered by the static TOML defaults (e.g. 600s).

Receipt quote (Finding F7):
> "The headless knobs have no env override — the TOML binding silently clobbers them (defect vs the documented `gate_concurrency` hierarchy). `config_dump_env` unconditionally emits `CONFIG_HEADLESS_MAX_ATTEMPTS` / `CONFIG_HEADLESS_WORKER_TIMEOUT_S` from `swarm.config.toml` (lib/config.sh:151-158) when the supervisor is sourced, so `CONFIG_HEADLESS_WORKER_TIMEOUT_S=120 bin/stampede headless …` silently runs with the TOML's 600 (attempt 6) and `CONFIG_HEADLESS_MAX_ATTEMPTS=1 …` silently runs with 2 (attempt 7). Either honor env (emit only when unset) or document that per-run tuning requires a TOML, and fail loudly on unknown env overrides."

## Done-Criteria

1. In `lib/config.sh`, emit `CONFIG_HEADLESS_MAX_ATTEMPTS` and `CONFIG_HEADLESS_WORKER_TIMEOUT_S` only if they are not already set in the environment, aligning with the `gate_concurrency` precedence hierarchy (environment overrides configuration).
2. Unit tests in `tests/test_config.sh` asserting environment variable precedence over `swarm.config.toml` values for headless configuration knobs.
3. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_config.sh
```
