---
id: DEMO-3
title: "Add a make target that prints the current test count"
type: demo:task
status: ready
assignee: any-worker
owns: Makefile
parent: examples/demo-repo/README.md
---

# DEMO-3 — `make count` target

## 1. Intended Outcome

`make count` prints the number of assertions in the suite (counted from
`tests/run_tests.sh`, not hardcoded), so the walkthrough can show the
suite growing ticket by ticket.

## 2. Explicit Done-Criteria

- `make count` prints an integer matching the real assertion count.
- `make test` unchanged and green.

## 3. Verification Step

```bash
make test && make count
```

Emit `ARCH DONE #DEMO-3 <commit-sha>` from your pane when finished.
