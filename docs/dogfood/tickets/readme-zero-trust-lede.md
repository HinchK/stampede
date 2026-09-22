---
id: DOG-5
title: "Above-the-fold: lead with the Zero Trust thesis; drop the Autonomous claim"
type: wayfinder:doc
status: backlog
assignee: agy-docs
owns: README.md
parent: maps/public-readiness.md
---

# DOG-5 — README lede (WAVE 2)

## 1. Intended Outcome

A reader's first screen states the thesis and the mechanism, not a Mermaid
diagram — and claims nothing the repo cannot back.

## 2. Problem

- `README.md:3` calls the project **"Autonomous Multi-Agent Orchestration
  Swarm"**. The repo's own external review states there is no unattended path:
  every mode assumes a human at a Herdr floor. Publishing "autonomous" invites
  exactly the scrutiny the Zero Trust framing would otherwise earn respect for.
- The first thing a reader meets is an architecture graph. The thesis is what
  earns the scroll, and it currently appears nowhere.

## 3. Scope

Replace the title and tagline (`README.md:1-3`), placing this **above** the
Mermaid diagram:

```markdown
# Stampede

**Zero Trust for LLM compute nodes.**

A coding agent is an untrusted worker that will optimize for the laziest path to
a green build. Stampede seats a herd of them against your repository and refuses
to take their word for anything.

Every claim of "done" is an unverified assertion until an independent supervisor
re-runs your real test suite against the exact commit — in the exact tree that
produced it. Implementation agents work in isolated worktrees and never merge.
Green verdicts are queued for an arbiter, which re-tests the *combined* result
before advancing an integration ref by compare-and-swap. Only a human moves
`main`.

The result is a system that systematically neutralizes the AI equivalent of
gaming the CI pipeline. It costs more compute than trusting the agent. That is
the trade.
```

### The claim must be scoped to isolated seats

Observed during the DOG-12 run, and the reason the lede above says
"implementation agents" rather than "workers": **only `worktree = true` seats are
gated at all.** From `.herdr-swarm/seats.json` on a live floor:

| seat | isolated | branch |
|---|---|---|
| `pm`, `looper`, `agy-docs`, `agy-gh` | 0 | `main` |
| `arch-1`, `arch-2`, `pi` | 1 | `swarm/<slug>/<seat>` |

Four of seven seats commit **directly to the base branch** with no worktree, no
suite gate, no arbiter and no human. An unqualified "nothing lands unverified"
is false, and `agy-docs` demonstrated it by landing both a premature completion
claim and a non-existent command flag on `main` inside one hour (see DOG-12 §6).

So the README must not claim blanket verification. Either scope every such
sentence to implementation agents, or add one honest line near the lede —
something like: *documentation and coordination seats commit directly to the
base branch; the gate covers code.* Do not quietly omit it; a reader who
discovers this themselves will trust nothing else on the page.

**Verb discipline — do not upgrade these.** Verified:

| Stage | Wired? |
|---|---|
| green verdict to `arbiter_enqueue` | automatic (`loop-bot-herd.sh:261`) |
| `arbiter_drain` | operator-invoked, no caller |
| `arbiter_promote` | operator-invoked, by design |
| `partition_check` / `lease_acquire` | **no caller at all** |

"are queued for an arbiter, which re-tests" is true of that. "automatically
drains" would not be. Do not describe the partition/lease layer as an active
defense — it ships and is tested, but nothing calls it.

## 4. Done-Criteria

1. The lede appears before the Mermaid block.
2. The tagline no longer says "Autonomous". The "Fail-Closed Autonomous Gate"
   heading near `:159` describes a real mode and stays.
3. No claim in the new prose describes an unwired mechanism as automatic.
4. No sentence claims blanket verification; the gate's scope (isolated
   implementation seats only) is either stated or the claim is scoped to them.
5. Only `README.md` is modified.

## 5. Verification Step

```bash
sed -n '1,25p' README.md
grep -n 'Autonomous' README.md                                # tagline hit must be gone
grep -n 'automatically drain\|partition check runs' README.md # want 0
```

## 6. Notes

Repo-wide rename and link conversion is DOG-9 — do not start it here.
