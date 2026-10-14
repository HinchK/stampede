#!/usr/bin/env bash
# lib/providers.sh — the provider registry (PUB-2)
#
# One place that knows which agent-CLI kinds exist and how to probe them.
# The pipeline (dispatch, suite gate, arbiter) never consults this file —
# it is provider-blind by design; only seating-relevant surfaces do
# (doctor, init, fallback chains). A provider entry is: binary name,
# version probe, and an honest remediation string. No provider gets
# special treatment anywhere else in the codebase (design tenet 4,
# maps/public-multi-provider.md).
#
# Sourced by: lib/cli/stampede-doctor.sh (and later init/fallback/seating).
# Requires: lib/common.sh (resolve_timeout), lib/pyenv.sh (resolve_python)
# for config-seat enumeration.

set -euo pipefail

# ── Registry ───────────────────────────────────────────────────────────────
# providers_kind_binary <kind>   → binary name (echo) / rc 1 unknown kind
providers_kind_binary() {
  case "$1" in
    claude)   echo "claude" ;;
    opencode) echo "opencode" ;;
    agy)      echo "agy" ;;
    pi)       echo "pi" ;;
    *)        return 1 ;;
  esac
}

# providers_kind_remediation <kind> → install pointer (echo); rc 1 unknown
providers_kind_remediation() {
  case "$1" in
    claude)   echo "install: npm install -g @anthropic-ai/claude-code" ;;
    opencode) echo "install: curl -fsSL https://opencode.ai/install | bash" ;;
    agy)      echo "install the AGY CLI (see its vendor docs), or seat these roles with another provider kind" ;;
    pi)       echo "optional local engine — see the [seats.pi] note in swarm.config.toml" ;;
    *)        return 1 ;;
  esac
}

# providers_list_kinds — registry enumeration (one per line)
providers_list_kinds() {
  printf 'claude\nopencode\nagy\npi\n'
}

# ── Probing ────────────────────────────────────────────────────────────────
# providers_kind_probe <kind>
#   → "ok <resolved-binary> <version-first-line>"   provider usable
#   → "missing <remediation>"                       binary not on PATH
#   → "unknown-kind <kind>"                         not in the registry
# Read-only: a `--version` call bounded by timeout(1) (5s); CLIs without a
# fast --version still resolve — the version field degrades to "unknown".
providers_kind_probe() {
  local kind="$1" bin ver
  if ! bin=$(providers_kind_binary "$kind"); then
    printf 'unknown-kind %s\n' "$kind"
    return 0
  fi
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'missing %s\n' "$(providers_kind_remediation "$kind")"
    return 0
  fi
  bin=$(command -v "$bin")
  # Bound the probe when timeout(1) is available (DOG-15 resolver); an
  # unresolved timeout degrades to an unbounded call rather than killing
  # the probe entirely — version capture is optional, presence is not.
  if [[ -n "${TIMEOUT_BIN:-}" ]] && command -v "$TIMEOUT_BIN" >/dev/null 2>&1; then
    ver=$("$TIMEOUT_BIN" 5 "$bin" --version 2>/dev/null | head -n1 || true)
  else
    ver=$("$bin" --version 2>/dev/null | head -n1 || true)
  fi
  printf 'ok %s %s\n' "$bin" "${ver:-unknown-version}"
}

# ── Chain resolution ───────────────────────────────────────────────────────
# providers_resolve_chain "kind1 kind2 ..." — walk the ordered chain, return
# the first healthy kind on stdout; empty output (rc 1) when none is usable.
# This is the PUB-6 seating seam: the launcher asks only this question.
providers_resolve_chain() {
  local k probe
  for k in $1; do
    probe=$(providers_kind_probe "$k")
    if [[ "${probe%% *}" == "ok" ]]; then
      printf '%s\n' "$k"
      return 0
    fi
  done
  return 1
}

# ── Model preflight (D2) ────────────────────────────────────────────────────
# providers_check_opencode_models <toml-path>
#   Every ENABLED seat whose chain includes opencode pins a model id that
#   `opencode models` must list. An unlisted id is not a launch error —
#   opencode silently serves a different model — so the only honest gate is
#   a preflight comparison, fail-closed before any workspace or pane exists.
#   rc 0: no opencode seats, opencode absent (advisory; the fallback chain
#         owns a missing binary), or every configured model is listed
#   rc 1: at least one enabled opencode seat pins an unlisted model (one
#         error line per offending seat, naming the seat and the id)
providers_check_opencode_models() {
  local toml_path="$1" bin catalog name model bad_count=0
  local seats_models
  seats_models=$("$PYTHON_BIN" - "$toml_path" 2>/dev/null <<'PYCODE'
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    cfg = tomllib.load(f)
for k, v in cfg.get('seats', {}).items():
    if not v.get('enabled', True):
        continue
    kinds = v.get('kinds') or ([v['default_kind']] if v.get('default_kind') else [])
    if 'opencode' not in kinds:
        continue
    model = v.get('model', 'auto')
    if model and model != 'auto':
        print(f"{v.get('name', k)}|{model}")
PYCODE
) || { printf '  cannot read seat models from %s\n' "$toml_path" >&2; return 1; }
  [[ -n "$seats_models" ]] || return 0
  if ! command -v opencode >/dev/null 2>&1; then
    printf '  opencode not installed — model preflight skipped (fallback chain applies)\n'
    return 0
  fi
  bin=$(command -v opencode)
  if [[ -n "${TIMEOUT_BIN:-}" ]] && command -v "$TIMEOUT_BIN" >/dev/null 2>&1; then
    catalog=$("$TIMEOUT_BIN" 10 "$bin" models 2>/dev/null) || catalog=""
  else
    catalog=$("$bin" models 2>/dev/null) || catalog=""
  fi
  if [[ -z "$catalog" ]]; then
    printf '  opencode models unavailable — model preflight skipped\n'
    return 0
  fi
  while IFS='|' read -r name model; do
    [[ -n "$name" ]] || continue
    if ! grep -qxF "$model" <<<"$catalog"; then
      printf '  seat %s pins opencode model %s — not listed by "opencode models"\n' "$name" "$model" >&2
      bad_count=$((bad_count + 1))
    fi
  done <<<"$seats_models"
  return "$bad_count"
}

# providers_healthy_chain "kind1 kind2 ..." — EVERY healthy kind, one per
# line, in chain order (D3): launch retries walk this list, re-asking the
# health question resolve_chain answers with a single winner.
providers_healthy_chain() {
  local k probe
  for k in $1; do
    probe=$(providers_kind_probe "$k")
    [[ "${probe%% *}" == "ok" ]] && printf '%s\n' "$k"
  done
  return 0
}

# Herdr forwards arguments after `--` to each harness — but only flags the
# harness actually supports. opencode v2's TUI has no --model flag (it exists
# only on `opencode run`): a forwarded flag prints usage and kills the seat
# (HERDR-1 D1). The opencode model travels instead as a per-seat project
# config — `.opencode/opencode.json` in the pane's working directory, which
# opencode resolves natively (verified: session messages record the pinned
# provider/model) and git ignores (`/.opencode`).
providers_write_opencode_model() { # CWD MODEL
  local cfg="${1%/}/.opencode/opencode.json" tmp
  if [[ -f "$cfg" ]]; then
    if jq -e --arg m "$2" '.model == $m' "$cfg" >/dev/null 2>&1; then
      return 0
    fi
    if ! jq -e type "$cfg" >/dev/null 2>&1; then
      printf 'opencode config is not valid JSON (left untouched): %s\n' "$cfg" >&2
      return 1
    fi
    tmp=$(mktemp) || return 1
    if jq --arg m "$2" '.model = $m' "$cfg" > "$tmp" 2>/dev/null && mv "$tmp" "$cfg"; then
      return 0
    fi
    rm -f "$tmp"
    return 1
  fi
  mkdir -p "${1%/}/.opencode" || return 1
  local payload
  payload=$(jq -cn --arg m "$2" '{"$schema": "https://opencode.ai/config.json", model: $m}') || return 1
  printf '%s\n' "$payload" > "$cfg" || return 1
}

providers_start_agent() { # NAME KIND PANE MODEL [CWD]
  local name="$1" kind="$2" pane="$3" model="${4:-}" cwd="${5:-$PWD}"
  case "$kind" in
    opencode)
      if [[ -n "$model" && "$model" != auto ]]; then
        providers_write_opencode_model "$cwd" "$model" || return 1
      fi
      herdr agent start "$name" --kind "$kind" --pane "$pane"
      ;;
    *)
      if [[ -n "$model" && "$model" != auto ]]; then
        herdr agent start "$name" --kind "$kind" --pane "$pane" -- --model "$model"
      else
        herdr agent start "$name" --kind "$kind" --pane "$pane"
      fi
      ;;
  esac
}

# ── Config enumeration ─────────────────────────────────────────────────────
# providers_seats_from_config <toml-path>
#   → lines: "<seat-key>|<kinds-comma-joined>|<enabled:1|0>|<seat-name>"
# Lists ALL seats (enabled and disabled) in declaration order. The kind field
# is the full ordered chain (a lone default_kind is a one-element chain).
# Self-contained python (mirrors lib/config.sh's argv-transport rule: the
# TOML path travels as sys.argv, never interpolated). Requires resolve_python
# to have run.
providers_seats_from_config() {
  local toml_path="$1"
  "$PYTHON_BIN" - "$toml_path" <<'PYCODE'
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    cfg = tomllib.load(f)
for k, v in cfg.get('seats', {}).items():
    kinds = v.get('kinds')
    if kinds is None:
        kinds = [v['default_kind']] if v.get('default_kind') else []
    enabled = 1 if v.get('enabled', True) else 0
    name = v.get('name', k)
    print(f'{k}|{",".join(kinds)}|{enabled}|{name}')
PYCODE
}
