# Wayfinder Map: Harden Headless Mode

## Destination

Fix the three genuine defects and two hardening/ergonomic gaps discovered during the live headless batch proof (`PROVE-HEADLESS-1`), ensuring `bin/stampede headless` reliably handles worktree provisioning failures, drives RED multi-attempt critique cycles to the ceiling with non-zero exit on failure, auto-drains queues without self-wedging, respects runtime environment overrides, and escalates timeouts with SIGKILL.

## Notes

- Domain: headless batch drainer (`lib/cli/stampede-headless.sh`), worktree lifecycle (`lib/worktree.sh`), unattended safety harness (`lib/headless.sh`), configuration dump (`lib/config.sh`), documentation (`docs/findings/headless-mode-design.md`).
- Source: Empirical proof findings in `docs/findings/headless-batch-run-receipt.md` (commit `5fe9c9f`, integrated on `swarm/stampede/integration` at `f588670`).
- Priority / Sequencing:
  - `HL-RED-1` (Severity MED-HIGH): Highest priority defect — unblocks proper critique loops, in-batch drain, and honest failure exit codes.
  - `HL-WT-1` (Severity MED): Fixes silent no-op phantom worktree provisioning. Disjoint from `HL-RED-1` and `SYNC-2`.
  - `HL-CFG-1` (Severity LOW-MED): Fixes TOML clobbering env overrides in `lib/config.sh`.
  - `HL-TMO-1` (Severity LOW): Hardens wall-clock timeout with `-k` escalation. Owns `lib/headless.sh`; cannot dispatch concurrently with `HL-RED-1`.
  - `HL-DOCS-1` (Severity LOW): Documentation and honest dead-letter reasons with log pointers; assigned to `agy-docs`.
- Arch Seat Balancing Convention: implementation tickets assigned to `arch` dispatch to whichever arch seat has sat idle longest (`state_change_seq`), verifying partition disjointness before leasing.
- Core Invariants: Human-only promote boundary; fail-closed partition checks; zero cross-pane injection.

## Active Frontier

- [Close first-RED critique termination and undrained queue gap](tickets/hl-red-1-first-red-ceiling-drain.md) (HL-RED-1) —
  completed, `arch` (integrated @ `af62507`). Multi-attempt critique turns below ceiling, non-zero batch failure exit, in-batch drain and lease release.
- [Propagate worktree_provision exit status](tickets/hl-wt-1-worktree-provision-rc.md) (HL-WT-1) —
  completed, `arch` (integrated @ `b95b383`). Propagated failure rc from `_wt_add_with_retry`, guarded `headless_spawn` cd, and added hermetic regression test case 16.
- [Respect env overrides for headless knobs](tickets/hl-cfg-1-toml-env-override.md) (HL-CFG-1) —
  completed, `arch` (integrated @ `7d27c8a`). Implemented `emit_env_wins` in `lib/config.sh` and verified environment overrides in `tests/test_config.sh`.
- [Escalate headless worker timeouts with SIGKILL](tickets/hl-tmo-1-worker-timeout-escalation.md) (HL-TMO-1) —
  completed, `arch` (integrated @ `67d1824`). Hard wall-clock bound with -k kill-grace and rc=124 normalization.
- [Document sandbox requirements and honest dead-letter reasons](tickets/hl-docs-1-dead-letter-reasons-and-brief-sandbox.md) (HL-DOCS-1) —
  completed, `arch` (integrated @ `f357e47`). Honest dead-letter reasons with log pointers, OpenCode sandbox external_directory config docs, test_cli [13].

## Decisions so far

- Headless batch mode proven live end-to-end on ephemeral scratch repo in PROVE-HEADLESS-1 (`f588670`), discovering 8 concrete findings and 3 defects in shipped code.
- Harden Headless Mode destination fully achieved: all 5 tickets (#HL-WT-1, #HL-RED-1, #HL-CFG-1, #HL-TMO-1, #HL-DOCS-1) implemented with TDD, reviewed with autonomous PASS verdicts, and integrated onto `swarm/stampede/integration`.
