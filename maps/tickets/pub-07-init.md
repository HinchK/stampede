---
id: PUB-7
title: "stampede init: provider-interviewed config generator"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/cli/stampede-init.sh,tests/test_cli_init.sh,swarm.config.toml
parent: maps/public-multi-provider.md
blocked_by: PUB-2,PUB-6
---

# PUB-7 — `stampede init`: from probe to working config (Wave 11)

## 1. Intended Outcome

`stampede init` (interactive by default, `--non-interactive` for scripts)
detects available providers via `lib/providers.sh`, interviews the user
(roles → seats → kinds, sensible defaults for one-provider users), and
writes a `swarm.config.toml` that `lib/config.sh` parses and `up -m s`
accepts on the first try. It refuses to finish with zero providers and
points at `stampede doctor`.

## 2. Problem

Hand-editing the TOML is fine for authors and hostile to strangers: seat
tables, kind spellings, worktree flags, geometry. `init` is the last mile
of M1 (first green verdict < 15 min) once the guide and demo exist.

## 3. Plan

- Non-destructive: existing `swarm.config.toml` → require `--force`, and
  even then write `swarm.config.toml.bak` first (the worktree-salvage
  instinct applied to config).
- Interview state machine: detected kinds → offer role presets
  (minimal: looper + one worker; standard: + pm/docs/gh) → per-seat kind
  choice defaulting to the probe result → write.
- Emitted config reuses PUB-6 chains where >1 provider detected
  (primary = first interview answer, fallback = remaining).
- `--non-interactive` takes flags (`--preset minimal|standard`, `--kinds
  a,b`) and fails closed on contradictions rather than prompting.
- Acceptance test in `tests/test_cli_init.sh`: run init against a scratch
  dir with stubbed providers → `bash lib/config.sh dump <slug>` succeeds →
  rendered config seats stub panes in a scratch workspace harness.

## 4. Explicit Done-Criteria

- Zero providers detected → non-zero exit, remediation message naming
  `stampede doctor`; nothing written.
- Existing config without `--force` → non-zero exit, nothing written.
- Every config `init` can emit parses under `lib/config.sh` (property
  asserted across preset × provider-count combinations in tests).
- 0 shellcheck warnings.

## 5. Verification Step

```bash
bin/stampede init --non-interactive --preset minimal --kinds opencode
bash lib/config.sh dump scratch-slug ; echo "rc=$? (want 0)"
make check
```

## 6. Resolution (2026-09-22, `3a534c0`)

- `lib/cli/stampede-init.sh`: Provider-interviewed configuration generator supporting interactive interview and `--non-interactive --preset minimal|standard --kinds <k1,k2,...>`. Enforces non-destructive overwrites requiring `--force` with `.bak` backup preservation. Validates rendered config through the real parser (`config_dump_env`) in a temporary staging location before installation.
- `tests/test_cli_init.sh`: 24 hermetic assertions covering preset × provider matrix parsed through the real parser; rosters, worktree isolation, chain ordering; zero-provider, bad-kind, no-preset, non-tty, missing-briefs, and overwrite/`.bak` discipline.
- `tests/test_async_gate.sh` (`6e1521e`): Load-calibrated non-blocking scan assertion self-calibrating against reference spawn times with sub-second timestamps.
- ShellCheck: 0 warnings; 14/14 suites green across the integrated combined tree.

