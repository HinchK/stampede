# Changelog

All notable changes to Stampede are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The tree is
pre-1.0: the public surface is not frozen.

`make version-check` fails when the top entry below disagrees with
`VERSION`. Tagging is a human act — nothing in this repository pushes.

## [0.5.0] — in development (multi-provider UX wave)

### Added
- `bin/stampede` unified entrypoint; lifecycle commands delegate to
  `herdr-loop-swarm.sh` unchanged, other commands dispatch by convention
  to `lib/cli/stampede-<cmd>.sh` (PUB-1).
- Provider registry (`lib/providers.sh`) and `stampede doctor`: per-seat
  OK/MISSING/SKIP provider health plus the 9-point preflight; enabled
  seats decide the exit code (PUB-2).
- `examples/demo-repo`: real test suite and a one-verified-verdict
  walkthrough (PUB-4).
- `VERSION`, this changelog, and `stampede version` (PUB-5).

## [0.4.0] — public readiness (dogfood waves 1–5)

### Changed
- Zero-trust README lede; token-claim relabelled as modelled, not
  measured (DOG-4, DOG-5).
- kultivait/pi local engine fully optional and disabled by default;
  proxy and credentials are config data, never launcher hardcode
  (DOG-7, PROXY-GATE).
- 48 tracked markdown files swept to repo-relative links (DOG-9).

### Added
- Apache-2.0 `LICENSE` (DOG-2); `CONTRIBUTING.md` and `SECURITY.md`
  (DOG-6); CI on macOS and Ubuntu running `make check` on every push and
  PR with pinned shellcheck (DOG-3, DOG-14).
- Centralized tomllib-capable interpreter resolution (`lib/pyenv.sh`)
  and timeout(1) resolution with actionable remediation (DOG-1, DOG-15).
- Hermetic `lib/gh_sync.sh` test suite (DOG-8); fresh-clone partition
  deadlock fix (DOG-11); looper promote guardrail (`--confirm` /
  `PROMOTE_CONFIRM=1`) and arbiter anchored to the orchestrator root
  (DOG-12, DOG-13).

## [0.3.0] — concurrent fan-out (Phase 3)

### Added
- Multi-worker seating from `swarm.config.toml` (heterogeneous kinds,
  worktree isolation per implementation seat).
- `lib/partition.sh`: single-line `owns:` grammar, overlap refusal, and
  path leases held until integration (P3-2, ADR 0012).
- Asynchronous supervisor suite gating with durable job records,
  `(ticket, sha)` dedupe, concurrency cap, mid-gate invalidation
  (P3-3, ADR 0013).
- String ticket ids end-to-end in the arbiter queue (ARB-STR).
- Live ANSI telemetry streaming in the Ops pane (`lib/telemetry.py`).

## [0.2.0] — worktree isolation (Phase 2)

### Added
- `lib/worktree.sh` provisioning with porcelain locking, dirty tracked
  checkpoints, salvage-preserving teardown, stale-branch gating
  (P2-1, P2-H, ADR 0006/0010).
- Supervisor gates seats in their own worktrees with pre/post drift
  detection (P3-3 specs, ADR 0008).
- `lib/arbiter.sh`: gated-sha merges onto `swarm/<slug>/integration`
  with compare-and-swap ref updates and human-only promote (P2-4,
  ADR 0009).
- Dynamic TOML seating, slug namespacing, nonce brief delivery, durable
  seat ledger v2 (T-INT wave, ADR 0003/0007).

## [0.1.0] — sequential swarm (Milestone 1)

### Added
- Fail-closed project profiling and test gating; synthetic gates
  (`true`, `none`, empty) rejected (ADR 0001).
- Supervisor verdict harvesting with exact-sha dedupe and fix-and-
  re-verdict on new commits (ADR 0002).
- 9-point preflight matrix and post-seating readiness verification
  (ADR 0005); safe workspace lifecycle resolved by physical pane cwd
  (ADR 0004).
- Aggregate `make test` / `make lint` / `make check` gates; bash 3.2
  platform floor enforced (#TEST-AGG, #BASH32-FLOOR).
