---
id: T-INT-2
title: "Integrate Config Registry, Namespacing, and Templated Brief Delivery"
type: wayfinder:prototype
status: resolved
assignee: arch
prototype_asset: herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
resolution:
  commit: 2455bc5
  verified_by: looper
  date: "2026-09-19"
---

# Integrate Config Registry, Namespacing, and Templated Brief Delivery (T-INT-2, T-005, T-INT-3)

## Question

How should `herdr-loop-swarm.sh` be integrated with `lib/config.sh` and `lib/briefs.sh` to eliminate hardcoded seat arrays, dynamically seat agents from `swarm.config.toml`, namespace agent names via `slugify()`, render briefs from templates and deliver them via compact file-path nonces, and record seated pane IDs into `.herdr-swarm/seats.json`?

## Preamble

1. **Intended Outcome**: Integrate `lib/config.sh` and `lib/briefs.sh` into `herdr-loop-swarm.sh`, dynamically seating agents from `swarm.config.toml`, namespacing agent names with `slugify()`, rendering and delivering briefs via `deliver_brief_nonce` file-path protocol (deleting `cat "$brief_file"`), and recording seated panes into `.herdr-swarm/seats.json`.
2. **Explicit Done-Criteria**:
   - `herdr-loop-swarm.sh` sources `lib/config.sh` and `lib/briefs.sh`.
   - Project slug is computed via `slugify "${REPO:-$(basename "$PWD")}"`.
   - Evaluates `$(config_dump_env "$PROJECT_SLUG" "$CONFIG_FILE")` to load seat definitions.
   - Calls `render_all_briefs "$PWD" "$PROJECT_SLUG"`.
   - Replaces hardcoded seat calls (:308-319) with iteration over `SEAT_KEYS`, seating each agent with its namespaced name, kind, and model.
   - Replaces inline prompt string dumping (`cat "$brief_file"`) with `deliver_brief_nonce`.
   - Records seated agents into `${PWD}/.herdr-swarm/seats.json` matching `{"workspace_id": "$WS_ID", "seats": [{"name": ..., "kind": ..., "pane": ...}]}`.
   - Verify `grep -n 'cat "$brief_file"\|seat_agent_safe looper' herdr-loop-swarm.sh` returns empty.
   - Shellcheck on `herdr-loop-swarm.sh` passes with 0 warnings.
3. **Verification Step**: Run:
   `grep -n 'cat "$brief_file"\|seat_agent_safe looper' herdr-loop-swarm.sh && exit 1 || true`
   and
   `shellcheck herdr-loop-swarm.sh lib/config.sh lib/briefs.sh && echo "PASS: config and brief integration"`

## Verification Log

- Dynamic seating loop over `SEAT_KEYS` integrated into `herdr-loop-swarm.sh`.
- Hardcoded seat lists and static prompt string dumping (`cat "$brief_file"`) completely deleted.
- Nonce file-path protocol (`deliver_brief_nonce`) active for all brief dispatches.
- Durable seat ledger written to `.herdr-swarm/seats.json` matching the schema required for safe teardown.
- Kickoff prompts parameterized with `${ARCH_AGENT}` and `${LOOPER_AGENT}`.
- Shellcheck on `herdr-loop-swarm.sh`, `lib/config.sh`, and `lib/briefs.sh` passed cleanly with 0 warnings.
- Resolved in commit `2455bc5`.
