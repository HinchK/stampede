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

  # Build replacement JSON dictionary
  local vars_json
  vars_json=$("$PYTHON_BIN" -c "
import json, os

vars_map = {
    'REPO': os.environ.get('REPO', 'local/repo'),
    'TEST_CMD': os.environ.get('TEST_CMD', 'echo no-test-suite'),
    'ECOSYSTEM': os.environ.get('ECOSYSTEM', 'generic'),
    'DOCS_DIR': os.environ.get('DOCS_DIR', 'docs'),
    'SLUG': '$slug',
    'ARCH_NAME': os.environ.get('SEAT_NAME_arch', 'arch-$slug'),
    'LOOPER_NAME': os.environ.get('SEAT_NAME_looper', 'looper-$slug'),
    'PM_NAME': os.environ.get('SEAT_NAME_pm', 'pm-$slug'),
    'DOCS_NAME': os.environ.get('SEAT_NAME_docs', 'agy-docs-$slug'),
    'GH_NAME': os.environ.get('SEAT_NAME_gh', 'agy-gh-$slug'),
    'REVIEWER_NAME': os.environ.get('SEAT_NAME_reviewer', 'reviewer-$slug'),
    'TRACE_DIR': os.environ.get('SWARM_TRACE_DIR', '.herdr-swarm/traces'),
    'PROXY_ENDPOINT': os.environ.get('PROXY_ENDPOINT', 'http://localhost:4114/v1'),
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

# Deliver brief to seated agent using file-path nonce protocol
deliver_brief_nonce() {
  local seat_name="$1"
  local brief_path="$2"

  if [[ ! -f "$brief_path" ]]; then
    printf '  \033[31m✖ Brief file not found: %s\033[0m\n' "$brief_path" >&2
    return 1
  fi

  # 1. Wait until agent is idle before sending prompt
  herdr agent wait "$seat_name" --until idle --timeout 15000 >/dev/null 2>&1 || true

  # 2. Deliver compact reference prompt (<200 bytes, immune to buffer truncation)
  local prompt_msg="STANDING BRIEF: You are seated as '${seat_name}'. Your standing brief is rendered at '${brief_path}'. Read it immediately using your file viewing tools and adopt this posture. Acknowledge when ready."
  herdr agent prompt "$seat_name" "$prompt_msg" >/dev/null 2>&1 || true

  # 3. Send enter keystroke to confirm submission
  sleep 1
  herdr agent send-keys "$seat_name" enter >/dev/null 2>&1 || true

  printf '  \033[32m✓\033[0m Brief delivered to %s (%s)\n' "$seat_name" "$(basename "$brief_path")"
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
