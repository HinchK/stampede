---
id: T-002
title: "Profile Detection and Fail-Closed Target Policy"
type: wayfinder:prototype
status: closed
assignee: looper
prototype_asset: lib/profile.sh
owns: lib/profile.sh
parent: maps/universal-herdr-swarm.md
---

# Profile Detection and Fail-Closed Target Policy

## Question

What exact fallback and caching strategy should `lib/profile.sh` follow when detecting repository remotes, ecosystem manifests, and test runners, and how does `.herdr-swarm/profile.env` enforce fail-closed behavior to completely prevent defaulting to `Standard-Pentest/kultivait` or allowing a fake-green test gate (`TEST_CMD="true"`)?

## Resolution

Built and validated prototype in [`lib/profile.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/profile.sh):
1. **Fallback & Caching Hierarchy:**
   - Evaluates `${TARGET_DIR}/.herdr-swarm/profile.env` first for cached/explicit user overrides (`REPO`, `TEST_CMD`, `ECOSYSTEM`, `DOCS_DIR`).
   - For `REPO`: Inspects `remote.upstream.url` first, then `remote.origin.url`, normalizing GitHub URLs into `owner/repo`.
   - For `TEST_CMD`: Inspects ecosystem manifests (`pyproject.toml`, `Cargo.toml`, `package.json`, `go.mod`) with lockfile awareness (e.g. `uv`, `poetry`, `pnpm`, `yarn`, `cargo`).
2. **Fail-Closed Target Policy:**
   - Completely removes hardcoded `Standard-Pentest/kultivait` default.
   - If no GitHub remote exists: In interactive mode prompts the driver (allowing `"none"` for local-only); in non-interactive mode exits non-zero (`1`) with clear remediation guidance.
   - If no test suite can be detected: Completely removes the fake-green `TEST_CMD="true"` fallback. In interactive mode prompts the driver; in non-interactive mode exits non-zero (`1`).
3. **Storage & Verification:**
   - Persists sanitized key-value strings to `.herdr-swarm/profile.env` using double-quoted escaping without backslash nesting.
   - Tested across Python, Rust, Node, and generic ecosystems.
