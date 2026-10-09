#!/usr/bin/env bash
# lib/briefs.sh — Dynamic Brief Templating and Nonce Delivery Protocol
# Prototype for Ticket: [Brief Templating Syntax and Nonce File Protocol]
#
# Renders briefs/*.in.md into ${TARGET_DIR}/.herdr-swarm/briefs/*.md
# Delivers briefs via file-path reference rather than raw inline prompt strings.

set -euo pipefail

# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck disable=SC1091  # tomllib-capable interpreter (DOG-1)
source "$(dirname "${BASH_SOURCE[0]}")/pyenv.sh"
resolve_python

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BRIEFS_SRC_DIR="${SCRIPT_DIR}/briefs"

# Substitute {{KEY}} variables in a template file using Python for safety
substitute_template() {
  local template_in="$1"
  local output_out="$2"
  local vars_json="$3"

  mkdir -p "$(dirname "$output_out")"

  "$PYTHON_BIN" -c "
import json, sys

with open('$template_in', 'r', encoding='utf-8') as f:
    content = f.read()

vars_dict = json.loads('''$vars_json''')

for k, v in vars_dict.items():
    placeholder = '{{' + k + '}}'
    content = content.replace(placeholder, str(v))

with open('$output_out', 'w', encoding='utf-8') as f:
    f.write(content)
"
}

# Render all brief templates for a target repository and slug
render_all_briefs() {
  local target_dir="${1:-$PWD}"
  local slug="${2:-}"
  local dest_dir="${target_dir}/.herdr-swarm/briefs"

  # Load profile variables
  # shellcheck disable=SC1091  # dynamically resolved sibling lib
  source "${SCRIPT_DIR}/lib/profile.sh"
  ensure_profile "$target_dir" 0 >/dev/null

  # Load config variables
  # shellcheck disable=SC1091  # dynamically resolved sibling lib
  source "${SCRIPT_DIR}/lib/config.sh"
  eval "$(config_dump_env "$slug")"

  # Build replacement JSON dictionary.
  # SCRIPT_DIR / ARBITER_BIN: the absolute orchestrator paths, so brief
  # templates can point agents at the governing arbiter instead of a
  # cwd-relative `lib/arbiter.sh` that resolves inside the target (DOG-13).
  # Travel via the environment — never interpolated into the Python source.
  export SCRIPT_DIR
  export ARBITER_BIN="${SCRIPT_DIR}/lib/arbiter.sh"
  local vars_json
  vars_json=$("$PYTHON_BIN" -c "
import json, os

vars_map = {
    'REPO': os.environ.get('REPO', 'local/repo'),
    'TEST_CMD': os.environ.get('TEST_CMD', 'echo no-test-suite'),
    'ECOSYSTEM': os.environ.get('ECOSYSTEM', 'generic'),
    'DOCS_DIR': os.environ.get('DOCS_DIR', 'docs'),
    'SLUG': '$slug',
    'SCRIPT_DIR': os.environ.get('SCRIPT_DIR', ''),
    'ARBITER_BIN': os.environ.get('ARBITER_BIN', ''),
    'ARCH_NAME': os.environ.get('SEAT_NAME_arch_1') or os.environ.get('SEAT_NAME_arch', 'arch-$slug'),
    'LOOPER_NAME': os.environ.get('SEAT_NAME_looper', 'looper-$slug'),
    'PM_NAME': os.environ.get('SEAT_NAME_pm', 'pm-$slug'),
    'DOCS_NAME': os.environ.get('SEAT_NAME_docs', 'agy-docs-$slug'),
    'GH_NAME': os.environ.get('SEAT_NAME_gh', 'agy-gh-$slug'),
    'REVIEWER_NAME': os.environ.get('SEAT_NAME_reviewer', 'reviewer-$slug'),
    'TRACE_DIR': os.environ.get('SWARM_TRACE_DIR', '.herdr-swarm/traces'),
    'PROXY_ENDPOINT': os.environ.get('PROXY_ENDPOINT', ''),
}
print(json.dumps(vars_map))
")

  mkdir -p "$dest_dir"

  # Render each template file in briefs/
  for tmpl in "$BRIEFS_SRC_DIR"/*.in.md; do
    [[ -f "$tmpl" ]] || continue
    local base
    base=$(basename "$tmpl" .in.md)
    local out_path="${dest_dir}/${base}.md"
    substitute_template "$tmpl" "$out_path" "$vars_json"
    printf '  \033[32m✓\033[0m Rendered brief: %s -> %s\n' "$(basename "$tmpl")" "$out_path"
  done
}

# HERDR-4: one submission path. The live probe (2026-10-07, Herdr 0.9.3 —
# docs/findings/brief-delivery-probe.md) proved `agent prompt` alone submits
# for every kind the swarm seats (opencode, claude, agy), so the legacy
# `sleep 1 && send-keys enter` follow-up is GONE everywhere: a stray Enter can
# resubmit the previous prompt on an opencode pane (duplicate dispatch).
_BRIEFS_PROMPT_WAIT_CACHE=""
_briefs_prompt_has_wait() {
  if [[ -z "$_BRIEFS_PROMPT_WAIT_CACHE" ]]; then
    if herdr agent prompt --help 2>&1 | grep -q -- '--wait'; then
      _BRIEFS_PROMPT_WAIT_CACHE=yes
    else
      _BRIEFS_PROMPT_WAIT_CACHE=no
    fi
  fi
  [[ "$_BRIEFS_PROMPT_WAIT_CACHE" == yes ]]
}

# Deliver brief to seated agent using file-path nonce protocol.
# Contract (HERDR-4): exactly one `agent prompt` per delivery — no Enter
# follow-up — with `--wait` where the capability probe says yes; failures are
# surfaced (delivered / FAILED:reason), never swallowed.
deliver_brief_nonce() {
  local seat_name="$1"
  local brief_path="$2"

  if [[ ! -f "$brief_path" ]]; then
    printf '  \033[31m✖ Brief file not found: %s\033[0m\n' "$brief_path" >&2
    return 1
  fi

  # Compact reference prompt (<200 bytes, immune to buffer truncation).
  # NOTE: herdr parses options only AFTER the <TEXT> positional —
  # `prompt <target> --wait <text>` is an arg-parser error (probe receipt).
  local prompt_msg="STANDING BRIEF: You are seated as '${seat_name}'. Your standing brief is rendered at '${brief_path}'. Read it immediately using your file viewing tools and adopt this posture. Acknowledge when ready."
  local out rc
  if _briefs_prompt_has_wait; then
    out=$(herdr agent prompt "$seat_name" "$prompt_msg" --wait --timeout 15000 2>&1) && rc=0 || rc=$?
  else
    out=$(herdr agent prompt "$seat_name" "$prompt_msg" 2>&1) && rc=0 || rc=$?
  fi

  if [[ $rc -eq 0 ]]; then
    printf '  \033[32m✓\033[0m Brief delivered to %s (%s)\n' "$seat_name" "$(basename "$brief_path")"
    return 0
  fi

  # agent_blocked: herdr rejected the submission pre-send — report, never
  # retry (ADR 0017 D4; a blocked agent must not be nudged by a resubmit).
  if [[ "$out" == *agent_blocked* ]]; then
    printf '  \033[31m✖ Brief delivery FAILED for %s: agent_blocked (agent is blocked — prompt was not sent; not retrying)\033[0m\n' "$seat_name" >&2
    return 1
  fi

  # agent_prompt_stalled / timeout are INDETERMINATE, not failures: the probe
  # caught claude returning agent_prompt_stalled while the prompt was in fact
  # submitted and answered. Degrade to a bounded pane read verifying the
  # STANDING BRIEF marker (typing == submission on a --wait-capable Herdr)
  # before deciding; unverified ⇒ FAILED.
  local code
  code=$(printf '%s' "$out" | sed -nE 's/.*"code":"([a-z_]+)".*/\1/p' | head -n1)
  case "${code:-rc$rc}" in
    agent_prompt_stalled|timeout)
      local _
      for _ in 1 2 3; do
        if herdr agent read "$seat_name" --source recent-unwrapped --lines 200 2>/dev/null \
           | grep -q "$BRIEF_ACK_REGEX"; then
          printf '  \033[32m✓\033[0m Brief delivered to %s (%s, verified by pane read after %s)\n' \
            "$seat_name" "$(basename "$brief_path")" "${code:-timeout}"
          return 0
        fi
        sleep 2
      done
      printf '  \033[31m✖ Brief delivery FAILED for %s: %s (marker not in pane output)\033[0m\n' \
        "$seat_name" "${code:-timeout}" >&2
      return 1
      ;;
    *)
      printf '  \033[31m✖ Brief delivery FAILED for %s: %s\033[0m\n' \
        "$seat_name" "${code:-${out:0:160}}" >&2
      return 1
      ;;
  esac
}

# CLI dispatcher
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-render}"
  case "$cmd" in
    render)
      render_all_briefs "${2:-$PWD}" "${3:-dev}"
      ;;
    deliver)
      deliver_brief_nonce "${2:-}" "${3:-}"
      ;;
    *)
      echo "Usage: $0 [render [target_dir] [slug]|deliver <seat_name> <brief_path>]"
      exit 1
      ;;
  esac
fi
