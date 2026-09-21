---
id: DOG-3
title: "CI: run make check on macos-latest and ubuntu-latest"
type: wayfinder:task
status: backlog
assignee: arch
owns: .github/
parent: maps/public-readiness.md
github_issue: 5
github_url: "https://github.com/HinchK/stampede/issues/5"
synced_at: "2026-09-21T21:52:15Z"
---

# DOG-3 — CI workflow (WAVE 2)

## 1. Intended Outcome

Every push and PR runs `make check` on both macOS and Ubuntu, so the repo can
never again be green on one machine and broken on another.

## 2. Problem

`.github/` does not exist. The 2026-09-19 external review's central finding was
"nothing routinely runs the tests." The `Makefile` landed (#TEST-AGG); the
mechanical external check did not. DOG-1's defect survived precisely because no
CI existed to catch it.

## 3. Scope

`.github/workflows/ci.yml`:

- triggers: `push` to `main`, `pull_request`
- matrix: `macos-latest`, `ubuntu-latest`
- install `shellcheck` and `jq` (brew on macOS, apt on Ubuntu)
- run `make check`

**The macOS leg must NOT pin a Python version.** The runner's stock interpreter
resolution is the configuration DOG-1 exists to survive; pinning 3.12 hides
exactly the regression this job is here to catch.

Do not install `herdr` / `agy` / `opencode` — the suites stub them.

## 4. Done-Criteria

1. `.github/workflows/ci.yml` exists and is valid YAML.
2. Both matrix legs run `make check`.
3. No `actions/setup-python` step pinning a version on the macOS leg.
4. No step requires a secret — the suites are hermetic.

## 5. Verification Step

```bash
"$PYTHON_BIN" -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml")); print("yaml ok")'
grep -c 'setup-python' .github/workflows/ci.yml   # want 0
grep -c 'make check'   .github/workflows/ci.yml   # want >= 1
```

If PyYAML is unavailable, validate with `gh workflow view` after push, or state
plainly in the receipt that YAML validity was eyeballed and not machine-checked.

## 6. Notes

Depends on DOG-1 having landed: this job keeps that fix proven, not merely applied.
