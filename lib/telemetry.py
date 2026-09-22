#!/usr/bin/env python3
"""
Telemetry event engine for the herdr swarm.

Commands:
  log <session_id> <event_type> [agent|-] [ticket_num] [json_payload] [--trace-dir <dir>]
      Append a structured JSONL event to <trace-dir>/<session_id>.jsonl
      Envelope: timestamp, iso, session_id, event_type, agent, ticket_num, payload

  stream <session_id> [trace_dir] [--once]
      Pretty-print events as 1-line ANSI badges, clamped to terminal width:
        [HH:MM:SS] [BADGE] SEAT-NAME #TICKET Summary Details...
      Badges: DISPATCH (cyan) · VERDICT:✓/✗ (green/red) · BREAKER:⚠ (yellow)
              LIFECYCLE (blue) · VERIFY:✓/✗ (green/red) · EVENT (plain)
      --once replays existing lines; without it the file is followed live.

Trace dir resolution: --trace-dir > $HERDR_TRACE_DIR > ./.herdr-swarm/traces
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

RESET = "\033[0m"
CYAN = "\033[36m"
GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
BLUE = "\033[34m"


def resolve_trace_dir(explicit: Optional[str] = None) -> Path:
    if explicit:
        return Path(explicit)
    env = os.environ.get("HERDR_TRACE_DIR")
    if env:
        return Path(env)
    return Path(".herdr-swarm/traces")


def log_event(
    session_id: str,
    event_type: str,
    agent: Optional[str] = None,
    ticket_num: Optional[str] = None,
    payload: Optional[dict] = None,
    trace_dir: Optional[str] = None,
) -> None:
    d = resolve_trace_dir(trace_dir)
    d.mkdir(parents=True, exist_ok=True)
    # ticket_num is string-typed end-to-end (the ARB-STR rule): ticket ids
    # like "DEMO-1" or "PUB-10" must survive verbatim. Ints are accepted
    # for backward compatibility and stored as-is; anything else is kept
    # as its string form — never silently dropped to null (PUB-10).
    if isinstance(ticket_num, int) and not isinstance(ticket_num, bool):
        ticket_num = str(ticket_num)
    event = {
        "timestamp": time.time(),
        "iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "session_id": session_id,
        "event_type": event_type,
        "agent": agent,
        "ticket_num": ticket_num,
        "payload": payload or {},
    }
    with open(d / f"{session_id}.jsonl", "a", encoding="utf-8") as f:
        # ensure_ascii=False: the trust ledger is read by humans auditing
        # events; a ✓ must land in the file as a ✓, not \u2713 (PUB-10).
        f.write(json.dumps(event, ensure_ascii=False) + "\n")


# ── streaming ──────────────────────────────────────────────────────────────

def _is_ok(payload: dict) -> bool:
    suite = str(payload.get("suite", "")).lower()
    if suite:
        return suite in ("green", "skipped")
    return bool(payload.get("ok", payload.get("success", False)))


def badge_for(event_type: str, payload: dict) -> Tuple[str, str]:
    et = (event_type or "").lower()
    if "dispatch" in et:
        return ("DISPATCH", CYAN)
    if "verdict" in et:
        return ("VERDICT:✓", GREEN) if _is_ok(payload) else ("VERDICT:✗", RED)
    if "breaker" in et or "stall" in et:
        return ("BREAKER:⚠", YELLOW)
    if "lifecycle" in et:
        return ("LIFECYCLE", BLUE)
    if "verify" in et or "seat" in et:
        return ("VERIFY:✓", GREEN) if _is_ok(payload) else ("VERIFY:✗", RED)
    return ("EVENT", "")


def _summary_bits(event: dict) -> Tuple[str, str]:
    payload = event.get("payload") or {}
    summary = payload.get("summary") or payload.get("action") or event.get("event_type") or "event"
    details = payload.get("details")
    if not details:
        extra = {k: v for k, v in payload.items() if k not in ("summary", "action", "details")}
        details = json.dumps(extra, separators=(",", ":"), ensure_ascii=False) if extra else ""
    return str(summary), str(details)


def _render(segments: List[Tuple[str, str]], width: int, color: bool) -> str:
    """Join (text, ansi_code) segments, truncating with an ellipsis so the
    visible width never exceeds `width`."""
    out: List[str] = []
    used = 0
    truncated = False
    for text, code in segments:
        if truncated:
            break
        if not text:
            continue
        if color and code:
            out.append(code)
        for i, ch in enumerate(text):
            if used >= max(width - 1, 1):
                truncated = True
                break
            out.append(ch)
            used += 1
        if color and code:
            out.append(RESET)
        if truncated:
            out.append("…" if color is False else "…")
    if truncated:
        out.append(RESET if color else "")
    return "".join(out)


def format_event(event: dict, width: int, color: bool) -> str:
    ts = time.strftime("%H:%M:%S", time.localtime(event.get("timestamp", 0)))
    label, ansi = badge_for(event.get("event_type", ""), event.get("payload") or {})
    summary, details = _summary_bits(event)

    head = f"[{ts}]"
    segs: List[Tuple[str, str]] = [(head, ""), (" ", ""), (f"[{label}]", ansi)]
    if event.get("agent"):
        segs.append((f" {event['agent']}", ""))
    if event.get("ticket_num") is not None:
        segs.append((f" #{event['ticket_num']}", ""))
    segs.append((f" {summary}", ""))
    if details:
        segs.append((f" — {details}", ""))
    return _render(segs, width, color)


def stream(session_id: str, trace_dir: Optional[str] = None, once: bool = False) -> None:
    d = resolve_trace_dir(trace_dir)
    path = d / f"{session_id}.jsonl"
    color = sys.stdout.isatty()

    try:
        import shutil
        width = shutil.get_terminal_size((120, 24)).columns
    except Exception:
        width = 120

    def emit(line: str) -> None:
        if line.strip():
            print(line, flush=True)

    if once:
        if path.is_file():
            for raw in path.read_text(encoding="utf-8").splitlines():
                try:
                    emit(format_event(json.loads(raw), width, color))
                except json.JSONDecodeError:
                    continue
        return

    # Follow mode: wait for the file, then tail it forever (tail -f -n 0)
    while not path.is_file():
        time.sleep(0.5)
    with open(path, "r", encoding="utf-8") as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.3)
                continue
            try:
                emit(format_event(json.loads(line), width, color))
            except json.JSONDecodeError:
                continue


# ── CLI ────────────────────────────────────────────────────────────────────

def _split_trace_dir(args: List[str]) -> Tuple[List[str], Optional[str]]:
    rest: List[str] = []
    trace_dir: Optional[str] = None
    i = 0
    while i < len(args):
        if args[i] == "--trace-dir" and i + 1 < len(args):
            trace_dir = args[i + 1]
            i += 2
            continue
        rest.append(args[i])
        i += 1
    return rest, trace_dir


def main(argv: List[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]

    if cmd == "log":
        rest, trace_dir = _split_trace_dir(argv[2:])
        if len(rest) < 2:
            print("usage: telemetry.py log <session_id> <event_type> [agent|-] [ticket_num] [json_payload] [--trace-dir <dir>]", file=sys.stderr)
            return 1
        session_id, event_type = rest[0], rest[1]
        agent = rest[2] if len(rest) > 2 and rest[2] != "-" else None
        # String ticket ids pass through verbatim (PUB-10 / ARB-STR);
        # numeric-looking ids keep their textual form too — a ticket id is
        # an identifier, not a number.
        ticket = rest[3] if len(rest) > 3 and str(rest[3]) != "-" else None
        payload = json.loads(rest[4]) if len(rest) > 4 else {}
        log_event(session_id, event_type, agent=agent, ticket_num=ticket, payload=payload, trace_dir=trace_dir)
        return 0

    if cmd == "stream":
        rest, trace_dir = _split_trace_dir(argv[2:])
        once = "--once" in rest
        rest = [a for a in rest if a != "--once"]
        if not rest:
            print("usage: telemetry.py stream <session_id> [trace_dir] [--once]", file=sys.stderr)
            return 1
        try:
            stream(rest[0], trace_dir or (rest[1] if len(rest) > 1 else None), once)
        except KeyboardInterrupt:
            pass
        return 0

    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
