#!/usr/bin/env bash
# lib/partition.sh — Task Intake File Partition Checking & Lease Protocol
# Prototype for Ticket: P3-2 (per docs/audits/2026-09-19-p3-2-task-partition-check-spec.md)
#
# Pure core (no git/herdr needed): owns_normalize, owns_parse_line,
# owns_parse_ticket, owns_overlaps — the functions where bugs would live.
# Stateful: partition_check, lease_acquire/release/list/reconcile
# (mkdir-locked, atomic, bash 3.2 / macOS safe), partition_drift_check,
# partition_suggest.
#
# owns grammar: ONE comma-separated line of repo-relative entries:
#   file            lib/partition.sh
#   dir prefix      docs/adr/
#   glob            tests/test_*.sh   (* does not cross / by intent; the
#                                     matcher is deliberately over-approximate)
# Fallback: a ticket WITHOUT owns acquires an EXCLUSIVE whole-repo lease
# (serialized execution — "owns everything", never "owns nothing").

set -euo pipefail

# ── normalization ───────────────────────────────────────────────────────────
# Normalize one entry: trim, strip leading ./, collapse //, casefold.
# Rejects absolute paths and `..` segments (fail-closed, entry named).
owns_normalize() { # ENTRY -> prints normalized entry; rc 1 = rejected
  local e="$1"
  e="${e#"${e%%[![:space:]]*}"}"
  e="${e%"${e##*[![:space:]]}"}"
  e="${e#./}"
  # bash 3.2 treats `\/` in the replacement of ${e//pat/rep} as a literal
  # backslash (so the naive ${e//\/\/ / /} leaks `lib\/x.sh` and the quoted
  # ${e//"//"/"/"} never collapses, looping forever). Route the replacement
  # through a variable so no backslash is parsed on either bash. (#BASH32-FLOOR)
  local _slash=/
  while [[ "$e" == *//* ]]; do e="${e//\/\//$_slash}"; done
  e=$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')
  if [[ -z "$e" ]]; then
    printf 'owns: empty entry rejected\n' >&2
    return 1
  fi
  if [[ "$e" == /* ]]; then
    printf 'owns: absolute path rejected: %s\n' "$e" >&2
    return 1
  fi
  local seg
  for seg in ${e//\// }; do
    if [[ "$seg" == ".." ]]; then
      printf 'owns: path escaping repo root rejected: %s\n' "$e" >&2
      return 1
    fi
  done
  printf '%s\n' "$e"
}

# Parse a raw comma-separated owns line into normalized entries (one per line).
owns_parse_line() { # STRING -> rc 0 ok, 1 malformed/rejected
  local raw="$1" entry rc=0
  local entries=()
  [[ -n "$raw" ]] || { printf 'owns: empty declaration rejected\n' >&2; return 1; }
  # NOTE: IFS is scoped to this read only — leaking a custom IFS into
  # owns_normalize would corrupt its own word splitting.
  IFS=',' read -r -a entries <<< "$raw"
  for entry in "${entries[@]}"; do
    owns_normalize "$entry" || rc=1
  done
  return "$rc"
}

# Parse `owns:` from a ticket file's frontmatter.
# rc 0 = ok (entries on stdout); 1 = malformed; 2 = absent (fallback path)
owns_parse_ticket() { # TICKET_FILE
  local f="$1" line="" in_fm=0 saw_owns=0 raw=""
  [[ -f "$f" ]] || { printf 'owns: ticket file not found: %s\n' "$f" >&2; return 1; }
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if (( in_fm )); then break; else in_fm=1; continue; fi
    fi
    (( in_fm )) || continue
    if [[ "$line" == owns:* ]]; then
      saw_owns=1
      raw="${line#owns:}"
      raw="${raw#"${raw%%[![:space:]]*}"}"
      continue
    fi
    # §0.1: a YAML block list under owns: parses as empty via line-by-line
    # frontmatter readers — reject it loudly.
    if (( saw_owns )) && [[ "${line#"${line%%[![:space:]]*}"}" == -* ]]; then
      printf 'owns: YAML block list rejected — use a comma-separated single line (owns: a.sh, b.sh)\n' >&2
      return 1
    fi
  done < "$f"
  if (( ! saw_owns )); then
    return 2
  fi
  owns_parse_line "$raw"
}

# ── overlap semantics (deliberately over-approximate) ──────────────────────
_owns_classify() { # ENTRY -> file|dir|glob
  local e="$1"
  [[ "$e" == */ ]] && { printf 'dir\n'; return 0; }
  [[ "$e" == *[\*\?]* ]] && { printf 'glob\n'; return 0; }
  printf 'file\n'
}

_owns_glob_prefix() { # GLOB -> literal text before the first wildcard
  printf '%s' "$1" | sed -E 's/[*?].*$//'
}

_owns_prefix_overlap() { # A B -> 0 when either is a path-prefix of the other
  local a="${1%/}" b="${2%/}"
  [[ "$a" == "$b" || "$a" == "$b/"* || "$b" == "$a/"* ]]
}

_owns_glob_expand() { # GLOB REPO_DIR -> matching paths (possibly none)
  local g="${1#./}" repo="$2"
  (cd "$repo" 2>/dev/null && find . \( -type f -o -type d \) -path "./${g}" 2>/dev/null \
    | sed 's|^\./||') || true
}

# True (0) when entries a and b may intersect. Inputs are normalized on entry
# (casefold, //, ./) so raw declarations compare safely.
owns_entry_overlaps() { # A B [REPO_DIR]
  local a b repo="${3:-$PWD}"
  a=$(owns_normalize "$1" 2>/dev/null || printf '%s' "$1")
  b=$(owns_normalize "$2" 2>/dev/null || printf '%s' "$2")
  local ca cb
  ca=$(_owns_classify "$a"); cb=$(_owns_classify "$b")

  case "${ca}/${cb}" in
    file/file) [[ "$a" == "$b" ]] ;;
    file/dir)  _owns_prefix_overlap "$b" "$a" ;;
    dir/file)  _owns_prefix_overlap "$a" "$b" ;;
    dir/dir)   _owns_prefix_overlap "$a" "$b" ;;
    glob/file|glob/dir)
      # shellcheck disable=SC2053  # intentional glob match (over-approximate:
      # * may cross / — a false conflict is cheap, a missed one is not)
      [[ "$b" == $a ]] || _owns_prefix_overlap "$(_owns_glob_prefix "$a")" "$b"
      ;;
    file/glob|dir/glob)
      # shellcheck disable=SC2053
      [[ "$a" == $b ]] || _owns_prefix_overlap "$(_owns_glob_prefix "$b")" "$a"
      ;;
    glob/glob)
      local pa pb
      pa=$(_owns_glob_prefix "$a"); pb=$(_owns_glob_prefix "$b")
      if [[ -z "$pa" || -z "$pb" ]]; then
        return 0   # undecidable → conflict (fail-closed)
      fi
      if _owns_prefix_overlap "$pa" "$pb"; then
        return 0
      fi
      # expansions against the current tree (a ticket may create files that
      # do not exist yet, hence the prefix rule above is primary)
      local ea eb
      ea=$(_owns_glob_expand "$a" "$repo")
      eb=$(_owns_glob_expand "$b" "$repo")
      [[ -n "$ea" && -n "$eb" ]] || return 1
      comm -12 <(printf '%s\n' "$ea" | sort -u) <(printf '%s\n' "$eb" | sort -u) | grep -q .
      ;;
    *) return 0 ;;
  esac
}

# owns_overlaps SET_A SET_B [REPO_DIR] — sets are newline-separated entries.
# Prints intersecting pairs ("a ∩ b"); rc 0 = any overlap.
owns_overlaps() { # SET_A SET_B [REPO_DIR]
  local a_set="$1" b_set="$2" repo="${3:-$PWD}"
  local a b found=0
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    while IFS= read -r b; do
      [[ -n "$b" ]] || continue
      if owns_entry_overlaps "$a" "$b" "$repo"; then
        printf '%s ∩ %s\n' "$a" "$b"
        found=1
      fi
    done <<<"$b_set"
  done <<<"$a_set"
  return $(( 1 - found ))
}

# ── active set (tickets that may have a worker touching files now) ─────────
# Resolved tickets fail OPEN when the gitignored integration evidence file is
# absent (a fresh clone has none — missing evidence is not activity, DOG-11);
# evidence that EXISTS and does not name the ticket keeps it active.
# _partition_ticket_active ID STATUS INTEG_FILE -> 0 = active
_partition_ticket_active() {
  local id="$1" status="$2" integ="$3"
  case "$status" in
    in_progress) return 0 ;;
    backlog|ready) return 1 ;;
    resolved|done|closed)
      # No evidence file → it cannot testify against the ticket → inactive.
      if [[ ! -f "$integ" ]]; then
        return 1
      fi
      # Evidence present: inactive only when it records this ticket
      # integrated (or since promoted).
      if jq -e -s --arg t "$id" 'any(.[]; (.ticket|tostring) == $t and (.status == "integrated" or .status == "promoted"))' "$integ" >/dev/null 2>&1; then
        return 1
      fi
      return 0
      ;;
    *) return 0 ;;   # unknown/unparseable → active (fail-closed)
  esac
}

# ── partition check: candidate vs live leases + active tickets ─────────────
# rc 0 = dispatchable (owns present, disjoint)
# rc 2 = dispatchable EXCLUSIVELY (no owns — serialized fallback)
# rc 1 = BLOCKED (details printed)
partition_check() { # CANDIDATE_TICKET_FILE [REPO_DIR]
  local cand="$1" repo="${2:-$PWD}"
  local state="${repo}/.herdr-swarm"
  local integ="${state}/integration.jsonl"
  # DOG-11: warn once when the gitignored evidence file is absent, so a
  # genuinely wiped state dir stays visible rather than silently forgiven.
  if [[ ! -f "$integ" ]]; then
    printf 'partition: WARNING integration evidence absent (%s) — resolved tickets assumed inactive\n' "$integ" >&2
  fi
  local owns="" owns_rc=0
  owns=$(owns_parse_ticket "$cand") || owns_rc=$?
  if [[ "$owns_rc" == 1 ]]; then
    return 1   # malformed candidate never dispatches
  fi
  local exclusive=0
  if [[ "$owns_rc" == 2 ]]; then
    exclusive=1
    owns=""
  fi

  local blocked=0
  local lt lown

  # live leases
  if [[ -f "$state/leases.json" ]]; then
    while IFS=$'\t' read -r lt lexcl lown; do
      [[ -n "$lt" ]] || continue
      lown=$(printf '%s' "$lown" | tr ',' '\n')
      if (( exclusive )) || [[ "$lexcl" == "true" ]] \
         || { [[ -n "$owns" && -n "$lown" ]] && owns_overlaps "$owns" "$lown" "$repo" >/dev/null; }; then
        printf 'BLOCKED by lease %s (exclusive=%s)\n' "$lt" "$lexcl" >&2
        [[ -n "$owns" && -n "$lown" ]] && owns_overlaps "$owns" "$lown" "$repo" | sed 's/^/  /' >&2
        blocked=1
      fi
    done < <(jq -r '.leases[]? | "\(.ticket)\t\(.exclusive)\t\((.owns // []) | join(","))"' "$state/leases.json" 2>/dev/null)
  fi

  # active ticket files
  local tf tid tstatus thas_owns towns
  for tf in "$repo"/maps/tickets/*.md; do
    [[ -f "$tf" ]] || continue
    tid=$(sed -nE 's/^id:[[:space:]]*(.+)$/\1/p' "$tf" | head -n1 | tr -d '"')
    tstatus=$(sed -nE 's/^status:[[:space:]]*(.+)$/\1/p' "$tf" | head -n1 | tr -d '"')
    [[ -n "$tid" && -n "$tstatus" ]] || continue
    thas_owns=$(grep -c '^owns:' "$tf" 2>/dev/null || true)
    _partition_ticket_active "$tid" "$tstatus" "$integ" || continue
    towns=""
    [[ "$thas_owns" -gt 0 ]] && towns=$(owns_parse_ticket "$tf" 2>/dev/null || true)
    if (( exclusive )) || { [[ -n "$owns" && -n "$towns" ]] && owns_overlaps "$owns" "$towns" "$repo" >/dev/null; }; then
      printf 'BLOCKED by active ticket %s (status=%s)\n' "$tid" "$tstatus" >&2
      [[ -n "$owns" && -n "$towns" ]] && owns_overlaps "$owns" "$towns" "$repo" | sed 's/^/  /' >&2
      blocked=1
    fi
  done

  (( blocked )) && return 1
  (( exclusive )) && return 2
  return 0
}

# ── leases: locked, atomic (mkdir lock; bash 3.2 / macOS safe) ─────────────
_lease_lock() { # STATE_DIR
  local lk="$1/leases.lock" tries=0 pid
  mkdir -p "$1"
  while ! mkdir "$lk" 2>/dev/null; do
    pid=""
    [[ -f "$lk/pid" ]] && pid=$(cat "$lk/pid" 2>/dev/null || true)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$lk"
      continue
    fi
    tries=$((tries + 1))
    (( tries >= 50 )) && return 1
    sleep 0.2
  done
  printf '%s\n' "$$" > "$lk/pid"
}
_lease_unlock() { rm -rf "${1}/leases.lock" 2>/dev/null || true; }

_lease_write() { # STATE_DIR JQ_FILTER_TEXT (already evaluated JSON on stdin)
  cat > "$1/leases.json.tmp" && mv "$1/leases.json.tmp" "$1/leases.json"
}

# Resolve a ticket id to its file. The id is NOT the filename in this repo —
# maps/tickets/ci-workflow.md carries `id: DOG-3` — so a path built from the id
# works only where the two happen to coincide, and on a case-sensitive
# filesystem it stops working even then: `lease_acquire T-SER` looked up
# T-SER.md for a file written as t-ser.md, which ext4 refuses and APFS resolves.
# Exact filename first (cheap, preserves the previous behaviour), then a
# frontmatter `id:` scan using the same idiom as partition_check above.
_partition_ticket_file() { # TICKET REPO — prints the path; rc 1 when unresolved
  local ticket="$1" repo="$2" tf tid
  if [[ -f "$repo/maps/tickets/${ticket}.md" ]]; then
    printf '%s\n' "$repo/maps/tickets/${ticket}.md"
    return 0
  fi
  for tf in "$repo"/maps/tickets/*.md; do
    [[ -f "$tf" ]] || continue
    tid=$(sed -nE 's/^id:[[:space:]]*(.+)$/\1/p' "$tf" | head -n1 | tr -d '"')
    [[ "$tid" == "$ticket" ]] || continue
    printf '%s\n' "$tf"
    return 0
  done
  return 1
}

# lease_acquire TICKET [SEAT] [BRANCH] [OWNS_LINE|'-' to read ticket file]
# The conflict check and the acquire happen in the SAME locked section.
# rc 0 acquired; 1 blocked/malformed
lease_acquire() {
  local ticket="$1" seat="${2:-unknown}" branch="${3:-}" owns_arg="${4:--}"
  local repo="${REPO_DIR:-$PWD}"
  local state="${STATE_DIR:-$repo/.herdr-swarm}"
  local owns="" owns_rc=0 exclusive=0
  if [[ "$owns_arg" == "-" ]]; then
    local tfile
    if ! tfile=$(_partition_ticket_file "$ticket" "$repo"); then
      printf 'partition: no ticket file for %s under %s/maps/tickets (tried %s.md and an id: scan)\n' \
        "$ticket" "$repo" "$ticket" >&2
      return 1
    fi
    owns=$(owns_parse_ticket "$tfile" 2>/dev/null) || owns_rc=$?
    [[ "$owns_rc" == 1 ]] && return 1
  else
    owns=$(owns_parse_line "$owns_arg") || return 1
  fi
  (( owns_rc == 2 )) && exclusive=1 && owns=""

  _lease_lock "$state" || return 1
  local conflict=0
  if [[ -f "$state/leases.json" ]]; then
    local lt lexcl lown
    while IFS=$'\t' read -r lt lexcl lown; do
      [[ -n "$lt" ]] || continue
      lown=$(printf '%s' "$lown" | tr ',' '\n')
      if (( exclusive )) || [[ "$lexcl" == "true" ]] \
         || { [[ -n "$owns" && -n "$lown" ]] && owns_overlaps "$owns" "$lown" "$repo" >/dev/null; }; then
        printf 'lease: %s BLOCKED by lease %s\n' "$ticket" "$lt" >&2
        conflict=1
        break
      fi
    done < <(jq -r '.leases[]? | "\(.ticket)\t\(.exclusive)\t\((.owns // []) | join(","))"' "$state/leases.json" 2>/dev/null)
  fi
  local rc=0
  if (( conflict )); then
    rc=1
  else
    local owns_json cur='{"version":1,"leases":[]}'
    owns_json=$(printf '%s\n' "$owns" | jq -R -s -c 'split("\n") | map(select(length > 0))')
    [[ -f "$state/leases.json" ]] && cur=$(cat "$state/leases.json" 2>/dev/null || printf '%s' "$cur")
    jq -c --arg t "$ticket" --arg seat "$seat" --arg br "$branch" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson excl "$exclusive" --argjson o "$owns_json" \
      '{version: 1, leases: ((.leases // []) + [{ticket: $t, seat: $seat, branch: $br, owns: $o, exclusive: ($excl == 1), acquired_at: $at}])}' \
      <<<"$cur" > "$state/leases.json.tmp" 2>/dev/null \
      && mv "$state/leases.json.tmp" "$state/leases.json" || rc=1
  fi
  _lease_unlock "$state"
  return "$rc"
}

# lease_release TICKET — locked removal
lease_release() {
  local ticket="$1"
  local repo="${REPO_DIR:-$PWD}"
  local state="${STATE_DIR:-$repo/.herdr-swarm}"
  [[ -f "$state/leases.json" ]] || return 0
  _lease_lock "$state" || return 1
  jq -c --arg t "$ticket" \
    '{version: 1, leases: ((.leases // []) | map(select(.ticket != $t)))}' \
    "$state/leases.json" > "$state/leases.json.tmp" \
    && mv "$state/leases.json.tmp" "$state/leases.json"
  _lease_unlock "$state"
}

lease_list() {
  local repo="${REPO_DIR:-$PWD}"
  local state="${STATE_DIR:-$repo/.herdr-swarm}"
  [[ -f "$state/leases.json" ]] || { printf '(no leases)\n'; return 0; }
  jq -r '.leases[]? | "\(.ticket)\t\(.seat)\texclusive=\(.exclusive)\t\((.owns // []) | join(","))"' "$state/leases.json"
}

# lease_reconcile — a lease whose seat is no longer in seats.json is stale:
# released with a warning (never silently).
lease_reconcile() {
  local repo="${REPO_DIR:-$PWD}"
  local state="${STATE_DIR:-$repo/.herdr-swarm}"
  [[ -f "$state/leases.json" && -f "$state/seats.json" ]] || return 0
  local stale
  stale=$(jq -r -s --slurpfile seats "$state/seats.json" \
    '.[0].leases[]? | . as $l
     | select($l.seat != "" and (($seats[0].seats // []) | map(.name) | index($l.seat) | not))
     | $l.ticket' \
    "$state/leases.json" 2>/dev/null || true)
  local t
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    printf 'lease: WARNING stale lease %s (seat no longer seated) — releasing\n' "$t" >&2
    lease_release "$t"
  done <<<"$stale"
}

# ── post-hoc drift check (§3.4): the declaration is a promise, not a fact ──
# Records owns_violation when a green verdict touched undeclared files.
# Never blocks integration — the arbiter's gate is the real safety net.
partition_drift_check() { # TICKET OWNS_LINE BASE_SHA HEAD_SHA [REPO_DIR]
  local ticket="$1" owns_raw="$2" base="$3" head="$4" repo="${5:-$PWD}"
  local owns
  owns=$(owns_parse_line "$owns_raw" 2>/dev/null || true)
  local viol_file="" f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ -z "$owns" ]] || ! owns_overlaps "$f" "$owns" "$repo" >/dev/null 2>&1; then
      viol_file+="$f"$'\n'
    fi
  done < <(git -C "$repo" diff --name-only "$base" "$head" 2>/dev/null || true)
  if [[ -n "$viol_file" ]]; then
    mkdir -p "$repo/.herdr-swarm"
    jq -cn --arg t "$ticket" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg files "$(printf '%s' "$viol_file")" \
      '{ticket: $t, ts: $ts, violation: "owns_violation", files: ($files | split("\n") | map(select(length > 0)))}' \
      >> "$repo/.herdr-swarm/owns-violations.jsonl"
    printf 'owns_violation: %s touched undeclared files:\n' "$ticket" >&2
    printf '%s' "$viol_file" | sed 's/^/  /' >&2
  fi
  return 0   # recorded, never blocking
}

# ── suggest: propose an owns line from a resolved ticket's diff ────────────
partition_suggest() { # BASE_REF BRANCH [REPO_DIR]
  local base="$1" branch="$2" repo="${3:-$PWD}"
  local files dirs dir count
  files=$(git -C "$repo" diff --name-only "${base}...${branch}" 2>/dev/null || true)
  [[ -n "$files" ]] || return 0
  dirs=$(printf '%s\n' "$files" | sed 's|/[^/]*$||' | sort -u)
  local out=""
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    count=$(printf '%s\n' "$files" | grep -c "^${dir}/" || true)
    if (( count >= 3 )); then
      out+="${dir}/,"
    else
      while IFS= read -r f; do out+="${f},"; done < <(printf '%s\n' "$files" | grep "^${dir}/")
    fi
  done <<<"$dirs"
  out="${out%,}"
  printf 'owns: %s\n' "$out"
}

# ── CLI ────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-}"
  shift 2>/dev/null || true
  case "$cmd" in
    check)
      partition_check "$@"
      ;;
    can-dispatch)
      partition_check "$@"
      ;;
    lease)
      sub="${1:-list}"; shift 2>/dev/null || true
      case "$sub" in
        acquire) lease_acquire "$@" ;;
        release) lease_release "$@" ;;
        list)    lease_list ;;
        reconcile) lease_reconcile ;;
      esac
      ;;
    suggest)
      partition_suggest "${1:?base}" "${2:?branch}" "${3:-$PWD}"
      ;;
    drift-check)
      partition_drift_check "$@"
      ;;
    overlaps)
      owns_overlaps "$1" "$2" "${3:-$PWD}"
      ;;
    *)
      printf 'Usage: %s check <ticket.md> [repo] | lease acquire|release|list|reconcile | suggest <base> <branch> [repo] | drift-check <ticket> <owns> <base> <head> [repo]\n' "$0" >&2
      exit 1 ;;
  esac
fi
