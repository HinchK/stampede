#!/usr/bin/env bash
# lib/gh_sync.sh — GitHub Issues Two-Way Synchronization Tooling
# Prototype for Ticket: T-017 (GitHub Issues Two-Way Synchronization Protocol & Tooling)
#
# Synchronizes local Markdown tickets in maps/tickets/*.md with upstream GitHub Issues.
#
# Invariants:
#   - Local-first single source of truth for architectural tickets and criteria.
#   - Fail-closed: refuses to execute if gh is unauthenticated or repo is unknown.
#   - Zero unconfirmed writes: defaults to --dry-run; requires --apply to write.
#   - YAML frontmatter anchors: persists github_issue and github_url into ticket frontmatter.
#
# Usage:
#   ./lib/gh_sync.sh [--dry-run] [--apply] [--repo OWNER/REPO] [--target-dir DIR]
#                    [--direction push|pull|both] [--ticket ID_OR_FILE] [--json]

set -euo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_LIB_DIR}/common.sh"
# shellcheck disable=SC1091  # tomllib-capable interpreter (DOG-1)
source "${SCRIPT_LIB_DIR}/pyenv.sh"
resolve_python
# shellcheck disable=SC1091
source "${SCRIPT_LIB_DIR}/profile.sh"

# Terminal formatting
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true); YELLOW=$(tput setaf 3 2>/dev/null || true)
  RED=$(tput setaf 1 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)
  DIM=$(tput dim 2>/dev/null || true)
else
  BOLD=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; DIM=""
fi

show_help() {
  cat << EOF
${BOLD}Universal Swarm — GitHub Issues Two-Way Synchronization Tooling (T-017)${RESET}

${BOLD}USAGE:${RESET}
  lib/gh_sync.sh [OPTIONS]

${BOLD}OPTIONS:${RESET}
  --dry-run              Preview planned synchronization actions without making changes (DEFAULT)
  --apply, --sync        Execute planned changes (create/update remote issues and update frontmatter)
  --repo <OWNER/REPO>    Explicit GitHub repository slug (e.g. 'org/repo'). Overrides git remote detection
  --target-dir <DIR>     Target repository directory containing maps/tickets/ (default: \$PWD)
  --direction <DIR>      Sync direction: push | pull | both (default: push)
  --ticket <ID_OR_FILE>  Restrict sync to a specific ticket ID (e.g. T-017) or file path
  --json                 Output machine-readable JSON sync plan
  --quiet                Suppress decorative headers and non-essential output
  --help, -h             Show this help message

${BOLD}FAIL-CLOSED POLICY:${RESET}
  This tool refuses to operate without:
  1. An installed and responsive 'gh' CLI binary.
  2. A verified GitHub authentication session ('gh auth status').
  3. A verified canonical repository slug from git remotes, profile.env, or --repo.
EOF
}

# ── Parse Arguments ────────────────────────────────────────────────────────
TARGET_DIR="$PWD"
REPO=""
DRY_RUN=true
APPLY=false
DIRECTION="push"
TICKET_FILTER=""
OUTPUT_JSON=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      APPLY=false
      shift
      ;;
    --apply|--sync)
      APPLY=true
      DRY_RUN=false
      shift
      ;;
    --repo)
      if [[ $# -lt 2 ]]; then
        echo "${RED}ERROR: --repo requires an argument (OWNER/REPO)${RESET}" >&2
        exit 1
      fi
      REPO="$2"
      shift 2
      ;;
    --target-dir)
      if [[ $# -lt 2 ]]; then
        echo "${RED}ERROR: --target-dir requires an argument${RESET}" >&2
        exit 1
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    --direction)
      if [[ $# -lt 2 ]]; then
        echo "${RED}ERROR: --direction requires an argument (push|pull|both)${RESET}" >&2
        exit 1
      fi
      DIRECTION="$2"
      shift 2
      ;;
    --ticket)
      if [[ $# -lt 2 ]]; then
        echo "${RED}ERROR: --ticket requires an argument${RESET}" >&2
        exit 1
      fi
      TICKET_FILTER="$2"
      shift 2
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      if [[ -d "$1" ]]; then
        if [[ "$1" == "maps/tickets" || "$1" == */maps/tickets || "$1" == "maps/tickets/" || "$1" == */maps/tickets/ ]]; then
          TARGET_DIR="$(cd "$1/../.." && pwd)"
        else
          TARGET_DIR="$(cd "$1" && pwd)"
        fi
        shift
      elif [[ -f "$1" || "$1" =~ ^[A-Za-z0-9_-]+$ ]]; then
        TICKET_FILTER="$1"
        shift
      else
        echo "${RED}ERROR: Unknown option or path '$1'${RESET}" >&2
        echo "Run 'lib/gh_sync.sh --help' for available options." >&2
        exit 1
      fi
      ;;
  esac
done

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "${RED}ERROR: Target directory does not exist: $TARGET_DIR${RESET}" >&2
  exit 1
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# ── Preflight & Fail-Closed Validations ────────────────────────────────────

# 1. gh binary check
if ! command -v gh >/dev/null 2>&1; then
  echo "${RED}ERROR: GitHub CLI ('gh') is not installed or not in PATH.${RESET}" >&2
  echo "" >&2
  echo "${BOLD}Fail-Closed Policy:${RESET} Cannot synchronize GitHub issues without 'gh'." >&2
  echo "Remediation: Install GitHub CLI via 'brew install gh' or https://cli.github.com" >&2
  exit 1
fi

# 2. gh auth check
if ! gh auth status >/dev/null 2>&1; then
  echo "${RED}ERROR: GitHub CLI is not authenticated.${RESET}" >&2
  echo "" >&2
  echo "${BOLD}Fail-Closed Policy:${RESET} Cannot query or mutate remote issues without valid authentication." >&2
  echo "Remediation: Run 'gh auth login' to establish an authenticated GitHub session." >&2
  exit 1
fi

# 3. Canonical repository resolution
if [[ -z "$REPO" ]]; then
  DETECTED_REPO=$(detect_repo "$TARGET_DIR" 2>/dev/null || true)
  if [[ -n "$DETECTED_REPO" ]]; then
    REPO="$DETECTED_REPO"
  else
    echo "${RED}ERROR: No canonical GitHub repository detected for ${TARGET_DIR}.${RESET}" >&2
    echo "" >&2
    echo "${BOLD}Fail-Closed Policy:${RESET} Cannot synchronize issues without a verified GitHub remote." >&2
    echo "Remediation:" >&2
    echo "  1. Add a git remote in the target repository:" >&2
    echo "     git -C \"$TARGET_DIR\" remote add origin git@github.com:OWNER/REPO.git" >&2
    echo "  2. Or record REPO in ${TARGET_DIR}/.herdr-swarm/profile.env:" >&2
    echo "     REPO=\"owner/repo\"" >&2
    echo "  3. Or pass an explicit repository flag:" >&2
    echo "     lib/gh_sync.sh --repo OWNER/REPO [options]" >&2
    exit 1
  fi
fi

if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "${RED}ERROR: Invalid repository slug format: '$REPO'${RESET}" >&2
  echo "Expected format: OWNER/REPO (e.g. 'Standard-Pentest/kultivait' or 'HinchK/loop-bot-herd-agy')" >&2
  exit 1
fi

# 4. Tickets directory check
TICKETS_DIR="${TARGET_DIR}/maps/tickets"
if [[ ! -d "$TICKETS_DIR" ]]; then
  echo "${RED}ERROR: Maps tickets directory not found: $TICKETS_DIR${RESET}" >&2
  echo "Remediation: Verify TARGET_DIR points to a repository with 'maps/tickets/'." >&2
  exit 1
fi

# ── Query Remote GitHub Issues ─────────────────────────────────────────────
if [[ "$QUIET" = false && "$OUTPUT_JSON" = false ]]; then
  printf "%s=== Universal Swarm: GitHub Issues Sync ===%s\n" "$BOLD" "$RESET"
  printf "Target Directory : %s\n" "$TARGET_DIR"
  printf "GitHub Repo      : %s%s%s\n" "$CYAN" "$REPO" "$RESET"
  printf "Mode             : %s\n" "$([ "$DRY_RUN" = true ] && printf "%sDRY-RUN (safe, zero unconfirmed writes)%s" "$GREEN" "$RESET" || printf "%sAPPLY (destructive updates enabled)%s" "$YELLOW" "$RESET")"
  printf "Direction        : %s\n" "$DIRECTION"
  printf "\nQuerying remote issues for %s...\n" "$REPO"
fi

REMOTE_ISSUES_JSON=""
if ! REMOTE_ISSUES_JSON=$(gh issue list --repo "$REPO" --limit 300 --state all --json number,title,state,stateReason,labels,url 2>&1); then
  echo "${RED}ERROR: Failed to query GitHub issues for '$REPO'.${RESET}" >&2
  echo "GitHub CLI response:" >&2
  echo "$REMOTE_ISSUES_JSON" >&2
  echo "" >&2
  echo "Remediation: Ensure repository '$REPO' exists and your GitHub token has 'repo' scope." >&2
  exit 1
fi

# ── Python Reconciliation Engine ───────────────────────────────────────────
RECONCILE_OUTPUT=$("$PYTHON_BIN" -c '
import sys, os, glob, re, json

target_dir = sys.argv[1]
tickets_dir = os.path.join(target_dir, "maps", "tickets")
repo = sys.argv[2]
remote_json_str = sys.argv[3]
direction = sys.argv[4]
ticket_filter = sys.argv[5].strip()
is_apply = (sys.argv[6] == "true")

try:
    remote_issues = json.loads(remote_json_str)
except Exception as e:
    sys.stderr.write(f"Failed to parse remote issues JSON: {e}\n")
    sys.exit(1)

# Index remote issues
remote_by_number = {issue["number"]: issue for issue in remote_issues}
remote_by_ticket_id = {}
for issue in remote_issues:
    m = re.match(r"^\[([A-Za-z0-9_-]+)\]", issue.get("title", ""))
    if m:
        t_id = m.group(1)
        remote_by_ticket_id[t_id] = issue

# Discover local tickets
ticket_files = sorted(glob.glob(os.path.join(tickets_dir, "*.md")))
local_tickets = []

for tf in ticket_files:
    rel_path = os.path.relpath(tf, target_dir)
    fname = os.path.basename(tf)
    
    with open(tf, "r", encoding="utf-8") as f:
        content = f.read()
    
    m = re.match(r"^---\n(.*?)\n---\n?(.*)", content, re.DOTALL)
    if not m:
        continue
    
    fm_raw, body = m.groups()
    fm = {}
    for line in fm_raw.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip().strip("\"").strip("\x27")
            fm[k] = v
            
    t_id = fm.get("id", "")
    t_title = fm.get("title", fname)
    t_status = fm.get("status", "in_progress").lower()
    t_type = fm.get("type", "wayfinder:task")
    t_assignee = fm.get("assignee", "")
    t_gh_num = fm.get("github_issue", "")
    t_gh_url = fm.get("github_url", "")
    t_synced_at = fm.get("synced_at", "")
    
    gh_int = int(t_gh_num) if t_gh_num and t_gh_num.isdigit() else None
    
    ticket_data = {
        "file_path": tf,
        "rel_path": rel_path,
        "id": t_id,
        "title": t_title,
        "status": t_status,
        "type": t_type,
        "assignee": t_assignee,
        "github_issue": gh_int,
        "github_url": t_gh_url,
        "synced_at": t_synced_at,
        "body": body,
        "fm_raw": fm_raw
    }
    
    if ticket_filter:
        filters = [f.strip() for f in ticket_filter.split(",") if f.strip()]
        matched = False
        for f in filters:
            if f == t_id or f in tf or t_id.startswith(f + "-") or (f.endswith("*") and t_id.startswith(f[:-1])):
                matched = True
                break
        if not matched:
            continue
            
    local_tickets.append(ticket_data)

# Compute Reconciliation Plan
plan_items = []
summary = {"create": 0, "link": 0, "update_remote": 0, "update_local": 0, "in_sync": 0, "total": len(local_tickets)}

for t in local_tickets:
    t_id = t["id"]
    t_num = t["github_issue"]
    t_st = t["status"]
    t_ti = t["title"]
    
    # Case 1: Linked to remote issue number
    if t_num is not None:
        remote_issue = remote_by_number.get(t_num)
        if not remote_issue:
            plan_items.append({
                "action": "WARN_MISSING",
                "ticket_id": t_id,
                "title": t_ti,
                "file": t["rel_path"],
                "github_issue": t_num,
                "detail": f"Local ticket references remote #{t_num}, but #{t_num} was not found on remote."
            })
            continue
            
        r_state = remote_issue.get("state", "OPEN").upper()
        local_is_closed = t_st in ("resolved", "closed", "done")
        remote_is_closed = (r_state == "CLOSED")
        
        if local_is_closed and not remote_is_closed:
            plan_items.append({
                "action": "UPDATE_REMOTE",
                "subaction": "close",
                "ticket_id": t_id,
                "title": t_ti,
                "file": t["rel_path"],
                "github_issue": t_num,
                "detail": f"Local status is \"{t_st}\", but remote #{t_num} is OPEN -> Close remote issue."
            })
            summary["update_remote"] += 1
        elif not local_is_closed and remote_is_closed:
            if direction in ("pull", "both"):
                plan_items.append({
                    "action": "UPDATE_LOCAL",
                    "subaction": "resolve",
                    "ticket_id": t_id,
                    "title": t_ti,
                    "file": t["rel_path"],
                    "github_issue": t_num,
                    "detail": f"Remote #{t_num} was closed on GitHub -> Update local status to \"resolved\"."
                })
                summary["update_local"] += 1
            else:
                plan_items.append({
                    "action": "UPDATE_REMOTE",
                    "subaction": "reopen",
                    "ticket_id": t_id,
                    "title": t_ti,
                    "file": t["rel_path"],
                    "github_issue": t_num,
                    "detail": f"Local status is active (\"{t_st}\"), but remote #{t_num} is CLOSED -> Reopen remote issue."
                })
                summary["update_remote"] += 1
        else:
            plan_items.append({
                "action": "IN_SYNC",
                "ticket_id": t_id,
                "title": t_ti,
                "file": t["rel_path"],
                "github_issue": t_num,
                "detail": f"Local and remote #{t_num} states match ({r_state})."
            })
            summary["in_sync"] += 1
            
    # Case 2: Unlinked (github_issue is empty)
    else:
        matched_remote = remote_by_ticket_id.get(t_id)
        if matched_remote:
            r_num = matched_remote["number"]
            r_url = matched_remote.get("url", f"https://github.com/{repo}/issues/{r_num}")
            plan_items.append({
                "action": "LINK",
                "ticket_id": t_id,
                "title": t_ti,
                "file": t["rel_path"],
                "github_issue": r_num,
                "github_url": r_url,
                "detail": f"Found existing remote issue #{r_num} matching title prefix [{t_id}]."
            })
            summary["link"] += 1
        else:
            plan_items.append({
                "action": "CREATE",
                "ticket_id": t_id,
                "title": t_ti,
                "file": t["rel_path"],
                "detail": f"Create new GitHub issue: \"[{t_id}] {t_ti}\"."
            })
            summary["create"] += 1

output = {
    "repo": repo,
    "target_dir": target_dir,
    "direction": direction,
    "is_apply": is_apply,
    "summary": summary,
    "items": plan_items,
    "tickets": local_tickets
}
print(json.dumps(output))
' "$TARGET_DIR" "$REPO" "$REMOTE_ISSUES_JSON" "$DIRECTION" "$TICKET_FILTER" "$APPLY")

if [[ "$OUTPUT_JSON" = true ]]; then
  printf "%s\n" "$RECONCILE_OUTPUT"
  exit 0
fi

# ── Render Plan ────────────────────────────────────────────────────────────
"$PYTHON_BIN" -c '
import sys, json

data = json.loads(sys.argv[1])
bold = sys.argv[2]
reset = sys.argv[3]
green = sys.argv[4]
yellow = sys.argv[5]
red = sys.argv[6]
cyan = sys.argv[7]
dim = sys.argv[8]

items = data["items"]
summary = data["summary"]
is_apply = data["is_apply"]

total_count = summary["total"]
print(f"\n{bold}Discovered Tickets:{reset} {total_count} local ticket(s) in maps/tickets/\n")
print(f"{bold}Planned Synchronization Actions:{reset}")

for item in items:
    action = item["action"]
    t_id = item["ticket_id"]
    title = item["title"]
    detail = item["detail"]
    gh_num = item.get("github_issue", "")
    
    if action == "CREATE":
        badge = f"{green}[CREATE]{reset}"
        print(f"  {badge}  {bold}{t_id}{reset} -> {title}")
        print(f"            {dim}{detail}{reset}")
    elif action == "LINK":
        badge = f"{cyan}[LINK]{reset}  "
        print(f"  {badge}  {bold}{t_id}{reset} -> #{gh_num} {title}")
        print(f"            {dim}{detail}{reset}")
    elif action == "UPDATE_REMOTE":
        badge = f"{yellow}[UPDATE]{reset}"
        print(f"  {badge}  {bold}{t_id}{reset} (remote #{gh_num})")
        print(f"            {dim}{detail}{reset}")
    elif action == "UPDATE_LOCAL":
        badge = f"{yellow}[PULL]{reset}  "
        print(f"  {badge}  {bold}{t_id}{reset} (local status update)")
        print(f"            {dim}{detail}{reset}")
    elif action == "IN_SYNC":
        badge = f"{dim}[IN_SYNC]{reset}"
        print(f"  {badge} {t_id} (remote #{gh_num}) — {detail}")
    elif action == "WARN_MISSING":
        badge = f"{red}[WARN]{reset}   "
        print(f"  {badge} {t_id} -> {detail}")

to_create = summary["create"]
to_link = summary["link"]
to_update = summary["update_remote"] + summary["update_local"]
in_sync = summary["in_sync"]

print(f"\n{bold}Summary:{reset}")
print(f"  To Create : {to_create}")
print(f"  To Link   : {to_link}")
print(f"  To Update : {to_update}")
print(f"  In Sync   : {in_sync}")
print(f"  Total     : {total_count}")

if not is_apply:
    print(f"\n{green}{bold}DRY RUN:{reset} {green}No remote GitHub changes or local file writes were executed.{reset}")
    print(f"Pass {bold}--apply{reset} to execute these operations.")
' "$RECONCILE_OUTPUT" "$BOLD" "$RESET" "$GREEN" "$YELLOW" "$RED" "$CYAN" "$DIM"

# ── Execute Plan (Only if --apply) ─────────────────────────────────────────
if [[ "$APPLY" = true ]]; then
  echo ""
  echo "${YELLOW}${BOLD}Applying Synchronization Actions...${RESET}"

  # Python applier script handles atomic frontmatter edits and triggers gh CLI mutations
  # shellcheck disable=SC2016
  "$PYTHON_BIN" -c '
import sys, os, re, json, subprocess, datetime

data = json.loads(sys.argv[1])
target_dir = sys.argv[2]
repo = sys.argv[3]

def update_frontmatter(file_path, updates):
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()
    m = re.match(r"^---\n(.*?)\n---\n?(.*)", content, re.DOTALL)
    if not m:
        return
    fm_raw, body = m.groups()
    lines = fm_raw.splitlines()
    new_lines = []
    seen = set()
    for line in lines:
        if ":" in line:
            k = line.split(":", 1)[0].strip()
            if k in updates:
                seen.add(k)
                v = updates[k]
                if isinstance(v, int):
                    new_lines.append(f"{k}: {v}")
                elif v is None:
                    continue
                else:
                    new_lines.append(f"{k}: \"{v}\"")
                continue
        new_lines.append(line)
    for k, v in updates.items():
        if k not in seen and v is not None:
            if isinstance(v, int):
                new_lines.append(f"{k}: {v}")
            else:
                new_lines.append(f"{k}: \"{v}\"")
    nl = "\n"
    new_content = f"---\n{nl.join(new_lines)}\n---\n{body}"
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(new_content)

now_iso = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

for item in data["items"]:
    action = item["action"]
    t_id = item["ticket_id"]
    t_file = os.path.join(target_dir, item["file"])
    
    if action == "LINK":
        gh_num = item["github_issue"]
        gh_url = item["github_url"]
        update_frontmatter(t_file, {
            "github_issue": gh_num,
            "github_url": gh_url,
            "synced_at": now_iso
        })
        print(f"✓ Linked {t_id} -> #{gh_num}")
        
    elif action == "CREATE":
        t_obj = next((t for t in data["tickets"] if t["id"] == t_id), None)
        if not t_obj:
            continue
        t_ti = t_obj["title"]
        title = f"[{t_id}] {t_ti}"
        t_rel = t_obj["rel_path"]
        t_typ = t_obj["type"]
        t_st = t_obj["status"]
        t_bdy = t_obj["body"]
        body = f"# [{t_id}] {t_ti}\n\n" \
               f"**Local Ticket:** `{t_rel}`\n" \
               f"**Type:** `{t_typ}` · **Status:** `{t_st}`\n\n---\n\n" \
               f"{t_bdy}"
        
        # Build labels
        labels = ["swarm:ticket"]
        if "prototype" in t_typ:
            labels.append("type:prototype")
        elif "milestone" in t_typ:
            labels.append("type:milestone")
        elif "task" in t_typ:
            labels.append("type:task")
            
        cmd = [
            "gh", "issue", "create",
            "--repo", repo,
            "--title", title,
            "--body", body
        ]
        for lbl in labels:
            cmd.extend(["--label", lbl])
            
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            url = res.stdout.strip()
            m_num = re.search(r"/issues/(\d+)$", url)
            gh_num = int(m_num.group(1)) if m_num else None
            
            update_frontmatter(t_file, {
                "github_issue": gh_num,
                "github_url": url,
                "synced_at": now_iso
            })
            print(f"✓ Created remote issue #{gh_num} ({url}) for {t_id}")
        except subprocess.CalledProcessError as e:
            sys.stderr.write(f"✗ Failed to create remote issue for {t_id}: {e.stderr}\n")

    elif action == "UPDATE_REMOTE":
        gh_num = item["github_issue"]
        sub = item.get("subaction", "")
        if sub == "close":
            cmd = ["gh", "issue", "close", str(gh_num), "--repo", repo, "--reason", "completed"]
            try:
                subprocess.run(cmd, capture_output=True, text=True, check=True)
                update_frontmatter(t_file, {"synced_at": now_iso})
                print(f"✓ Closed remote issue #{gh_num} for {t_id}")
            except subprocess.CalledProcessError as e:
                sys.stderr.write(f"✗ Failed to close #{gh_num}: {e.stderr}\n")
        elif sub == "reopen":
            cmd = ["gh", "issue", "reopen", str(gh_num), "--repo", repo]
            try:
                subprocess.run(cmd, capture_output=True, text=True, check=True)
                update_frontmatter(t_file, {"synced_at": now_iso})
                print(f"✓ Reopened remote issue #{gh_num} for {t_id}")
            except subprocess.CalledProcessError as e:
                sys.stderr.write(f"✗ Failed to reopen #{gh_num}: {e.stderr}\n")
                
    elif action == "UPDATE_LOCAL":
        update_frontmatter(t_file, {
            "status": "resolved",
            "synced_at": now_iso
        })
        print(f"✓ Updated local status for {t_id} to resolved")
' "$RECONCILE_OUTPUT" "$TARGET_DIR" "$REPO"

  echo ""
  echo "${GREEN}${BOLD}✓ Synchronization completed successfully.${RESET}"
fi
