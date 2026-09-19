#!/usr/bin/env python3
"""
Telemetry and execution event logger for herdr-loop-swarm.
Writes structured JSONL trace files to ~/.herdr-loop-swarm/traces/
"""

import os
import sys
import json
import time
from pathlib import Path
from typing import Optional, Dict, Any

TRACE_DIR = Path(os.path.expanduser("~/.herdr-loop-swarm/traces"))

def init_trace_dir() -> Path:
    TRACE_DIR.mkdir(parents=True, exist_ok=True)
    return TRACE_DIR

def log_event(
    session_id: str,
    event_type: str,
    agent: Optional[str] = None,
    ticket_num: Optional[int] = None,
    payload: Optional[Dict[str, Any]] = None,
) -> None:
    init_trace_dir()
    trace_file = TRACE_DIR / f"{session_id}.jsonl"
    
    event = {
        "timestamp": time.time(),
        "iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "event_type": event_type,
        "agent": agent,
        "ticket_num": ticket_num,
        "payload": payload or {},
    }
    
    with open(trace_file, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: telemetry.py <session_id> <event_type> [agent] [ticket_num] [json_payload]")
        sys.exit(1)
        
    sess = sys.argv[1]
    etype = sys.argv[2]
    agent = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
    ticket = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4].isdigit() else None
    payload = json.loads(sys.argv[5]) if len(sys.argv) > 5 else {}
    
    log_event(sess, etype, agent=agent, ticket_num=ticket, payload=payload)
