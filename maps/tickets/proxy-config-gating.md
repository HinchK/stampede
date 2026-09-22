---
id: PROXY-GATE
title: "Universal launcher must not hardcode kultivait: proxy start, health URL, serve cmd, and credits probe are config-gated"
type: wayfinder:defect
status: resolved
commit: 14f8016
assignee: pi
owns: herdr-loop-swarm.sh,loop-bot-herd.sh,lib/config.sh,swarm.config.toml
parent: maps/universal-herdr-swarm.md
github_issue: 40
github_url: "https://github.com/HinchK/stampede/issues/40"
synced_at: "2026-09-22T03:16:07Z"
---

# PROXY-GATE

The "universal" launcher ran `uv run kultivait serve` in any target repo
regardless of `[proxy] enabled = false`; the supervisor read
`~/.kultivait/credentials.toml` unconditionally and pointed operators at a
script that does not exist in this repo (`herdr-kultivait-session.sh`).

**Fix:**

- `[proxy] enabled` defaults to **false** (a universal target repo never
  inherits this machine's kultivait setup); `serve_cmd` is config data.
- `lib/config.sh` emits `PROXY_HEALTH_URL` and `PROXY_SERVE_CMD` alongside
  `PROXY_ENABLED`/`PROXY_ENDPOINT`; plan preview says "Routing proxy".
- Launcher preflight and Ops-pane launch blocks run only when enabled, probe
  the configured health URL, and run the configured serve command (warn and
  skip when enabled without a serve_cmd).
- Supervisor: recovery pointer now names this repo
  (`./herdr-loop-swarm.sh up <dir>`); `credits_watch` runs only when
  `[proxy] enabled = true` and honors `KULTIVAIT_CREDENTIALS` for the path.

## Verification Step

    bash lib/config.sh dump s | grep PROXY     # enabled=false + health/serve
    make lint                                  # 0 warnings
    grep -n 'kultivait serve' herdr-loop-swarm.sh   # no hits (cmd lives in toml)
