---
id: DOG-14
title: "The 0-warning lint bar is version-dependent: CI's shellcheck fails what the dev shell passes"
type: wayfinder:defect
status: in_progress
assignee: arch-1
owns: .github/workflows/ci.yml,lib/preflight.sh
parent: maps/public-readiness.md
github_issue: 10
github_url: "https://github.com/HinchK/stampede/issues/10"
synced_at: "2026-09-21T22:28:00Z"
---

# DOG-14 — Pin the lint toolchain

> Found by DOG-3's CI on its first run, on PR #9. The repo's own lint gate is
> not reproducible across machines.

## 1. Intended Outcome

`make lint` gives the same verdict on a dev shell and on both CI runners,
because the tool that decides it is pinned rather than whatever the platform
package manager happens to ship.

## 2. Problem

PR #9, `make check (ubuntu-latest)`:

```
In lib/preflight.sh line 172:
preflight_report_text() { # FD
^-- SC2120 (warning): preflight_report_text references arguments, but none are ever passed.

In lib/preflight.sh line 198:
preflight_report_json() { # FD — requires jq
^-- SC2120 (warning): ...

In lib/preflight.sh line 235:
    if ! preflight_report_json; then
         ^-- SC2119 (info): Use preflight_report_json "$@" ...

make: *** [Makefile:30: lint] Error 1
```

Locally, shellcheck **0.11.0** reports the same file clean (`rc=0`), and so does
the macOS leg, which uses Homebrew's current build — its log line is
`Lint clean (14 shell files)`. Ubuntu installs shellcheck from `apt`, which is
older and applies the SC2119/SC2120 heuristic differently.

Verified: these findings are **not** a regression introduced by this backlog.
The same check at the clone base `924619d` also reports 0 SC2119/SC2120 under
0.11.0 — the functions are unchanged. The *tool* changed, not the code.

So the repo's stated bar, "0 shellcheck warnings", currently means "0 warnings
on whatever shellcheck you happen to have installed." That is the same class of
defect as DOG-1: an unpinned tool making green machine-dependent.

## 3. Scope

Do **both**, in this order — they fix different halves:

1. **Make the source clean under old and new shellcheck alike.** For each
   SC2119/SC2120 site in `lib/preflight.sh`, either pass `"$@"` through as the
   older heuristic expects, or add a narrowly-scoped
   `# shellcheck disable=SC2120` with a one-line reason. Prefer passing `"$@"`
   where the function genuinely takes an optional FD; use the directive only
   where it does not.
2. **Pin the tool in CI** so this cannot drift again: install a fixed
   shellcheck release on **both** legs rather than taking `apt`'s or Homebrew's
   current build, and print the version in the existing "Record toolchain" step
   (it already does — keep it).

Do not raise the bar to silence the finding (no `-S error`), and do not remove
the lint gate from `make check`.

## 4. Done-Criteria

1. `shellcheck lib/preflight.sh` is clean under the pinned version **and** under
   0.11.0.
2. Both CI legs install the same pinned shellcheck version, and the version
   appears in the job log.
3. `make check` green on `macos-latest` and `ubuntu-latest`.
4. Any `disable=` directive added carries a one-line reason and is scoped to the
   specific line or function, never file-wide.

## 5. Verification Step

```bash
shellcheck --version | sed -n '2p'
make lint
grep -n 'shellcheck' .github/workflows/ci.yml
grep -rn 'shellcheck disable' lib/preflight.sh
```

The receipt must name the pinned version and show the PR's CI going green on
both legs.
