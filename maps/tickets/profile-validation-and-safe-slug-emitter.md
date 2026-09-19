---
id: T-002-fix
title: "Profile Validation and Safe Slug Emitter"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: lib/profile.sh
parent: maps/universal-herdr-swarm.md
---

# Profile Validation and Safe Slug Emitter (D3 & D4 Fix)

## Question

How should `lib/profile.sh` prevent empty user inputs from silently caching `TEST_CMD="none"`, how should downstream modes refuse execution when no test runner exists, and how should a shared `slugify()` and `shlex.quote` argv emitter in `lib/config.sh` enforce Herdr agent naming rules (`^[a-z][a-z0-9_-]*$`)?

## Preamble

1. **Intended Outcome**: Harden `lib/profile.sh` so interactive test command prompts re-ask on empty input (never silently caching `none`), add `test_cmd_is_runnable()` gate blocking auto-queue mode when `TEST_CMD="none"`, implement a shared `slugify()` function adhering to `^[a-z][a-z0-9_-]*$`, and update `lib/config.sh` to pass parameters via `sys.argv` and emit values quoted via `shlex.quote`.
2. **Explicit Done-Criteria**:
   - `lib/profile.sh`: Empty prompt input re-prompts; `none` only accepted if explicitly typed.
   - `lib/profile.sh`: Defines `test_cmd_is_runnable "$cmd"` returning 1 for `""`, `"none"`, or `"true"`.
   - `slugify()` converts `MyApp` -> `myapp`, `loop.bot` -> `loop-bot`, `123-app` -> `s-123-app`, and `a'b` -> `a-b`.
   - `lib/config.sh`: `config_dump_env` passes arguments via `sys.argv` (no inline string interpolation) and uses `shlex.quote`.
   - Shellcheck on `lib/profile.sh` and `lib/config.sh` passes with 0 warnings.
3. **Verification Step**: Run `shellcheck lib/profile.sh lib/config.sh && python3 -c "import sys; from subprocess import run; res = run(['./lib/config.sh', '--dump-env', \"a'b\"], capture_output=True, text=True); assert res.returncode == 0 and 'SEAT_' in res.stdout, res.stderr; print('PASS: slug quotes safely emitted')"`
