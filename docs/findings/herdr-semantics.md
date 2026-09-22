# Herdr Semantics — Empirical Findings (T-001)

**Date:** 2026-09-19 · **herdr 0.9.1** · **Method:** live probes against a scratch workspace (`probe-t001`, cwd `/tmp/.../opencode/probe-t001`), cleaned up after. All outputs below are observed, not inferred.

Resolves viability findings **V1** (workspace-focus routing) and **V3** (agent-name scoping) from the brainstorm report (`/tmp/arch-out.md`, 2026-09-19 session).

---

## A. workspace focus & pane routing (V1)

### A1. IDs are workspace-prefixed and globally unique

Pane IDs embed their workspace: `wN:p1`, tab IDs `wN:t1` (observed across workspaces `wK`/`wM`/`wN`). Any command addressed by an explicit pane/tab ID is unambiguous server-wide.

### A2. Explicit-ID operations route correctly regardless of focus

With workspace `wM` focused, `herdr pane split --pane wN:p1 --direction down` created `wN:p2` — inside `wN`, the pane's own workspace. **Routing is by the target ID, not by focused workspace.**

```
$ herdr workspace focus wM && herdr pane split --pane wN:p1 --direction down --no-focus
{"new":"wN:p2"}          # landed in wN while wM was focused
```

### A3. `pane split --current` does NOT follow workspace focus — DANGEROUS in scripts

With `wN` focused (verified via `workspace list` → `"focused":true` on `wN`), `pane split --current` created **`wM:pF` — a pane in the live swarm workspace**. `--current` resolves to the terminal UI's current foreground pane (wherever the human last interacted, in `wM`), not to the focused workspace's anchor.

```
$ herdr workspace focus wN   # wN shows focused:true
$ herdr pane split --current --direction right --no-focus
{"new":"wM:pF"}             # WRONG WORKSPACE — split landed in the live swarm
```

**Conclusion (a):** `workspace focus` is UI cosmetics for scripting purposes — it does not steer pane split/agent commands. Commands route via explicit workspace-prefixed pane IDs. The V1 bug in `herdr-loop-swarm.sh` external mode is real, but the correct fix is **"always split explicit anchor pane IDs obtained from `tab_by_label`"**, not merely adding a `workspace focus` call. Scripts must never use `--current`. (Calling `workspace create --focus` is still good UX so the herd tab appears after setup.)

### A4. Workspace creation & teardown mechanics

- `herdr workspace create --cwd <dir> --label L --focus` creates ws + focuses atomically; a fresh workspace auto-creates tab `<ws>:t1` with anchor pane `<ws>:p1` running a shell at `--cwd`. No manual tab creation needed for the anchor.
- `herdr pane close <pane>` retires any agent hosted in that pane (observed: agent vanished from `agent list` on pane close). There is **no `agent stop`** command — retirement = close the hosting pane.
- `herdr workspace close <id>` disposes the workspace and its panes (agents retired with them).

---

## B. agent naming — global registry (V3)

### B1. Names are server-global, not per-workspace

Agent names occupy a single registry across all workspaces. Attempting to seat `looper` in the scratch workspace while the live `looper` exists in `wM` fails:

```
$ herdr agent start looper --kind opencode --pane wN:p1
{"error":{"code":"agent_name_taken",
 "message":"agent name looper is already used; candidates: terminal_id=… pane_id=wM:p6
            workspace_id=wM tab_id=wM:t2 cwd=/path/to/loop-bot-herd-agy status=Idle"}}
```

Same error for duplicates within one workspace. The error's candidate diagnostics conveniently report the existing holder's pane/workspace/cwd/status.

**Conclusion (b):** two simultaneous project swarms cannot both seat `arch`/`looper`/etc. Per-project namespacing is **mandatory** (e.g. `arch-<proj-slug>`), and `agent_alive`-style checks must use the namespaced name.

### B2. agent start is pane-routed (not focus-routed)

`herdr agent start probe-a --kind opencode --pane wN:p2` while `wM` was focused registered the agent under `wN` (`agent list` → `probe-a ws=wN`). The agent's workspace is inherited from its hosting pane.

### B3. Targets & rename

- Agent targets resolve by unique name or by hosting pane ID.
- `herdr agent rename <target> <name>` exists (also `--clear`); renames enforce the same global uniqueness.

---

## C. Legal characters in agent names (conclusion c)

Probed via `agent rename` (validation shared with `agent start` — `probe-a` was itself started with a hyphen):

| Candidate | Result |
|---|---|
| `probe-dash` (`-`) | **ACCEPT** (both start & rename paths) |
| `probe_us` (`_`) | **ACCEPT** |
| `probe·dot` (U+00B7 MIDDLE DOT) | REJECT `invalid_agent_name` |
| `pd.dot` (`.`) | REJECT |
| `pd sp` (space) | REJECT |
| `pd:col` (`:`) | REJECT |
| `pd/m` / `pd@m` | REJECT |
| `Pd-Cap` (uppercase) | REJECT |
| `9pd` (leading digit) | REJECT |

**Effective grammar: lowercase-start `[a-z][a-z0-9_-]*`** (lowercase letters, digits, hyphen, underscore; must begin with a lowercase letter).

**Design impact:** the brainstorm's proposed `arch·slug` scheme is **illegal**. Namespacing must use `-` or `_`: adopt `arch-<slug>`, `looper-<slug>`, `pm-<slug>`, `docs-<slug>`, `gh-<slug>`, `reviewer-<slug>` (slug derived from repo dirname, lowercased, `[^a-z0-9_-]` → `-`).

---

## D. Implications for M1 tickets

| Ticket | Implication |
|---|---|
| T-004 (workspace context) | Fix = explicit anchor-IDs everywhere (from `tab_by_label --workspace`), **ban `--current`** in scripts; optional `workspace focus` for UX after create; `--fresh` = `workspace close` + recreate. |
| T-005 (namespacing) | Global registry confirmed → `seat-<slug>` names mandatory; `agent_name_taken` error text is parseable to detect cross-project collisions and report the holder. |
| T-011 (`down`) | Teardown = close agent panes (agents retire automatically) → `workspace close`; keep `.herdr-swarm/`. |
| T-012 (supervisor pane) | Seating the loop-bot shell pane uses the same anchor-ID routing; no agent involved (plain pane). |

## E. Probe log (chronological receipts)

1. `workspace list` → `wK(~)`, `wM(loop-bot-herd-agy, focused, 14 panes/8 tabs, 5 agents)`.
2. `workspace create --cwd …/probe-t001 --label probe-t001 --focus` → `wN` (focused:true; anchor `wN:t1`/`wN:p1` at probe cwd).
3. `pane split --current` (wN focused) → **`wM:pF` (wrong ws)** → closed in cleanup.
4. `workspace focus wM`; `pane split --pane wN:p1 --direction down` → `wN:p2` (correct cross-ws routing).
5. `agent start probe-a --kind opencode --pane wN:p2` (wM focused) → agent registered `ws=wN`.
6. `agent start looper … --pane wN:p1` → `agent_name_taken` (holder reported in `wM`).
7. Rename sweep: `-`/`_` accept; `· . : space / @ uppercase leading-digit` reject.
8. Cleanup: `pane close wN:p2` (probe-a retired) → `workspace close wN` → `pane close wM:pF`. Final: workspaces `wK`,`wM(focused)`; wM back to 14 panes; agents exactly `looper,pm,arch,agy-docs,agy-gh`.
