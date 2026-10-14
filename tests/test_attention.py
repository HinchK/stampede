import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess


SOURCE = Path(__file__).resolve().parents[1] / "lib/attention.py"
spec = importlib.util.spec_from_file_location("stampede_attention", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AttentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / ".herdr-swarm").mkdir()
        (self.repo / ".herdr-swarm/profile.env").write_text("REPO=upstream/project\nTEST_CMD=make test\n")
        (self.repo / "swarm.config.toml").write_text(
            '[attention]\nmode = "medium"\nbounded_looper = true\n'
            '[seats.looper]\ndefault_kind = "agy"\nmodel = "flash-test"\n'
            '[seats.arch_1]\nname = "arch-1"\nrole = "architect"\ndefault_kind = "opencode"\n')
        (self.repo / ".herdr-swarm/seats.json").write_text(json.dumps({
            "seats": [{"name": "arch-1-test", "kind": "opencode", "isolated": True,
                       "pane": "p1", "worktree_dir": str(self.repo)}]}))
        self.policy = module.Attention(self.repo)
        self.calls = []
        self.policy.ask = lambda kind, ticket, evidence, seats: self.calls.append((kind, ticket)) or {
            "action": "assign" if kind == "new" else "repair" if kind == "red" else "summary",
            "seat": "arch-1-test", "summary": "short receipt"}
        self.policy.dispatch = lambda seat, brief, ticket: self.calls.append(("dispatch", seat, ticket)) or True
        self.policy.repair = lambda seat, brief, ticket: self.calls.append(("repair", seat, ticket)) or True
        self.policy.issue = lambda ticket: {"title": "Test issue", "body": "Own: src/example.py",
                                            "assignees": [], "labels": [{"name": "loop:ready"}]}
        self.policy.seat_ready = lambda seat: True

    def test_green_modes_and_dedupe(self):
        self.assertEqual(self.policy.event("green", "11", "sha-a", "arch-1-test")["status"], "manual_arbiter")
        self.assertEqual(self.calls, [("green", "11")])
        self.assertEqual(self.policy.event("green", "11", "sha-a", "arch-1-test")["status"], "duplicate")
        self.assertEqual(len(self.calls), 1)
        self.policy.set_mode("quiet")
        self.assertEqual(self.policy.event("green", "12", "sha-b")["status"], "manual_arbiter")
        self.assertEqual(len(self.calls), 1)
        self.policy.set_mode("loud")
        self.assertEqual(self.policy.event("green", "13", "sha-c")["status"], "paused")
        self.assertTrue(self.policy.is_paused("13"))

    def test_new_ticket_modes_and_validated_dispatch(self):
        self.policy.ask = lambda kind, ticket, evidence, seats: self.calls.append((kind, ticket, evidence)) or {
            "action": "assign", "seat": "arch-1-test", "summary": "short receipt"}
        self.assertEqual(self.policy.event("new", "21", "ready")["status"], "dispatched")
        self.assertIn(("dispatch", "arch-1-test", "21"), self.calls)
        self.assertIn("Test issue", self.calls[0][2])
        ticket_file = self.repo / ".herdr-swarm/tickets/21.md"
        self.assertTrue(ticket_file.exists())
        self.assertIn("id: 21", ticket_file.read_text())
        self.policy.ask = lambda *args: {"action": "assign", "seat": "pm-test", "summary": "bad"}
        self.assertEqual(self.policy.event("new", "22", "ready")["status"], "paused")
        self.assertTrue(self.policy.is_paused("22"))
        self.policy.set_mode("quiet")
        self.assertEqual(self.policy.event("new", "23", "ready")["status"], "queued")
        prior_turns = len([call for call in self.calls if call[0] == "new"])
        self.assertEqual(self.policy.event("new", "25", "loop:ready:auto")["status"], "dispatched")
        self.assertEqual(len([call for call in self.calls if call[0] == "new"]), prior_turns)
        self.policy.set_mode("loud")
        self.assertEqual(self.policy.event("new", "24", "ready")["status"], "paused")

    def test_red_one_repair_then_pause_and_blocked(self):
        self.assertEqual(self.policy.event("red", "31", "gate-a", "arch-1-test")["status"], "repair_dispatched")
        self.assertIn(("repair", "arch-1-test", "31"), self.calls)
        self.assertEqual(self.policy.event("red", "31", "gate-b", "arch-1-test")["status"], "paused")
        self.assertTrue(self.policy.is_paused("31"))
        self.assertEqual(self.policy.event("blocked", "32", "question", "arch-1-test")["status"], "paused")
        self.policy.set_mode("quiet")
        self.assertEqual(self.policy.event("red", "33", "gate-c", "arch-1-test")["status"], "paused")
        self.policy.set_mode("loud")
        self.assertEqual(self.policy.event("red", "34", "gate-d", "arch-1-test")["status"], "paused")

    def test_red_from_isolated_docs_seat_can_repair_same_seat(self):
        config = self.repo / "swarm.config.toml"
        config.write_text(config.read_text() + '\n[seats.docs]\nname = "docs"\nrole = "docs"\ndefault_kind = "agy"\n')
        ledger = self.repo / ".herdr-swarm/seats.json"
        data = json.loads(ledger.read_text())
        data["seats"].append({"name": "docs-test", "kind": "agy", "isolated": True,
                              "pane": "p2", "worktree_dir": str(self.repo)})
        ledger.write_text(json.dumps(data))
        policy = module.Attention(self.repo)
        policy.seat_ready = lambda seat: True
        policy.ask = lambda *args: {"action": "repair", "seat": "docs-test", "summary": "repair doc"}
        policy.repair = lambda *args: True
        self.assertEqual(policy.event("red", "35", "gate-red", "docs-test")["status"], "repair_dispatched")

    def test_model_failure_and_untrusted_action_pause(self):
        self.policy.ask = lambda *args: {"action": "shell", "command": "touch /tmp/harm"}
        self.assertEqual(self.policy.event("new", "41", "ready")["status"], "paused")
        self.policy.ask = lambda *args: (_ for _ in ()).throw(TimeoutError("model timeout"))
        self.assertEqual(self.policy.event("red", "42", "gate", "arch-1-test")["status"], "paused")
        self.assertNotIn(("dispatch", "arch-1-test", "41"), self.calls)

    def test_mode_persists_and_resume_is_ticket_local(self):
        self.policy.set_mode("loud")
        self.policy.event("new", "51", "ready")
        self.policy.event("new", "52", "ready")
        self.policy.resume("51")
        self.assertFalse(module.Attention(self.repo).is_paused("51"))
        self.assertTrue(module.Attention(self.repo).is_paused("52"))
        self.assertEqual(module.Attention(self.repo).mode(), "loud")

    def test_ask_is_fresh_bounded_agy_and_parses_structured_result(self):
        class Result:
            stdout = json.dumps({"structured_output": {"action": "summary", "summary": "brief"},
                                 "usage": {"input_tokens": 50, "output_tokens": 8}, "num_turns": 1})
        with patch.object(module.subprocess, "run", return_value=Result()) as run:
            proposal = module.Attention(self.repo).ask("green", "61", "sha", [])
        argv = run.call_args.args[0]
        self.assertEqual(proposal["summary"], "brief")
        self.assertIn("--print", argv)
        self.assertIn("--print-timeout", argv)
        self.assertNotIn("--continue", argv)
        self.assertIn("--sandbox", argv)
        self.assertIn("--effort", argv)
        self.assertNotEqual(run.call_args.kwargs["cwd"], self.repo)
        self.assertEqual(argv[argv.index("--model") + 1], "flash-test")
        self.assertIn("active_leases", argv[argv.index("--print") + 1])
        usage = json.loads((self.repo / ".herdr-swarm/looper-usage.jsonl").read_text().splitlines()[0])
        self.assertEqual(usage["usage"]["output_tokens"], 8)

    def test_next_ready_ticket_skips_seen_assigned_and_blocked(self):
        self.policy.event("new", "1", "ready")
        issues = [
            {"number": 1, "assignees": [], "labels": [{"name": "loop:ready"}]},
            {"number": 2, "assignees": [{"login": "someone"}], "labels": [{"name": "loop:ready"}]},
            {"number": 3, "assignees": [], "labels": [{"name": "loop:ready"}, {"name": "loop:blocked"}]},
            {"number": 4, "assignees": [], "labels": [{"name": "loop:ready"}]},
        ]
        self.policy.list_issues = lambda: issues
        self.assertEqual(self.policy.next_ready_ticket(), "4")

    def test_quiet_queued_ticket_becomes_eligible_when_auto_intake_enabled(self):
        self.policy.set_mode("quiet")
        self.assertEqual(self.policy.event("new", "7", "loop:ready")["status"], "queued")
        self.policy.list_issues = lambda: [{"number": 7, "assignees": [],
                                            "labels": [{"name": "loop:ready"}]}]
        self.assertEqual(self.policy.next_ready_ticket(), "")
        self.assertEqual(self.policy.next_ready_ticket(auto=True), "7")
        self.assertEqual(self.policy.event("new", "7", "loop:ready:auto")["status"], "dispatched")
        self.assertEqual(self.policy.next_ready_ticket(auto=True), "")

    def test_quiet_queued_ticket_is_reconsidered_after_mode_change(self):
        self.policy.set_mode("quiet")
        self.assertEqual(self.policy.event("new", "8", "loop:ready")["status"], "queued")
        self.policy.list_issues = lambda: [{"number": 8, "assignees": [],
                                            "labels": [{"name": "loop:ready"}]}]
        self.policy.set_mode("medium")
        self.assertEqual(self.policy.next_ready_ticket(), "8")
        self.assertEqual(self.policy.event("new", "8", "loop:ready")["status"], "dispatched")

    def test_interrupted_decision_requires_human_recovery(self):
        self.policy.ask = lambda *args: (_ for _ in ()).throw(KeyboardInterrupt())
        with self.assertRaises(KeyboardInterrupt):
            self.policy.event("red", "71", "gate", "arch-1-test")
        restarted = module.Attention(self.repo)
        self.assertEqual(restarted.event("red", "71", "gate", "arch-1-test")["status"], "paused")
        self.assertTrue(restarted.is_paused("71"))

    def test_repair_requires_matching_live_lease(self):
        actual = module.Attention(self.repo)
        brief = self.repo / "repair.md"
        brief.write_text("repair")
        leases = self.repo / ".herdr-swarm/leases.json"
        leases.write_text(json.dumps({"leases": [{"ticket": "81", "seat": "arch-1-test"}]}))
        with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertTrue(actual.repair("arch-1-test", brief, "81"))
            self.assertFalse(actual.repair("arch-other", brief, "81"))
            self.assertFalse(actual.repair("arch-1-test", brief, "82"))
        self.assertEqual(run.call_count, 1)

    def test_github_reads_use_project_profile_not_git_default(self):
        class Result:
            stdout = "[]"
        with patch.object(module.subprocess, "run", return_value=Result()) as run:
            module.Attention(self.repo).list_issues()
        self.assertEqual(run.call_args.args[0][3:5], ["-R", "upstream/project"])

    def test_new_dispatch_stops_when_gate_or_issue_readiness_changes(self):
        (self.repo / ".herdr-swarm/control.json").write_text('{"suite_gate": false}')
        self.assertEqual(self.policy.event("new", "91", "loop:ready")["status"], "paused")
        self.assertNotIn(("dispatch", "arch-1-test", "91"), self.calls)
        (self.repo / ".herdr-swarm/control.json").write_text('{"suite_gate": true}')
        views = [{"title": "Ready", "body": "", "assignees": [], "labels": [{"name": "loop:ready"}]},
                 {"title": "Taken", "body": "", "assignees": [{"login": "human"}],
                  "labels": [{"name": "loop:ready"}]}]
        self.policy.issue = lambda ticket: views.pop(0)
        self.assertEqual(self.policy.event("new", "92", "loop:ready")["status"], "paused")
        self.assertNotIn(("dispatch", "arch-1-test", "92"), self.calls)


if __name__ == "__main__":
    unittest.main()
