#!/usr/bin/env python3
"""Durable per-ticket attention policy for the bounded AGY looper."""

import argparse
from collections import deque
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import tomllib


VALID_MODES = ("quiet", "medium", "loud")
VALID_EVENTS = ("green", "new", "red", "blocked")
PAUSED_SUMMARY_LIMIT = 8
SCHEMA = json.dumps({"type": "object", "properties": {
    "action": {"enum": ["summary", "assign", "repair", "escalate"]},
    "seat": {"type": "string"}, "summary": {"type": "string"}},
    "required": ["action", "summary"], "additionalProperties": False})


# Ticket frontmatter statuses this repo uses for finished work.
TERMINAL_STATUSES = {"done", "resolved", "closed", "superseded"}


class Attention:
    def __init__(self, repo):
        self.repo = Path(repo).resolve()
        self.state_dir = self.repo / ".herdr-swarm"
        self.state_dir.mkdir(exist_ok=True)
        with (self.repo / "swarm.config.toml").open("rb") as handle:
            self.config = tomllib.load(handle)
        self.file = self.state_dir / "attention.json"
        if self.file.exists():
            self._locked(self._recover_inflight)

    def _recover_inflight(self, data):
        for ticket in set(data["inflight"].values()):
            self._pause(data, ticket, "interrupted decision: inspect seat, lease, and logs before resuming")
        data["inflight"].clear()

    def _read(self):
        if not self.file.exists():
            return {"seen": [], "paused": {}, "repairs": {}, "inflight": {}, "approved": {}, "finished": []}
        data = json.loads(self.file.read_text())
        if not isinstance(data, dict) or not isinstance(data.get("seen"), list) or not isinstance(data.get("paused"), dict):
            raise ValueError("invalid attention state; refusing to dispatch")
        data.setdefault("repairs", {})
        data.setdefault("inflight", {})
        data.setdefault("approved", {})
        if not isinstance(data.get("finished"), list):
            data["finished"] = []
        return data

    def _write(self, data):
        with tempfile.NamedTemporaryFile("w", dir=self.state_dir, prefix=".attention.", delete=False) as handle:
            json.dump(data, handle, sort_keys=True)
            handle.write("\n")
            tmp = Path(handle.name)
        os.replace(tmp, self.file)

    def _locked(self, operation):
        with (self.state_dir / "attention.lock").open("a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = self._read()
            result = operation(data)
            self._write(data)
            return result

    def mode(self):
        data = self._read()
        mode = data.get("mode", self.config.get("attention", {}).get("mode", "medium"))
        if mode not in VALID_MODES:
            raise ValueError("invalid attention mode; refusing to dispatch")
        return mode

    def set_mode(self, mode):
        if mode not in VALID_MODES:
            raise ValueError("attention mode must be quiet, medium, or loud")
        def change(data):
            data["mode"] = mode
            if mode != "quiet":
                data["seen"] = [item for item in data["seen"] if item.get("status") != "queued"]
        self._locked(change)
        return mode

    def is_paused(self, ticket):
        return ticket in self._read()["paused"]

    def resume(self, ticket):
        def change(data):
            data["paused"].pop(ticket, None)
            data["seen"] = [item for item in data["seen"] if item["ticket"] != ticket]
            # Resuming is the human's approval: loud mode lets the next decision through.
            data["approved"][ticket] = True
            # A remembered closed issue can be reopened by the same resume.
            data["finished"] = [item for item in data["finished"] if str(item) != str(ticket)]
        self._locked(change)

    def _log(self, name, message):
        with (self.state_dir / name).open("a") as handle:
            handle.write(message.replace("\n", " ")[:1000] + "\n")

    def _pause(self, data, ticket, reason):
        data["paused"][ticket] = reason[:400]
        self._log("troubleshooting.log", f"#{ticket} paused: {reason}")
        self._log("handoff.log", f"Human decision needed for #{ticket}: {reason}")
        return {"status": "paused", "reason": reason}

    def _candidates(self, architect_only=True):
        ledger = json.loads((self.state_dir / "seats.json").read_text())
        configured = [v.get("name", k).replace("_", "-") for k, v in self.config.get("seats", {}).items()
                      if (not architect_only and k != "looper") or v.get("role") == "architect"]
        return [seat for seat in ledger.get("seats", []) if seat.get("isolated") is True
                and seat.get("agentless") is not True
                and any(seat.get("name", "") == base or seat.get("name", "").startswith(base + "-")
                        for base in configured)]

    def seat_ready(self, seat):
        try:
            result = subprocess.run(["herdr", "agent", "get", seat], capture_output=True,
                                    text=True, timeout=5, check=False)
            if result.returncode:
                return False
            agent = json.loads(result.stdout).get("result", {}).get("agent", {})
            return agent.get("agent_status") in ("idle", "done", "waiting")
        except (OSError, ValueError, subprocess.TimeoutExpired):
            return False

    def profile_value(self, key):
        profile = self.state_dir / "profile.env"
        if profile.exists():
            for line in profile.read_text().splitlines():
                if line.startswith(key + "="):
                    return line[len(key) + 1:].strip().strip('"\'')
        return ""

    def github_repo(self):
        value = self.profile_value("REPO")
        if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
            return value
        raise ValueError("project profile has no GitHub repository; refusing issue dispatch")

    def gate_ready(self):
        command = self.profile_value("TEST_CMD")
        if command in ("", "none", "true"):
            return False
        control = self.state_dir / "control.json"
        return not control.exists() or json.loads(control.read_text()).get("suite_gate", True) is True

    def issue(self, ticket):
        try:
            repo = self.github_repo()
        except ValueError:
            return None
        if not str(ticket).isdigit():
            return None
        try:
            result = subprocess.run(["gh", "issue", "view", str(ticket), "-R", repo,
                                     "--json", "title,body,assignees,labels,state"],
                                    cwd=self.repo, capture_output=True, text=True, timeout=20, check=True)
            return json.loads(result.stdout)
        except (subprocess.SubprocessError, ValueError, OSError) as exc:
            raise ValueError(f"could not read GitHub issue #{ticket}") from exc

    def issue_ready(self, issue, rule=""):
        if not issue:
            return False
        if str(issue.get("state", "OPEN")).upper() != "OPEN":
            return False
        labels = {item.get("name") for item in issue.get("labels", [])}
        if "loop:blocked" in labels or issue.get("assignees"):
            return False
        if str(rule).startswith("map:") or (self.state_dir / "active-map").exists():
            return True
        return "loop:ready" in labels

    def local_ticket_path(self, ticket):
        return self.repo / "maps" / "tickets" / f"{ticket}.md"

    def local_ticket_status(self, text):
        lines = str(text).splitlines()
        front = lines[1:] if lines and lines[0].strip() == "---" else lines
        for line in front:
            if line.strip() == "---":
                break
            if line.lower().startswith("status:"):
                return line.split(":", 1)[1].strip().strip("\"'").lower()
        return ""

    def local_ticket_ready(self, text):
        if not str(text).strip():
            return False
        return self.local_ticket_status(text) not in {"blocked", "paused", *TERMINAL_STATUSES}

    def _ticket_finished(self, ticket):
        issue = self.issue(ticket)
        if issue is not None:
            return str(issue.get("state", "OPEN")).upper() != "OPEN"
        path = self.local_ticket_path(ticket)
        return path.is_file() and self.local_ticket_status(path.read_text()) in TERMINAL_STATUSES

    def seat_has_outstanding_work(self, seat):
        lease_file = self.state_dir / "leases.json"
        if lease_file.is_file():
            try:
                leases = json.loads(lease_file.read_text()).get("leases", [])
            except ValueError:
                leases = []
            if any(item.get("seat") == seat for item in leases):
                return True
        gates = self.state_dir / "gates"
        if gates.is_dir():
            for job in gates.glob("*.job"):
                if (gates / f"{job.stem}.rc").exists():
                    continue
                try:
                    record = json.loads(job.read_text())
                except ValueError:
                    continue
                if record.get("seat") == seat:
                    return True
        return False

    def list_issues(self):
        result = subprocess.run(["gh", "issue", "list", "-R", self.github_repo(),
                                 "--state", "open", "--label", "loop:ready",
                                 "--limit", "100", "--json", "number,assignees,labels"],
                                cwd=self.repo, capture_output=True, text=True, timeout=20, check=True)
        return json.loads(result.stdout)

    def map_body(self, map_id):
        map_id = str(map_id).strip()
        if not map_id or map_id in {".", ".."} or "/" in map_id or "\\" in map_id:
            raise ValueError(f"invalid map id {map_id}")
        maps_dir = self.repo / "maps"
        if maps_dir.is_dir():
            exact = [cand for cand in maps_dir.glob("*.md") if cand.stem == map_id]
            if len(exact) > 1:
                raise ValueError(f"ambiguous local map match for {map_id}")
            if len(exact) == 1:
                return exact[0].read_text()
        if map_id.isdigit():
            try:
                repo = self.github_repo()
            except ValueError:
                return ""
            try:
                result = subprocess.run(["gh", "issue", "view", map_id, "-R", repo,
                                         "--json", "body"], cwd=self.repo, capture_output=True, text=True,
                                        timeout=20, check=True)
                return json.loads(result.stdout).get("body", "")
            except (subprocess.SubprocessError, ValueError, OSError):
                return ""
        return ""

    def map_tickets(self, map_id):
        body = self.map_body(map_id)
        if not body:
            return []
        tickets = []
        for line in body.splitlines():
            match = re.match(r"^\s*-\s*\[\s*\]\s*(.*)$", line)
            if not match:
                continue
            rest = match.group(1)
            gh_match = re.search(r"#([0-9]+)", rest)
            if gh_match:
                tickets.append(gh_match.group(1))
                continue
            file_match = re.search(r"(?:tickets/|\b)([A-Za-z0-9_.-]+)\.md", rest)
            if file_match:
                tickets.append(file_match.group(1))
                continue
            token_match = re.search(r"\b([A-Za-z0-9_]+-[0-9]+)\b", rest)
            if token_match:
                tickets.append(token_match.group(1))
                continue
            words = rest.strip().split()
            if words:
                clean = re.sub(r"[^A-Za-z0-9_.-]", "", words[0])
                if clean:
                    tickets.append(clean)
        return tickets

    def _ticket_settled(self, ticket):
        path = self.state_dir / "integration.jsonl"
        if not path.is_file():
            return False
        for line in path.read_text().splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if str(row.get("ticket")) == str(ticket) and row.get("status") in ("integrated", "promoted"):
                return True
        return False

    def _latest_new(self, data, ticket):
        found = None
        for item in data.get("seen", []):
            if item.get("ticket") == ticket and item.get("kind") == "new":
                found = item
        return found

    def _remember_finished(self, ids):
        # shortcut: a closed issue remembered here stays skipped until resume,
        # even if GitHub reopens it. Local files are re-read; they are cheap.
        if not ids:
            return
        def remember(data):
            have = {str(item) for item in data["finished"]}
            have.update(ids)
            data["finished"] = sorted(have)
        self._locked(remember)

    def _map_head_ready(self, ticket):
        if not str(ticket).isdigit():
            return True
        try:
            self.github_repo()
        except ValueError:
            return True
        issue = self.issue(ticket)
        return issue is not None and self.issue_ready(issue, "map:")

    def next_ready_ticket(self, auto=False):
        data = self._read()
        seen = {item["ticket"] for item in data["seen"] if item.get("kind") == "new"
                and (not auto or item.get("status") != "queued")}
        active_map_file = self.state_dir / "active-map"
        if active_map_file.exists():
            map_id = active_map_file.read_text().strip()
            if map_id:
                # Resume Map is sequential: an earlier unchecked item that is
                # still running, paused, or not yet integrated holds the rest.
                remembered = {str(item) for item in data["finished"]}
                found = set()
                cache = {}
                real_issue = self.issue
                def cached_issue(ticket):
                    key = str(ticket)
                    if key not in cache:
                        cache[key] = real_issue(ticket)
                    return cache[key]
                self.issue = cached_issue
                try:
                    for ticket in self.map_tickets(map_id):
                        ticket_str = str(ticket)
                        if self._ticket_settled(ticket_str) or ticket_str in remembered:
                            continue
                        # A finished ticket left unchecked must not hold the map forever.
                        try:
                            finished = self._ticket_finished(ticket_str)
                        except (OSError, ValueError, subprocess.SubprocessError):
                            return ""
                        if finished:
                            if cache.get(ticket_str) is not None:
                                found.add(ticket_str)
                            continue
                        if ticket_str in data["paused"]:
                            return ""
                        latest = self._latest_new(data, ticket_str)
                        if latest and not (auto and latest.get("status") == "queued"):
                            return ""
                        try:
                            if not self._map_head_ready(ticket_str):
                                return ""
                        except (OSError, ValueError, subprocess.SubprocessError):
                            return ""
                        return ticket_str
                    return ""
                finally:
                    self.issue = real_issue
                    self._remember_finished(found)

        issues = sorted(self.list_issues(), key=lambda issue: issue["number"])
        for issue in issues:
            ticket = str(issue["number"])
            labels = {item.get("name") for item in issue.get("labels", [])}
            if (ticket not in seen and ticket not in data["paused"] and not issue.get("assignees")
                    and "loop:ready" in labels and "loop:blocked" not in labels):
                return ticket
        return ""

    def dispatch(self, seat, brief, ticket):
        if not self.gate_ready():
            return False
        env = os.environ.copy()
        env.update(REPO_DIR=str(self.repo), STATE_DIR=str(self.state_dir))
        result = subprocess.run(["bash", str(Path(__file__).resolve().parents[1] / "loop-bot-herd.sh"),
                                 "dispatch", seat, str(brief), ticket], cwd=self.repo, env=env,
                                capture_output=True, text=True, timeout=30, check=False)
        if result.returncode:
            self._log("troubleshooting.log", f"#{ticket} dispatch refused: {result.stderr or result.stdout}")
        return result.returncode == 0

    def repair(self, seat, brief, ticket):
        # The original lease stays held through RED. Re-prompt its same seat;
        # attempting a fresh dispatch would falsely collide with that lease.
        lease_file = self.state_dir / "leases.json"
        if not lease_file.exists():
            return False
        leases = json.loads(lease_file.read_text()).get("leases", [])
        if not any(item.get("ticket") == ticket and item.get("seat") == seat for item in leases):
            return False
        result = subprocess.run(["herdr", "agent", "prompt", seat,
                                 f"REPAIR BRIEF (file): {brief} — fix, commit, and re-verdict."],
                                cwd=self.repo, capture_output=True, text=True, timeout=30, check=False)
        return result.returncode == 0

    def ask(self, kind, ticket, evidence, seats):
        model = self.config.get("seats", {}).get("looper", {}).get("model")
        if not model:
            raise ValueError("looper model is not configured")
        def recent(path, fields):
            if not path.exists():
                return []
            with path.open() as handle:
                lines = deque(handle, maxlen=10)
            records = []
            for line in lines:
                try:
                    row = json.loads(line)
                    records.append({field: row[field] for field in fields if field in row})
                except (TypeError, ValueError):
                    continue
            return records
        lease_file = self.state_dir / "leases.json"
        active_leases = json.loads(lease_file.read_text()).get("leases", [])[:20] if lease_file.exists() else []
        paused_items = list(self._read()["paused"].items())
        checkpoint = {"event": kind, "ticket": ticket, "evidence": evidence[:1000],
                      "candidate_seats": seats,
                      "paused_count": len(paused_items),
                      "paused_recent": [{"ticket": item[0], "reason": item[1][:160]}
                                        for item in paused_items[-PAUSED_SUMMARY_LIMIT:]],
                      "paused_path": str(self.file),
                      "active_leases": active_leases,
                      "pending_arbiter": recent(self.state_dir / "integration.jsonl", ("ticket", "sha", "status")),
                      "recent_verdicts": recent(self.state_dir / "session-verdicts.jsonl", ("ticket", "sha", "suite")),
                      "full_evidence_dir": str(self.state_dir)}
        prompt = ("You are Stampede's one-turn AGY looper. Return one compact JSON proposal. "
                  "Allowed actions: summary for GREEN; assign one candidate seat for a new ticket; "
                  "repair the supplied same seat for RED; escalate for human input. "
                  "Do not run commands, approve gates, drain the arbiter, or promote. "
                  "Checkpoint: " + json.dumps(checkpoint, ensure_ascii=False))
        with tempfile.TemporaryDirectory(prefix="stampede-looper-") as runtime:
            result = subprocess.run(["agy", "--print", prompt, "--model", model, "--effort", "low", "--sandbox",
                                     "--output-format", "json", "--json-schema", SCHEMA,
                                     "--print-timeout", "90s", "--disable-slash-commands"],
                                    cwd=Path(runtime), capture_output=True, text=True, timeout=100, check=True)
        if len(result.stdout) > 100_000:
            raise ValueError("looper response exceeded bound")
        packet = json.loads(result.stdout)
        if not isinstance(packet, dict):
            raise ValueError("invalid AGY response envelope")
        proposal = packet.get("structured_output", packet)
        for _ in range(3):
            if isinstance(proposal, str):
                proposal = json.loads(proposal)
            elif isinstance(proposal, dict) and "action" not in proposal:
                proposal = proposal.get("result", proposal.get("response", proposal.get("text")))
            else:
                break
        if not isinstance(proposal, dict) or proposal.get("action") not in ("summary", "assign", "repair", "escalate"):
            raise ValueError("invalid looper proposal")
        if not isinstance(proposal.get("summary"), str) or len(proposal["summary"]) > 500:
            raise ValueError("invalid looper summary")
        with (self.state_dir / "looper-usage.jsonl").open("a") as handle:
            handle.write(json.dumps({"ts": int(time.time()), "ticket": ticket, "event": kind,
                                     "model": model, "usage": packet.get("usage", {}),
                                     "num_turns": packet.get("num_turns")}) + "\n")
        return proposal

    def event(self, kind, ticket, evidence, seat=""):
        if kind not in VALID_EVENTS or not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", ticket):
            raise ValueError("invalid event or ticket")
        if len(evidence) > 2048:
            raise ValueError("event evidence exceeds bound")
        key = hashlib.sha256(json.dumps([kind, ticket, evidence, seat]).encode()).hexdigest()

        def handle(data):
            if any(item["key"] == key for item in data["seen"]):
                if key in data["inflight"]:
                    data["inflight"].pop(key)
                    return self._pause(data, ticket, "interrupted decision: inspect seat, lease, and logs before resuming")
                return {"status": "duplicate"}
            data["seen"].append({"key": key, "ticket": ticket, "kind": kind})
            data["seen"] = data["seen"][-1000:]
            # Persist the receipt before any model call or dispatch. A crash
            # leaves a visible human handoff instead of repeating a prompt.
            data["inflight"][key] = ticket
            self._write(data)
            try:
                result = decide(data)
                if result["status"] == "deferred":
                    data["seen"].pop()
                else:
                    data["seen"][-1]["status"] = result["status"]
                    # A blocked health ping is not the decision the human approved.
                    if kind != "blocked":
                        data["approved"].pop(ticket, None)
                return result
            finally:
                data["inflight"].pop(key, None)

        def decide(data):
            mode = data.get("mode", self.config.get("attention", {}).get("mode", "medium"))
            if mode not in VALID_MODES:
                raise ValueError("invalid attention mode")
            if ticket in data["paused"]:
                return {"status": "paused", "reason": data["paused"][ticket]}
            if kind == "blocked":
                if data["approved"].get(ticket):
                    return {"status": "noted"}
                return self._pause(data, ticket, f"blocked: {evidence}")
            if mode == "loud" and not data["approved"].get(ticket):
                return self._pause(data, ticket, f"{kind}: human review required")
            if kind == "green":
                if mode == "medium":
                    try:
                        proposal = self.ask(kind, ticket, evidence, [])
                        self._log("worklog.log", f"#{ticket} GREEN: {proposal['summary']}")
                    except (OSError, ValueError, subprocess.SubprocessError) as exc:
                        self._log("troubleshooting.log", f"#{ticket} looper summary failed: {exc}")
                self._log("handoff.log", f"#{ticket} GREEN queued; human: inspect gate, run stampede arbiter {self.repo} drain")
                return {"status": "manual_arbiter"}
            if mode == "quiet" and kind == "new" and evidence != "loop:ready:auto":
                self._log("worklog.log", f"#{ticket} ready, queued for human dispatch")
                return {"status": "queued"}
            if mode == "quiet" and kind != "new":
                return self._pause(data, ticket, f"{kind}: {evidence}")
            if kind == "red" and data["repairs"].get(ticket, 0) >= 1:
                return self._pause(data, ticket, "second RED: human review required")
            try:
                candidates = [item["name"] for item in self._candidates(kind == "new")
                              if self.seat_ready(item["name"])]
                if kind == "new":
                    candidates = [name for name in candidates if not self.seat_has_outstanding_work(name)]
                if kind == "new" and not self.gate_ready():
                    raise ValueError("project suite gate is unavailable; ticket intake stopped")
                issue = self.issue(ticket) if kind == "new" else None
                if kind == "new" and issue is not None and not self.issue_ready(issue, evidence):
                    raise ValueError("issue is no longer ready or is assigned")
                if kind == "new" and issue is None:
                    local_ticket = self.local_ticket_path(ticket)
                    if not local_ticket.is_file():
                        raise ValueError(f"ticket {ticket} could not be read; dispatch stopped")
                    if not self.local_ticket_ready(local_ticket.read_text()):
                        raise ValueError("local ticket is not ready; dispatch stopped")
                if kind == "new" and not candidates:
                    return {"status": "deferred"}
                if mode == "quiet" and kind == "new":
                    proposal = {"action": "assign", "seat": candidates[0] if candidates else "",
                                "summary": "deterministic quiet dispatch"}
                else:
                    model_evidence = evidence
                    if issue:
                        model_evidence += f"; issue: {issue['title']} — {(issue.get('body') or '')[:800]}"
                    else:
                        local_ticket = self.repo / "maps" / "tickets" / f"{ticket}.md"
                        if local_ticket.exists():
                            model_evidence += f"; ticket: {local_ticket.read_text()[:800]}"
                    proposal = self.ask(kind, ticket, model_evidence, candidates if kind == "new" else [seat])
                selected = proposal.get("seat")
                if kind == "new":
                    if proposal["action"] != "assign" or selected not in candidates:
                        raise ValueError("looper selected no ready architect seat")
                    issue = self.issue(ticket)
                    if issue is not None:
                        if not self.issue_ready(issue, evidence):
                            raise ValueError("issue changed while looper was deciding; dispatch stopped")
                        issue_body = issue.get("body") or ""
                        body = f"Ticket #{ticket}: {issue['title']}\n\n{issue_body}\n"
                    else:
                        local_ticket = self.local_ticket_path(ticket)
                        if not local_ticket.is_file():
                            raise ValueError(f"ticket {ticket} could not be read; dispatch stopped")
                        body = local_ticket.read_text()
                        if not self.local_ticket_ready(body):
                            raise ValueError("local ticket is not ready; dispatch stopped")
                        issue_body = body
                    owns = next((line for line in issue_body.splitlines()
                                 if line.startswith("owns:")), "")
                    ticket_file = self.state_dir / "tickets" / f"{ticket}.md"
                    ticket_file.parent.mkdir(exist_ok=True)
                    ticket_file.write_text(f"---\nid: {ticket}\n{owns + chr(10) if owns else ''}---\n\n{body}")
                else:
                    if proposal["action"] != "repair" or selected != seat or seat not in candidates:
                        raise ValueError("RED repair must return to the same ready isolated architect")
                    body = f"Repair ticket #{ticket} on the same isolated worktree. Gate evidence: {evidence}\nCommit and re-verdict.\n"
                brief = self.state_dir / "briefs" / f"attention-{ticket}-{key[:10]}.md"
                brief.parent.mkdir(exist_ok=True)
                brief.write_text(body)
                sent = self.dispatch(selected, brief, ticket) if kind == "new" else self.repair(selected, brief, ticket)
                if not sent:
                    raise ValueError("deterministic dispatch refused")
                if kind == "red":
                    data["repairs"][ticket] = data["repairs"].get(ticket, 0) + 1
                self._log("worklog.log", f"#{ticket} {kind} -> {selected}: {proposal['summary']}")
                return {"status": "dispatched" if kind == "new" else "repair_dispatched", "seat": selected}
            except (OSError, KeyError, ValueError, subprocess.SubprocessError) as exc:
                return self._pause(data, ticket, f"{kind} needs human: {exc}")

        return self._locked(handle)


def main():
    parser = argparse.ArgumentParser(prog="stampede attention")
    parser.add_argument("command", choices=("mode", "event", "resume", "next"))
    parser.add_argument("repo", type=Path)
    parser.add_argument("values", nargs="*")
    args = parser.parse_args()
    policy = Attention(args.repo)
    if args.command == "mode":
        print(policy.set_mode(args.values[0]) if args.values else policy.mode())
    elif args.command == "resume":
        if len(args.values) != 1:
            parser.error("resume requires one ticket")
        policy.resume(args.values[0])
        print(f"resumed #{args.values[0]}")
    elif args.command == "next":
        if args.values not in ([], ["auto"]):
            parser.error("next accepts only auto")
        print(policy.next_ready_ticket(auto=args.values == ["auto"]))
    else:
        if len(args.values) not in (3, 4):
            parser.error("event requires KIND TICKET EVIDENCE [SEAT]")
        print(json.dumps(policy.event(*args.values)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as exc:
        print(f"attention: {exc}", file=sys.stderr)
        sys.exit(1)
