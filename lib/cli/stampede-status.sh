#!/usr/bin/env bash
# lib/cli/stampede-status.sh — `stampede status --rich` (PUB-11)
#
# Session trust dashboard: pure read-only aggregation over the state the
# herd already wrote — telemetry traces (PUB-10 schema), the supervisor's
# session-verdicts.jsonl, and the arbiter queue. No new emit points, no
# writes, no network. Missing artifacts (fresh clone) are a friendly empty
# state with exit 0 — empty is not an error.
#
# Every number on screen traces to a record (M3): tickets by verdict come
# from the verdicts JSONL (latest record per ticket wins), gate durations
# from trace `suite.verdict` events carrying `gate.duration_ms` (absence
# is never averaged — PUB-10 absence semantics), integrations from the
# arbiter queue, re-verdicts from the verdicts (ticket) history:
#   ratio = (verdict records - distinct tickets) / verdict records
#
# Output: one ANSI table for humans; --json names its sources for
# scripting. The human table is rendered FROM the same JSON object the
# --json mode prints, so the two can never disagree.

set -euo pipefail

# _status_read_jsonl FILE → the file's records as one JSON array ([] when
# absent). Resilient to torn trailing lines: fromjson? drops garbage
# instead of aborting the whole aggregation.
_status_read_jsonl() {
  local f="$1"
  [[ -f "$f" ]] || { printf '[]\n'; return 0; }
  jq -R -s 'split("\n") | map(select(length > 0) | (fromjson? // empty))' "$f" 2>/dev/null || printf '[]\n'
}

# _status_read_traces DIR → every event across all session files, as one
# JSON array ([] when absent).
_status_read_traces() {
  local d="$1"
  [[ -d "$d" ]] || { printf '[]\n'; return 0; }
  [[ -n "$(find "$d" -maxdepth 1 -type f -name '*.jsonl' -print -quit 2>/dev/null)" ]] \
    || { printf '[]\n'; return 0; }
  find "$d" -maxdepth 1 -type f -name '*.jsonl' -print0 2>/dev/null \
    | xargs -0 cat 2>/dev/null \
    | jq -R -s 'split("\n") | map(select(length > 0) | (fromjson? // empty))' 2>/dev/null \
    || printf '[]\n'
}

# _status_iso EPOCH → ISO-8601 UTC, portable across BSD/GNU date.
_status_iso() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || printf '?'
}

stampede_cmd_status() {
  local root config dir="" json=0
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  config="${STAMPEDE_CONFIG:-$root/swarm.config.toml}"

  while (( $# > 0 )); do
    case "$1" in
      --rich) : ;;   # the dashboard IS the rich form; --json switches renderer
      --json) json=1 ;;
      -h|--help)
        cat <<'EOF'
Usage: stampede status --rich [--json] [dir]

Read-only session trust dashboard: tickets by verdict, gate runs and
durations, integrations enqueued/promoted, per-seat and per-provider
activity, and the re-verdict ratio — aggregated from .herdr-swarm/traces/,
session-verdicts.jsonl, and the arbiter queue. A fresh clone with no
artifacts prints a friendly empty state and exits 0.

  --json    machine-readable output; names its sources
  dir       target repo (default: $PWD, or $REPO_DIR)
EOF
        return 0
        ;;
      --*) printf 'status: unknown flag: %s\n' "$1" >&2; return 1 ;;
      *)  dir="$1" ;;
    esac
    shift
  done

  local repo="${dir:-${REPO_DIR:-$PWD}}"
  local state="$repo/.herdr-swarm"
  local traces_dir="$state/traces"
  local verdicts_file="$state/session-verdicts.jsonl"
  local queue_file="$state/integration.jsonl"

  # Sources are named (done-criteria): the path when present, JSON null
  # when not. All three null → friendly empty state.
  local src_traces="null" src_verdicts="null" src_queue="null"
  if [[ -d "$traces_dir" ]]; then src_traces="\"$traces_dir\""; fi
  if [[ -f "$verdicts_file" ]]; then src_verdicts="\"$verdicts_file\""; fi
  if [[ -f "$queue_file" ]]; then src_queue="\"$queue_file\""; fi
  local is_empty="true"
  if [[ "$src_traces" != "null" || "$src_verdicts" != "null" || "$src_queue" != "null" ]]; then
    is_empty="false"
  fi

  # ── aggregate (every value below traces to a record) ──────────────────────
  local vjson tjson qjson sessions_json="[]"
  vjson=$(_status_read_jsonl "$verdicts_file")
  tjson=$(_status_read_traces "$traces_dir")
  qjson=$(_status_read_jsonl "$queue_file")
  if [[ -d "$traces_dir" ]]; then
    sessions_json=$(find "$traces_dir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null \
      | sed -E 's|.*/||; s|\.jsonl$||' \
      | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null) || sessions_json="[]"
  fi

  local tickets_json gates_json integration_json seats_json providers_json="[]" reverdicts_json

  # Seat → kind chains come from the PUB-2 registry (config enumeration).
  # Best-effort: without a resolvable interpreter or config the dashboard
  # degrades to kinds "-" and no provider rollup, never fails — a read-only
  # report must not hard-fail on the one missing input.
  local kinds_map="{}" pyok=0
  # shellcheck disable=SC1091  # sibling libs resolved from orchestrator root
  source "$root/lib/pyenv.sh"
  # shellcheck disable=SC1091
  source "$root/lib/providers.sh"
  if resolve_python >/dev/null 2>&1 && [[ -f "$config" ]]; then
    kinds_map=$(providers_seats_from_config "$config" 2>/dev/null \
      | jq -R -n 'reduce inputs as $l ({};
          ($l | split("|")) as $p
          | if ($p | length) == 4 and $p[2] == "1" then .[$p[0]] = $p[1] else . end)' 2>/dev/null) || kinds_map="{}"
    pyok=1
  fi

  tickets_json=$(jq -c '
    [ .[] | {t: (.ticket | tostring), s: (.suite // "other"), ts: (.ts // 0)} ]
    | group_by(.t)
    | map(sort_by(.ts) | last | .s) as $latest
    | {
        green:   ([$latest[] | select(. == "green")] | length),
        red:     ([$latest[] | select(. == "RED")] | length),
        skipped: ([$latest[] | select(. == "skipped")] | length),
        other:   ([$latest[] | select(. != "green" and . != "RED" and . != "skipped")] | length),
        total:   ($latest | length)
      }' <<<"$vjson" 2>/dev/null) || tickets_json='{"green":0,"red":0,"skipped":0,"other":0,"total":0}'

  local runs_n
  runs_n=$(jq 'length' <<<"$vjson" 2>/dev/null) || runs_n=0
  gates_json=$(jq -c --argjson runs "$runs_n" '
    [ .[]
      | select(.event_type == "suite.verdict")
      | .payload["gate.duration_ms"]?
      | select(type == "number") ] as $d
    | {
        runs: $runs,
        timed_runs: ($d | length),
        avg_ms: (if ($d | length) > 0 then (($d | add) / ($d | length) | round) else null end),
        max_ms: (if ($d | length) > 0 then ($d | max) else null end)
      }' <<<"$tjson" 2>/dev/null) || gates_json='{"runs":0,"timed_runs":0,"avg_ms":null,"max_ms":null}'

  integration_json=$(jq -c '
    {
      enqueued: length,
      queued:    ([.[] | select(.status == "queued")] | length),
      integrated: ([.[] | select(.status == "integrated")] | length),
      promoted:  ([.[] | select(.status == "promoted")] | length),
      conflict:  ([.[] | select(.status == "conflict")] | length),
      integration_red: ([.[] | select(.status == "integration_red")] | length)
    }' <<<"$qjson" 2>/dev/null) || integration_json='{"enqueued":0,"queued":0,"integrated":0,"promoted":0,"conflict":0,"integration_red":0}'

  seats_json=$(jq -c --argjson m "$kinds_map" '
    [ .[] | {seat: ((.seat // "?") | tostring), s: (.suite // "other"), ts: (.ts // 0)} ]
    | group_by(.seat)
    | map(.[0].seat as $sk | {
        seat: $sk,
        kinds: ($m[$sk] // "-"),
        gates: length,
        green: ([.[] | select(.s == "green")] | length),
        red:   ([.[] | select(.s == "RED")] | length),
        skipped: ([.[] | select(.s == "skipped")] | length),
        last_ts: (map(.ts) | max)
      })
    | sort_by(-.gates, .seat)' <<<"$vjson" 2>/dev/null) || seats_json='[]'

  reverdicts_json=$(jq -c '
    ([.[].ticket | tostring] | unique) as $t
    | {
        records: length,
        distinct_tickets: ($t | length),
        extra: (length - ($t | length)),
        ratio: (if length > 0 then (((((length - ($t | length)) / length) * 1000) | round) / 1000) else 0 end)
      }' <<<"$vjson" 2>/dev/null) || reverdicts_json='{"records":0,"distinct_tickets":0,"extra":0,"ratio":0}'

  # Review loop rollup (REV-4), from trace events only — every count names
  # its event source: dispatched = review.dispatched events; passes/blocks =
  # review.verdict by explicit verdict field; rerounds = review.critique
  # events (each critique initiates one re-review round); per-ticket detail
  # groups by the ticket carried in the payload.
  reviews_json=$(jq -c '
    [ .[] | select(.event_type == "review.dispatched" or .event_type == "review.verdict" or .event_type == "review.critique") ] as $rv
    | {
        total:        ([$rv[] | select(.event_type == "review.dispatched")] | length),
        passes:       ([$rv[] | select(.event_type == "review.verdict" and .payload.verdict == "PASS")] | length),
        blocks:       ([$rv[] | select(.event_type == "review.verdict" and .payload.verdict == "BLOCK")] | length),
        rerounds:     ([$rv[] | select(.event_type == "review.critique")] | length),
        findings_total: ([$rv[] | select(.event_type == "review.verdict") | .payload.findings_count? | select(type == "number")] | add // 0),
        tickets: (
          [ $rv[] | (.payload.ticket // .ticket_num // "?") as $t | {t: ($t | tostring), e: .event_type, r: (.payload.round // 0)} ]
          | group_by(.t)
          | map({
              ticket: .[0].t,
              rounds: (map(.r) | max),
              verdicts: ([.[] | select(.e == "review.verdict")] | length),
              critiques: ([.[] | select(.e == "review.critique")] | length)
            })
          | sort_by(.ticket)
        )
      }' <<<"$tjson" 2>/dev/null) || reviews_json='{"total":0,"passes":0,"blocks":0,"rerounds":0,"findings_total":0,"tickets":[]}'

  # Per-provider rollup: seats rolled to their primary kind (first of the
  # configured chain). Only when the registry join above succeeded.
  if [[ "$pyok" == "1" && "$kinds_map" != "{}" ]]; then
    providers_json=$(jq -c --argjson m "$kinds_map" '
      [ .[] | {seat: ((.seat // "?") | tostring)} ]
      | group_by(.seat)
      | map(.[0].seat as $sk | {seat: $sk, gates: length, kind: (($m[$sk] // "-") | split(","))[0]})
      | group_by(.kind)
      | map({kind: .[0].kind, seats: length, gates: (map(.gates) | add)})
      | sort_by(-.gates, .kind)' <<<"$vjson" 2>/dev/null) || providers_json='[]'
  fi

  # ── the single source of truth: one JSON object, both renderers read it ───
  local final
  final=$(jq -n \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson empty "$is_empty" \
    --argjson src_traces "$src_traces" \
    --argjson src_verdicts "$src_verdicts" \
    --argjson src_queue "$src_queue" \
    --arg config "$config" \
    --argjson sessions "$sessions_json" \
    --argjson tickets "$tickets_json" \
    --argjson gates "$gates_json" \
    --argjson integration "$integration_json" \
    --argjson seats "$seats_json" \
    --argjson providers "$providers_json" \
    --argjson reverdicts "$reverdicts_json" \
    --argjson reviews "$reviews_json" \
    '{
      command: "stampede status --rich",
      read_only: true,
      empty: $empty,
      generated_at: $generated_at,
      sources: {
        traces: $src_traces,
        verdicts: $src_verdicts,
        arbiter_queue: $src_queue,
        config: $config
      },
      sessions: $sessions,
      tickets: $tickets,
      gates: $gates,
      integration: $integration,
      seats: $seats,
      providers: $providers,
      reverdicts: $reverdicts,
      reviews: $reviews
    }')

  if (( json )); then
    printf '%s\n' "$final"
    return 0
  fi

  # ── human table (rendered FROM $final — it cannot disagree with --json) ───
  local DIM="" RESET="" BOLD="" GREEN="" RED="" YELLOW=""
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    DIM=$(tput dim 2>/dev/null || printf ''); RESET=$(tput sgr0 2>/dev/null || printf '')
    BOLD=$(tput bold 2>/dev/null || printf ''); GREEN=$(tput setaf 2 2>/dev/null || printf '')
    RED=$(tput setaf 1 2>/dev/null || printf ''); YELLOW=$(tput setaf 3 2>/dev/null || printf '')
  fi

  printf '%bstampede status%s — session trust dashboard (read-only)\n\n' "$BOLD" "$RESET"
  if [[ "$is_empty" == "true" ]]; then
    printf '  Nothing to report yet — no swarm state at %s%s%s.\n\n' "$DIM" "$state" "$RESET"
    printf '  Run %sstampede up%s to seat the swarm, then work tickets;\n' "$BOLD" "$RESET"
    printf '  this dashboard fills from traces, verdicts, and the arbiter queue.\n'
    printf '  See docs/user-guide.md for the walkthrough.\n'
    return 0
  fi

  printf '  %bdir%s        %s\n' "$DIM" "$RESET" "$repo"
  printf '  %bsources%s   traces=%s verdicts=%s arbiter_queue=%s\n' \
    "$DIM" "$RESET" "$src_traces" "$src_verdicts" "$src_queue"
  printf '  %bsessions%s  %s\n\n' "$DIM" "$RESET" \
    "$(jq -r '.sessions | if length == 0 then "(none)" else join(", ") end' <<<"$final")"

  local g r s o tot
  g=$(jq -r '.tickets.green' <<<"$final"); r=$(jq -r '.tickets.red' <<<"$final")
  s=$(jq -r '.tickets.skipped' <<<"$final"); o=$(jq -r '.tickets.other' <<<"$final")
  tot=$(jq -r '.tickets.total' <<<"$final")
  printf '  %btickets%s    %sgreen%s %s · %sred%s %s · skipped %s · other %s  (%s with a verdict)\n' \
    "$BOLD" "$RESET" "$GREEN" "$RESET" "$g" "$RED" "$RESET" "$r" "$s" "$o" "$tot"

  local runs timed avg mx gdetail
  runs=$(jq -r '.gates.runs' <<<"$final"); timed=$(jq -r '.gates.timed_runs' <<<"$final")
  if [[ "$timed" -gt 0 ]]; then
    avg=$(jq -r '.gates.avg_ms // "untimed"' <<<"$final"); mx=$(jq -r '.gates.max_ms // "untimed"' <<<"$final")
    gdetail="avg ${avg}ms, max ${mx}ms"
  else
    gdetail="none timed (no gate.duration_ms in traces)"
  fi
  printf '  %bgates%s     %s suite runs (%s timed: %s)\n' \
    "$BOLD" "$RESET" "$runs" "$timed" "$gdetail"

  local en qn in_ pr cf rd
  en=$(jq -r '.integration.enqueued' <<<"$final"); qn=$(jq -r '.integration.queued' <<<"$final")
  in_=$(jq -r '.integration.integrated' <<<"$final"); pr=$(jq -r '.integration.promoted' <<<"$final")
  cf=$(jq -r '.integration.conflict' <<<"$final"); rd=$(jq -r '.integration.integration_red' <<<"$final")
  printf '  %barbiter%s   enqueued %s · queued %s · %sintegrated%s %s · promoted %s · %sconflict%s %s · red %s\n' \
    "$BOLD" "$RESET" "$en" "$qn" "$GREEN" "$RESET" "$in_" "$pr" "$YELLOW" "$RESET" "$cf" "$rd"

  # Review loop line (REV-4): rendered only when review events exist —
  # a herd without the reviewer seat must not print a wall of zeros that
  # reads as "reviews happened and all were empty".
  local rt rp rb rr
  rt=$(jq -r '.reviews.total' <<<"$final"); rp=$(jq -r '.reviews.passes' <<<"$final")
  rb=$(jq -r '.reviews.blocks' <<<"$final"); rr=$(jq -r '.reviews.rerounds' <<<"$final")
  if [[ "$rt" -gt 0 || "$rp" -gt 0 || "$rb" -gt 0 || "$rr" -gt 0 ]]; then
    printf '  %breviews%s    dispatched %s · %spass%s %s · %sblock%s %s · re-rounds %s\n' \
      "$BOLD" "$RESET" "$rt" "$GREEN" "$RESET" "$rp" "$RED" "$RESET" "$rb" "$rr"
    local rv_ticket rv_rounds rv_verdicts rv_crit
    while IFS=$'\t' read -r rv_ticket rv_rounds rv_verdicts rv_crit; do
      printf '    %-16s rounds %s · verdicts %s · critiques %s\n' \
        "$rv_ticket" "$rv_rounds" "$rv_verdicts" "$rv_crit"
    done < <(jq -r '.reviews.tickets[] | [.ticket, (.rounds|tostring), (.verdicts|tostring), (.critiques|tostring)] | @tsv' <<<"$final")
  fi

  local seat kind kgates kg kr ks klast
  if [[ "$(jq '.seats | length' <<<"$final")" -gt 0 ]]; then
    printf '\n  %-14s %-22s %5s %5s %4s %5s  %s\n' "SEAT" "KIND" "GATES" "GREEN" "RED" "SKIP" "LAST"
    while IFS=$'\t' read -r seat kind kgates kg kr ks klast; do
      printf '  %-14s %-22s %5s %5s %4s %5s  %s\n' \
        "$seat" "$kind" "$kgates" "$kg" "$kr" "$ks" "$(_status_iso "$klast")"
    done < <(jq -r '.seats[] | [.seat, .kinds, (.gates|tostring), (.green|tostring), (.red|tostring), (.skipped|tostring), (.last_ts|tostring)] | @tsv' <<<"$final")
  else
    printf '\n  no verdict records yet\n'
  fi

  if [[ "$(jq '.providers | length' <<<"$final")" -gt 0 ]]; then
    printf '\n  %-10s %5s %5s\n' "PROVIDER" "SEATS" "GATES"
    while IFS=$'\t' read -r pk ps pg; do
      printf '  %-10s %5s %5s\n' "$pk" "$ps" "$pg"
    done < <(jq -r '.providers[] | [.kind, (.seats|tostring), (.gates|tostring)] | @tsv' <<<"$final")
  fi

  local rec dis extra pct
  rec=$(jq -r '.reverdicts.records' <<<"$final"); dis=$(jq -r '.reverdicts.distinct_tickets' <<<"$final")
  extra=$(jq -r '.reverdicts.extra' <<<"$final"); pct=$(jq -r '.reverdicts.ratio * 100' <<<"$final")
  printf '\n  %bre-verdicts%s %s extra / %s records (%s distinct tickets) = %s%% of records were re-verdicts\n' \
    "$BOLD" "$RESET" "$extra" "$rec" "$dis" "$(printf '%.1f' "$pct")"
  printf '  %bformula%s (records - distinct tickets) / records, from session-verdicts.jsonl history\n' "$DIM" "$RESET"
  return 0
}
