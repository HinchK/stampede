---
id: PUB-2
title: "Provider registry (lib/providers.sh) and stampede doctor"
type: wayfinder:task
status: ready
assignee: arch
owns: lib/providers.sh,lib/cli/stampede-doctor.sh,tests/test_providers.sh,tests/test_cli_doctor.sh
parent: maps/public-multi-provider.md
blocked_by: PUB-1
---

# PUB-2 — Provider registry + `stampede doctor` (Wave 9)

## 1. Intended Outcome

`stampede doctor` prints one provider-aware health table — per configured
seat: kind, resolved binary, version, `OK`/`MISSING` + install remediation —
plus the existing 9-point preflight result, and exits non-zero iff any
**enabled** seat's provider is unusable. Disabled seats (`enabled = false`)
report `SKIP` and never fail the run.

## 2. Problem

Preflight validates abstract dependencies (`jq`, `git`, `python3`+tomllib,
`gh`, daemon) but not the thing users actually get stuck on: which agent
CLIs they have, which seats those CLIs can serve, and what to install when
one is missing. Provider knowledge is tribal.

## 3. Plan

- `lib/providers.sh`: one registry table — kind → probe function
  (`command -v` the CLI binary, capture `--version` where cheap),
  brief-delivery notes, verdict-protocol note ("any CLI that can read a
  file and print a line can be a worker"). Kinds at landing: `claude`,
  `opencode`, `agy`, `pi`. Registry is data + tiny probes; no provider is
  special-cased anywhere else.
- `lib/cli/stampede-doctor.sh`: reads `swarm.config.toml` via
  `lib/config.sh`, walks seats, consults the registry, renders the table,
  then runs `lib/preflight.sh`. Remediation strings live in the registry.
- Tests: stub binaries on `PATH` (healthy / missing / version-failing),
  enabled-vs-disabled seat expectations, exit codes.

## 4. Explicit Done-Criteria

- Table renders for every configured seat with actionable MISSING text.
- Exit `0` when all enabled seats probe OK; exit `1` if any enabled seat
  misses its provider; disabled seats never affect the exit code.
- 0 shellcheck warnings; registry probes are read-only.

## 5. Verification Step

```bash
bin/stampede doctor; echo "rc=$?"
PATH=/usr/bin:/bin bin/stampede doctor; echo "rc=$? (want 1)"
make check
```
