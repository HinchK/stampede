#!/usr/bin/env bash
# lib/cli/stampede-init.sh — `stampede init` (PUB-7)
#
# Provider-interviewed config generator: probes what is actually installed
# (lib/providers.sh), asks (or takes flags for) preset + provider chain,
# and writes a swarm.config.toml that `up` accepts on the first try.
#
# House rules this command lives by:
#   - fail-closed: zero usable providers → exit 1 pointing at stampede doctor
#   - non-destructive: an existing config needs --force, and even then the
#     old file survives as swarm.config.toml.bak
#   - never writes invalid config: output is rendered to a temp file,
#     validated through the real parser (lib/config.sh config_dump_env),
#     and only then moved into place

stampede_cmd_init() {
  local root target_dir="" preset="" kinds_arg="" noninteractive=0 force=0
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --non-interactive) noninteractive=1 ;;
      --preset)          preset="${2:-}"; shift ;;
      --kinds)           kinds_arg="${2:-}"; shift ;;
      --force)           force=1 ;;
      -h|--help)
        cat <<'EOF'
Usage: stampede init [dir] [--non-interactive] [--preset minimal|standard]
                     [--kinds kind1,kind2] [--force]

Generates swarm.config.toml from probed providers.

  dir                target directory (default: current directory)
  --non-interactive  no prompts; requires --preset (and --kinds unless the
                    registry detection finds providers on PATH)
  --preset           minimal (looper + one worker) | standard (pm, looper,
                    worker, docs, gh)
  --kinds            ordered provider chain, primary first
                    (e.g. --kinds opencode,claude)
  --force            overwrite an existing config (backs up to .bak first)

Fails closed when no probed provider is usable — run stampede doctor first.
EOF
        return 0
        ;;
      -*) printf 'init: unknown flag: %s\n' "$1" >&2; return 2 ;;
      *)  target_dir="$1" ;;
    esac
    shift
  done
  [[ -n "$target_dir" ]] || target_dir="$PWD"

  # shellcheck disable=SC1091
  source "$root/lib/common.sh"
  # shellcheck disable=SC1091
  source "$root/lib/pyenv.sh"
  # shellcheck disable=SC1091
  source "$root/lib/providers.sh"
  # shellcheck disable=SC1091
  source "$root/lib/config.sh"

  resolve_python >/dev/null 2>&1 || {
    printf 'init: cannot resolve a tomllib-capable interpreter — see lib/preflight.sh\n' >&2
    return 1
  }
  resolve_timeout >/dev/null 2>&1 || true   # probes degrade, never die, without it

  target_dir=$(cd "$target_dir" 2>/dev/null && pwd) || {
    printf 'init: target directory not found\n' >&2
    return 1
  }
  local config="$target_dir/swarm.config.toml"

  # ── Detect what is actually installed ─────────────────────────────────
  local detected="" k probe
  while IFS= read -r k; do
    probe=$(providers_kind_probe "$k")
    [[ "${probe%% *}" == "ok" ]] && detected+=" $k"
  done < <(providers_list_kinds)

  # ── Resolve the effective chain ───────────────────────────────────────
  local chain=""
  if [[ -n "$kinds_arg" ]]; then
    local entry invalid=""
    IFS=',' read -ra _kinds <<<"$kinds_arg"
    for entry in "${_kinds[@]}"; do
      entry=$(printf '%s' "$entry" | tr -d '[:space:]')
      [[ -z "$entry" ]] && continue
      if ! providers_list_kinds | grep -qx "$entry"; then
        invalid+=" $entry"
        continue
      fi
      # dedupe, keep order
      [[ " $chain " == *" $entry "* ]] || chain+=" $entry"
    done
    if [[ -n "$invalid" ]]; then
      printf 'init: not provider kinds (registry: %s):%s\n' "$(providers_list_kinds | tr '\n' ' ')" "$invalid" >&2
      return 1
    fi
  fi

  local usable=0 ke
  for ke in $chain; do
    probe=$(providers_kind_probe "$ke")
    [[ "${probe%% *}" == "ok" ]] && usable=1 || printf 'init: warning: %s not detected on PATH — seating will fail until installed (stampede doctor)\n' "$ke" >&2
  done

  # ── Interactive interview (default) ────────────────────────────────────
  if [[ "$noninteractive" -eq 0 ]]; then
    if [[ ! -t 0 ]]; then
      printf 'init: stdin is not a terminal — pass --non-interactive (with --preset)\n' >&2
      return 1
    fi
    printf 'stampede init — providers detected:%s\n' "${detected:- (none)}"
    if [[ -z "$preset" ]]; then
      printf 'Preset [minimal]/standard: '
      read -r preset || true
      preset=${preset:-minimal}
    fi
    if [[ -z "$chain" ]]; then
      local default_chain="${detected:-}"
      printf 'Provider chain (comma-separated, primary first) [%s]: ' "${default_chain// /,}"
      read -r kinds_arg || true
      if [[ -n "$kinds_arg" ]]; then
        chain=""
        IFS=',' read -ra _kinds <<<"$kinds_arg"
        for entry in "${_kinds[@]}"; do
          entry=$(printf '%s' "$entry" | tr -d '[:space:]')
          [[ -z "$entry" ]] && continue
          if ! providers_list_kinds | grep -qx "$entry"; then
            printf 'init: not a provider kind: %s\n' "$entry" >&2
            return 1
          fi
          [[ " $chain " == *" $entry "* ]] || chain+=" $entry"
        done
      else
        chain="$default_chain"
      fi
    fi
  else
    [[ -n "$preset" ]] || { printf 'init: --non-interactive requires --preset minimal|standard\n' >&2; return 2; }
    if [[ -z "$chain" ]]; then
      chain="$detected"
    fi
  fi

  chain=$(printf '%s' "$chain" | tr -s ' ' ' ' | sed 's/^ //; s/ $//')
  for ke in $chain; do
    probe=$(providers_kind_probe "$ke")
    [[ "${probe%% *}" == "ok" ]] && usable=1
  done
  if [[ -z "$chain" ]] || [[ "$usable" -eq 0 ]]; then
    printf 'init: no usable provider in the effective chain — nothing written.\n' >&2
    printf 'init: run stampede doctor for per-seat remedies, then retry.\n' >&2
    return 1
  fi

  case "$preset" in
    minimal|standard) ;;
    *) printf 'init: unknown preset: %s (minimal|standard)\n' "$preset" >&2; return 2 ;;
  esac

  # ── Briefs must exist relative to the target dir ───────────────────────
  local briefs_missing="" b
  local -a preset_briefs=(briefs/looper.md briefs/arch.md)
  [[ "$preset" == "standard" ]] && preset_briefs+=(briefs/overseer-pm.md briefs/worker-docs.md briefs/worker-gh.md)
  for b in "${preset_briefs[@]}"; do
    [[ -f "$target_dir/$b" ]] || briefs_missing+=" $b"
  done
  if [[ -n "$briefs_missing" ]]; then
    printf 'init: brief templates missing under %s:%s\n' "$target_dir" "$briefs_missing" >&2
    printf 'init: run inside your stampede checkout (or copy briefs/ there)\n' >&2
    return 1
  fi

  # ── Non-destructive write ──────────────────────────────────────────────
  if [[ -f "$config" ]]; then
    if [[ "$force" -eq 0 ]]; then
      printf 'init: %s already exists — pass --force to overwrite (a .bak will be kept)\n' "$config" >&2
      return 1
    fi
    cp "$config" "$config.bak"
  fi

  # ── Render, validate through the real parser, then move into place ────
  local primary="${chain%% *}" rest=""
  if [[ "$chain" == *" "* ]]; then
    rest="${chain#* }"
    kinds_line="kinds = [\"${chain// /\", \"}\"]"
  else
    kinds_line="default_kind = \"$chain\""
  fi
  local project_name
  project_name=$(basename "$target_dir")

  local tmp="$config.tmp"
  cat > "$tmp" <<TOML
# swarm.config.toml — generated by stampede init (preset: $preset)
# Provider chain probed at $(date '+%Y-%m-%d %H:%M:%S'): $chain
# Edit freely; re-run stampede init --force to regenerate (a .bak is kept).

[swarm]
name = "$project_name"
workspace_label = "swarm-dev"
trace_dir = ".herdr-swarm/traces"
worktree_root = ".herdr-swarm/worktrees"
TOML

  emit_seat() { # key name role brief tab position worktree
    printf '\n[seats.%s]\nname = "%s"\nrole = "%s"\n%s\nbrief = "%s"\ntab = "%s"\nposition = "%s"\n' \
      "$1" "$2" "$3" "$kinds_line" "$4" "$5" "$6"
    if [[ "$7" == "worktree" ]]; then
      printf 'worktree = true\n'
    fi
    return 0
  }

  if [[ "$preset" == "minimal" ]]; then
    emit_seat looper   "looper"  "Orchestrator"          briefs/looper.md      herd bottom-full ""
    emit_seat arch_1   "arch-1"  "Implementation Engine" briefs/arch.md        herd top-right  worktree
  else
    emit_seat pm       "pm"      "Overseer"              briefs/overseer-pm.md herd top-left   ""
    emit_seat arch_1   "arch-1"  "Implementation Engine" briefs/arch.md        herd top-right  worktree
    emit_seat looper   "looper"  "Orchestrator"          briefs/looper.md      herd bottom-full ""
    emit_seat docs     "docs"    "Documentation & ADRs"  briefs/worker-docs.md ops  top-left     ""
    emit_seat gh       "gh"      "GitHub & CI Operations" briefs/worker-gh.md  ops  top-right    ""
  fi >> "$tmp"
  true

  if ! config_dump_env "$(slugify "$project_name")" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    printf 'init: generated config failed validation — nothing written (this is a bug; please report it)\n' >&2
    return 1
  fi
  mv "$tmp" "$config"

  printf 'init: wrote %s\n' "$config"
  printf '     preset %s · chain %s (primary: %s%s)\n' "$preset" "$chain" "$primary" \
    "${rest:+, fallback: $rest}"
  printf '     next: stampede doctor && stampede up <target-repo> -m s\n'
}
