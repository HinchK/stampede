#!/usr/bin/env bash
# lib/profile.sh — Universal Project Profiling & Fail-Closed Detection
# Prototype for Ticket: [Profile Detection and Fail-Closed Target Policy]
#
# Detects:
#   REPO: Canonical GitHub owner/repo slug (fail-closed, no kultivait default)
#   TEST_CMD: Project validation test suite command (fail-closed, no "true" fake-green)
#   ECOSYSTEM: python | rust | node | go | generic
#   DOCS_DIR: docs directory path
#
# Storage: ${TARGET_DIR}/.herdr-swarm/profile.env

set -euo pipefail

# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Safe key-value writer for profile.env
save_profile_var() {
  local key="$1"
  local val="$2"
  local env_file="$3"

  mkdir -p "$(dirname "$env_file")"
  touch "$env_file"

  local tmp
  tmp=$(mktemp)
  grep -vE "^${key}=" "$env_file" > "$tmp" || true
  val="${val#\"}"
  val="${val%\"}"
  printf '%s="%s"\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$env_file"
}

# Read variable from profile.env if present
read_profile_var() {
  local key="$1"
  local env_file="$2"

  if [[ -f "$env_file" ]]; then
    local raw
    raw=$(grep -E "^${key}=" "$env_file" | head -n1 | cut -d'=' -f2-)
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw#\'}"
    raw="${raw%\'}"
    printf '%s\n' "$raw"
  fi
}

# Detect canonical GitHub repo (prefers upstream over origin)
detect_repo() {
  local target_dir="${1:-$PWD}"
  local env_file="${target_dir}/.herdr-swarm/profile.env"
  local repo=""

  # 1. Check cached profile.env first
  repo=$(read_profile_var "REPO" "$env_file")
  if [[ -n "$repo" ]]; then
    printf '%s\n' "$repo"
    return 0
  fi

  # 2. Check git remotes
  if git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local upstream_url origin_url remote_url
    upstream_url=$(git -C "$target_dir" config --get remote.upstream.url 2>/dev/null || true)
    origin_url=$(git -C "$target_dir" config --get remote.origin.url 2>/dev/null || true)
    remote_url="${upstream_url:-$origin_url}"

    if [[ -n "$remote_url" ]]; then
      repo=$(printf '%s' "$remote_url" | sed -E 's/.*github.com[:\/]([^\/]+\/[^\/\.]+).*/\1/' | sed 's/\.git$//')
    fi
  fi

  if [[ -n "$repo" && "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    printf '%s\n' "$repo"
    return 0
  fi

  # 3. Fail-closed: Never default to hardcoded kultivait!
  return 1
}

# Detect ecosystem and test command
# Ecosystem order matters: explicit project markers (python/rust/node/go)
# always win; then repo-level aggregate runners (make / run_all.sh) — the
# convention this swarm's own targets use — so a repo whose only suite is
# `make test` is still gate-able. Everything else fails closed as generic.
detect_ecosystem() {
  local target_dir="${1:-$PWD}"

  if [[ -f "${target_dir}/pyproject.toml" || -f "${target_dir}/setup.py" || -f "${target_dir}/requirements.txt" ]]; then
    echo "python"
  elif [[ -f "${target_dir}/Cargo.toml" ]]; then
    echo "rust"
  elif [[ -f "${target_dir}/package.json" ]]; then
    echo "node"
  elif [[ -f "${target_dir}/go.mod" ]]; then
    echo "go"
  elif [[ -f "${target_dir}/Makefile" || -f "${target_dir}/makefile" ]] \
       && grep -qE '^[[:space:]]*test[[:space:]]*:' \
            "${target_dir}/Makefile" "${target_dir}/makefile" 2>/dev/null; then
    echo "make"
  elif [[ -f "${target_dir}/run_all.sh" ]]; then
    echo "run_all"
  else
    echo "generic"
  fi
}

detect_test_cmd() {
  local target_dir="${1:-$PWD}"
  local env_file="${target_dir}/.herdr-swarm/profile.env"
  local cached
  cached=$(read_profile_var "TEST_CMD" "$env_file")
  if [[ -n "$cached" ]]; then
    printf '%s\n' "$cached"
    return 0
  fi

  local eco
  eco=$(detect_ecosystem "$target_dir")

  case "$eco" in
    python)
      if command -v uv >/dev/null 2>&1; then
        echo "uv run pytest -q"
      elif [[ -f "${target_dir}/poetry.lock" ]] && command -v poetry >/dev/null 2>&1; then
        echo "poetry run pytest -q"
      else
        echo "pytest -q"
      fi
      ;;
    rust)
      echo "cargo test --quiet"
      ;;
    node)
      if [[ -f "${target_dir}/pnpm-lock.yaml" ]] && command -v pnpm >/dev/null 2>&1; then
        echo "pnpm test"
      elif [[ -f "${target_dir}/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
        echo "yarn test"
      else
        echo "npm test"
      fi
      ;;
    go)
      echo "go test ./..."
      ;;
    make)
      # Aggregate-runner repos: the Makefile's test target was verified by
      # detect_ecosystem (a Makefile without one stays generic/fail-closed).
      echo "make test"
      ;;
    run_all)
      if [[ -x "${target_dir}/run_all.sh" ]]; then
        echo "./run_all.sh"
      else
        echo "bash run_all.sh"
      fi
      ;;
    generic)
      # Fail-closed: Never default to "true"!
      return 1
      ;;
  esac
}

detect_docs_dir() {
  local target_dir="${1:-$PWD}"
  local env_file="${target_dir}/.herdr-swarm/profile.env"
  local cached
  cached=$(read_profile_var "DOCS_DIR" "$env_file")
  if [[ -n "$cached" ]]; then
    printf '%s\n' "$cached"
    return 0
  fi

  if [[ -d "${target_dir}/docs" ]]; then
    echo "docs"
  elif [[ -d "${target_dir}/doc" ]]; then
    echo "doc"
  elif [[ -d "${target_dir}/documentation" ]]; then
    echo "documentation"
  else
    echo "docs"
  fi
}

# Gate for suite-dependent modes (auto-queue, suite-gated verdicts): a test
# command is runnable only when it is a real command. "", "none", and "true"
# all mean "no suite gate" and must block those modes (never fake-green).
test_cmd_is_runnable() {
  local cmd="${1:-}"
  [[ -n "$cmd" && "$cmd" != "none" && "$cmd" != "true" ]]
}

# Prompt for the test validation command. Empty input re-prompts forever —
# "none" is honored only when explicitly typed, never silently substituted.
prompt_test_cmd() { # PROMPT
  local input=""
  while [[ -z "$input" ]]; do
    printf '%s' "$1" >&2
    read -r input || return 1
    [[ -n "$input" ]] || printf '  \033[33m!\033[0m Empty command not allowed — enter a command, or "none" to skip suite gates.\n' >&2
  done
  printf '%s\n' "$input"
}

# Orchestrator entrypoint: Ensures a valid profile exists or prompts / exits fail-closed
ensure_profile() {
  local target_dir="${1:-$PWD}"
  local interactive="${2:-0}"
  local env_file="${target_dir}/.herdr-swarm/profile.env"

  local repo test_cmd eco docs_dir
  eco=$(detect_ecosystem "$target_dir")
  docs_dir=$(detect_docs_dir "$target_dir")

  # Resolve REPO
  if ! repo=$(detect_repo "$target_dir"); then
    if (( interactive )) && [[ -t 0 ]]; then
      printf '  \033[33m?\033[0m No GitHub remote detected for %s.\n' "$(basename "$target_dir")"
      printf '    Enter canonical GitHub repository (owner/repo) or "none" for local-only: '
      read -r repo || true
      [[ -z "$repo" ]] && repo="none"
      save_profile_var "REPO" "$repo" "$env_file"
    else
      printf '  \033[31m✖ FATAL: No GitHub remote detected and REPO is not configured.\033[0m\n' >&2
      printf '    Fix: Run git remote add origin <url> OR set REPO in %s\n' "$env_file" >&2
      return 1
    fi
  else
    save_profile_var "REPO" "$repo" "$env_file"
  fi

  # Resolve TEST_CMD
  if ! test_cmd=$(detect_test_cmd "$target_dir"); then
    if (( interactive )) && [[ -t 0 ]]; then
      printf '  \033[33m?\033[0m No test framework auto-detected for %s (%s).\n' "$(basename "$target_dir")" "$eco"
      test_cmd=$(prompt_test_cmd '    Enter test validation command or "none" to skip suite gates: ')
      save_profile_var "TEST_CMD" "$test_cmd" "$env_file"
    else
      printf '  \033[31m✖ FATAL: Could not auto-detect test command for %s.\033[0m\n' "$eco" >&2
      printf '    Fix: Set TEST_CMD in %s (e.g. TEST_CMD="make test")\n' "$env_file" >&2
      return 1
    fi
  else
    save_profile_var "TEST_CMD" "$test_cmd" "$env_file"
  fi

  save_profile_var "ECOSYSTEM" "$eco" "$env_file"
  save_profile_var "DOCS_DIR" "$docs_dir" "$env_file"

  # Export for caller subshell
  export REPO="$repo"
  export TEST_CMD="$test_cmd"
  export ECOSYSTEM="$eco"
  export DOCS_DIR="$docs_dir"

  return 0
}

# CLI dispatcher if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-dump}"
  case "$cmd" in
    detect-repo)
      detect_repo "${2:-$PWD}" || { echo "none"; exit 1; }
      ;;
    detect-test)
      detect_test_cmd "${2:-$PWD}" || { echo "none"; exit 1; }
      ;;
    detect-ecosystem)
      detect_ecosystem "${2:-$PWD}"
      ;;
    is-runnable)
      if test_cmd_is_runnable "${2:-}"; then echo "runnable"; else echo "not-runnable"; exit 1; fi
      ;;
    ensure)
      ensure_profile "${2:-$PWD}" "${3:-0}"
      ;;
    dump)
      target="${2:-$PWD}"
      ensure_profile "$target" "${3:-0}" >/dev/null
      cat "${target}/.herdr-swarm/profile.env"
      ;;
    *)
      echo "Usage: $0 [detect-repo|detect-test|detect-ecosystem|is-runnable <cmd>|ensure|dump] [dir] [interactive(0|1)]"
      exit 1
      ;;
  esac
fi
