---
id: DOG-7
title: "Make the kultivait/pi local engine completely optional"
type: wayfinder:defect
status: resolved
commit: a00fafa
assignee: arch-1
owns: swarm.config.toml,briefs/pi.md,briefs/pi.in.md,lib/gh_sync.sh,loop-bot-herd.sh,herdr-loop-swarm.sh,lib/config.sh,lib/briefs.sh
parent: maps/public-readiness.md
github_issue: 13
github_url: "https://github.com/HinchK/stampede/issues/13"
synced_at: "2026-09-21T18:40:00Z"
---

# DOG-7 — kultivait fully optional (WAVE 3, RUNS ALONE)

## 1. Intended Outcome

A clone on a machine that has never heard of kultivait seats cleanly, and the
word survives only in ADRs and audits as history.

## 2. Problem

`#PROXY-GATE` did real work — `[proxy] enabled` defaults `false`, and both the
launcher's proxy start (`herdr-loop-swarm.sh:570`) and the supervisor's credits
probe (`loop-bot-herd.sh:428`) are correctly gated. What remains:

1. **`seats.pi` is enabled by default** (`swarm.config.toml:63-70`) with
   `default_kind = "pi"` and `model = "kultivait/auto"`. The kind is passed
   straight to `herdr agent start --kind` (`herdr-loop-swarm.sh:465`), so on any
   machine without a `pi` runtime this seat fails to seat.
2. **`briefs/pi.md` has no `.in.md` template** — the only brief in that state,
   so it is hand-authored while looking generated.
3. `KULTIVAIT_CREDENTIALS` / `~/.kultivait/credentials.toml` (`loop-bot-herd.sh:429`).
4. `serve_cmd = "uv run kultivait serve"` ships as a live default
   (`swarm.config.toml:25`).
5. `localhost:4114` hardcoded in `lib/config.sh:131-132`, `lib/briefs.sh:75`,
   `herdr-loop-swarm.sh:287,570`.
6. `Standard-Pentest/kultivait` as the example slug in `lib/gh_sync.sh:195` — a
   private third-party repo name in user-facing help text.

## 3. Scope

1. Add `enabled = false` to `[seats.pi]`. **The mechanism already exists and is
   already used** — `[seats.reviewer]` carries it and `lib/config.sh:137` honours
   it by dropping the seat from `SEAT_KEYS`. Do not invent a new one.
2. Either add `briefs/pi.in.md` or remove `briefs/pi.md` with the seat. State
   which, and why, in the receipt.
3. Rename `KULTIVAIT_CREDENTIALS` to `PROXY_CREDENTIALS`, with the path as config
   data under `[proxy]`, matching how `serve_cmd` and `health_check_url` were
   already generalised.
4. Empty `serve_cmd`; document the kultivait value in a comment.
5. Replace the `localhost:4114` literals with reads from `[proxy]`.
6. Change the `gh_sync.sh` example slug to a neutral one.

**Do not scrub `kultivait` from `docs/adr/` or `docs/audits/`.** Those record
*why* the fail-closed profile policy exists; erasing them destroys the provenance
this repo's whole thesis rests on.

## 4. Done-Criteria

1. `grep -rn kultivait --include='*.sh' --include='*.toml' .` returns only
   comments, no executable default.
2. `bash lib/config.sh dump stampede` lists no `pi` seat in `SEAT_KEYS`.
3. `grep -rn '4114' lib/ *.sh` — no hardcoded literal outside `swarm.config.toml`.
4. ADR and audit occurrences untouched.
5. `make check` green; `shellcheck` 0 warnings.

## 5. Verification Step

```bash
bash lib/config.sh dump stampede | grep SEAT_KEYS     # must not contain "pi"
grep -rn kultivait --include='*.sh' --include='*.toml' .
grep -rn '4114' lib/ *.sh
git diff --stat -- docs/adr docs/audits               # want EMPTY
make check
```

## 6. Notes

Touches `loop-bot-herd.sh` and `lib/config.sh`, which DOG-1 also owns. Runs alone,
after DOG-1 has integrated.
