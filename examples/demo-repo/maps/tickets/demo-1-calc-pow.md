---
id: DEMO-1
title: "Add calc_pow (integer exponentiation) to lib/calc.sh"
type: demo:task
status: ready
assignee: any-worker
owns: lib/calc.sh,tests/run_tests.sh
parent: examples/demo-repo/README.md
---

# DEMO-1 — Add `calc_pow`

## 1. Intended Outcome

`lib/calc.sh` gains `calc_pow <base> <exp>` (non-negative integer
exponent) with tests in `tests/run_tests.sh` covering exp 0, exp 1, and a
general case. Negative exponents fail loudly, mirroring `calc_div`'s
divide-by-zero discipline.

## 2. Explicit Done-Criteria

- `calc_pow 2 10` prints `1024`; `calc_pow 7 0` prints `1`.
- Negative exponent exits non-zero with a stderr message.
- `make test` green including the new assertions.

## 3. Verification Step

```bash
make test && bash -c 'source lib/calc.sh && [ "$(calc_pow 2 10)" = 1024 ]'
```

Emit `ARCH DONE #DEMO-1 <commit-sha>` from your pane when finished.
