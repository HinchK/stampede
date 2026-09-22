---
id: P3
title: "Cross-LLM Quota and Credit Probing"
type: wayfinder:prototype
status: backlog
assignee: arch
owns: lib/quota.sh
parent: maps/universal-herdr-swarm.md
---

# Cross-LLM Quota and Credit Probing (P3)

## Context & Problem Statement

In multi-agent autonomous herds spanning Anthropic (Claude Code), Google Gemini (AGY), and Z.AI / OpenAI (OpenCode), token rate limits (TPM/RPM) and billing credit exhaustion can cause mid-task crashes, silent stalls, or corrupted outputs.

Phase 3 introduces active quota and credit monitoring:
1. **Live Quota Probing:** Query backend rate-limit headers or status endpoints across configured model providers.
2. **Graceful Worker Throttling:** When credit or quota thresholds dip below safe operating margins, automatically signal `looper` and `pm` to pause or reroute tasks before tasks fail.
3. **Telemetry & Ops Alerting:** Stream live provider quota headroom into the Ops pane via `lib/telemetry.py`.

## Preamble

1. **Intended Outcome**: `arch` implements `lib/quota.sh` to probe live API limits across Anthropic, Google Gemini, and Z.AI backends, integrating credit thresholds into `loop-bot-herd.sh`.
2. **Explicit Done-Criteria**:
   - `lib/quota.sh` provides provider-agnostic probing functions for Anthropic, Google Gemini, and Z.AI.
   - `loop-bot-herd.sh` checks quota margins during poll loops and pauses non-essential seats when thresholds are exceeded.
   - Passes `shellcheck` with 0 warnings.
3. **Verification Step**:
   - Run `shellcheck lib/quota.sh`.
   - Run test probing script against mock and live provider endpoints.
