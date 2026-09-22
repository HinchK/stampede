# demo-repo — one verified verdict, end to end

A stranger-size repository: one bash library (`lib/calc.sh`), one real
test suite (`tests/run_tests.sh`), three disjoint tickets. It exists so
you can watch Stampede's whole loop — seat → dispatch → suite gate →
integration — in minutes, without risking a real project.

The walkthrough below assumes you have Stampede checked out somewhere
(`$STAMPEDE`) and **one** agent CLI installed (`stampede doctor` says
which seats can run). You never need more than one.

## 0. Make the demo your own repo

Stampede supervises a *target* repo and profiles it fail-closed: it wants
a git repo and a GitHub remote *name* (nothing is ever pushed). So copy
the demo out of the Stampede checkout and give it both:

```bash
cp -r "$STAMPEDE/examples/demo-repo" /tmp/demo && cd /tmp/demo
git init -q && git add -A && git commit -qm "demo baseline"
git remote add origin https://github.com/you/demo.git   # placeholder, never pushed
```

## 1. Prove the baseline is green

```bash
make test
```

Seven assertions pass. This is the exact command the supervisor will
re-run later — it is the only thing allowed to call your work done.

## 2. Seat the swarm (no dispatch yet)

From the demo directory (replace `$STAMPEDE` with your checkout path):

```bash
"$STAMPEDE/bin/stampede" up . -m s
```

`-m s` seats agents and renders their briefs but dispatches nothing.
When it settles, confirm every seat is alive and brief-ready:

```bash
"$STAMPEDE/bin/stampede" verify .
```

## 3. Hand one ticket to one worker

Open `maps/tickets/demo-1-calc-pow.md`, read its three-part preamble
(Intended Outcome / Done-Criteria / Verification Step), then prompt your
worker seat by name (the launcher printed seat names when seating; in
Herdr you can also just type into the pane). Tell it, in one short line,
the ticket path — e.g.:

```
Work ticket maps/tickets/demo-1-calc-pow.md in this repo, on a branch.
```

The worker implements, commits, and emits the completion verdict line
from its standing brief:

```
ARCH DONE #DEMO-1 <commit-sha>
```

## 4. Watch the gate

The supervisor (`$STAMPEDE/loop-bot-herd.sh watch`, or the pane the
launcher started) harvests that line, checks the sha exists, and re-runs
`make test` itself — on the worker's tree, at that sha. It does not read
the worker's chat, does not trust the worker's own test run, and records
the verdict in `.herdr-swarm/session-verdicts.jsonl`:

```bash
cat .herdr-swarm/session-verdicts.jsonl
```

A green line there — not the worker's claim — is what retires a ticket.

### The RED path (worth doing once)

Sabotage it: `calc_pow` returns `$1 ** ($2 + 1)` — off by one exponent.
The gate goes RED, the ticket stays open, and the worker must fix and
re-verdict at a **new** sha. That loop is the product.

## 5. Integrate

Green verdicts queue for the arbiter. Run it (it re-tests the *combined*
result before advancing the integration ref):

```bash
"$STAMPEDE"/lib/arbiter.sh drain
"$STAMPEDE"/lib/arbiter.sh promote   # asks for explicit confirmation
```

`promote` fast-forwards `main` — and asks first, because only a human
moves `main`. Ever.

## 6. Tear down

```bash
"$STAMPEDE/bin/stampede" down . --yes
```

Panes the swarm opened close; panes you opened yourself are untouched;
worktrees are pruned with salvage for anything dirty.

## The tickets

| Ticket | owns (disjoint) | teaches |
|---|---|---|
| [DEMO-1](maps/tickets/demo-1-calc-pow.md) | `lib/calc.sh`, `tests/run_tests.sh` | implementation + suite gate |
| [DEMO-2](maps/tickets/demo-2-document-library.md) | `README.md` | a docs ticket can be gated too |
| [DEMO-3](maps/tickets/demo-3-make-count.md) | `Makefile` | the smallest possible ticket |

Dispatch them one at a time, or together — their `owns:` paths do not
overlap, which is exactly what partition checking enforces on real herds.
