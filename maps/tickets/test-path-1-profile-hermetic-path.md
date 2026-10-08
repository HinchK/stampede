---
id: TEST-PATH-1
title: "Hermeticize tests/test_profile.sh:78 PATH against runner tool shadow hazard"
type: wayfinder:task
status: backlog
assignee: arch
owns: tests/test_profile.sh
parent: maps/pick-up-where-we-left-off.md
---

# TEST-PATH-1 -- hermeticize test_profile [4c] against runner PATH tool shadowing

## Intended Outcome

Test case `4c` in `tests/test_profile.sh` simulates the absence of `uv` and `poetry` without allowlisting host system directories (`PATH=/usr/bin:/bin`), eliminating a latent failure hazard on Ubuntu CI runners.

## Background (citing .herdr-swarm/research/path-allowlist-ubuntu-hazard.md)

Research report `.herdr-swarm/research/path-allowlist-ubuntu-hazard.md` §1 and §2.2 documents a recurring failure mode across GitHub Actions Ubuntu runners (`ubuntu-latest`): test suites that construct `PATH` with `/usr/bin:/bin` under the assumption that a binary is absent fail when Ubuntu runner images preinstall that binary into `/usr/bin/`.

In `tests/test_profile.sh:77-78`:
```bash
check "4c" "python TEST_CMD with no uv and no poetry.lock -> pytest -q" \
  '[[ $(PATH=/usr/bin:/bin detect_test_cmd "$R4") == "pytest -q" ]]'
```

`detect_test_cmd` checks for `uv` via `command -v uv`. On macOS hosts and default Ubuntu runners today, `uv` is either absent or placed in `~/.cargo/bin/uv` or `/usr/local/bin/uv`, so `PATH=/usr/bin:/bin` makes `command -v uv` fail as intended. However, if a future GitHub Actions runner update, local Linux package manager, or container environment installs `uv` or `poetry` into `/usr/bin`, `detect_test_cmd` will find `/usr/bin/uv` and emit `uv run pytest -q`, breaking `check 4c`.

This is the exact same defect class that caused `CI-FIX-1` (`test_ci_local.sh`), `CI-FIX-2` (`test_repo_state.sh`), and `CI-FIX-3` (`test_standby.sh`).

## Done-Criteria

1. Replace `PATH=/usr/bin:/bin` in `tests/test_profile.sh:78` with a hermetic bin directory containing symlinks only to the minimal utilities `detect_test_cmd` executes (e.g. `cat`, `grep`, `sed`, `awk`, `head`, `find`), or explicitly stub/shadow `uv` and `poetry` with failing or absent entries.
2. Verify that an ambient `uv` present on the host or injected into `/usr/bin` (or a simulated runner environment with `uv` on PATH) cannot leak into test case `4c`.
3. Ensure no regressions in existing `check 4a`, `4b`, or other `test_profile.sh` assertions.
4. `make check` green locally and in CI, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_profile.sh && make check
```
