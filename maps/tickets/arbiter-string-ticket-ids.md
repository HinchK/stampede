---
id: ARB-STR
title: "Arbiter queue must accept string ticket ids (repo vocabulary is P3-4-spec / T-017 style, not numeric)"
type: wayfinder:defect
status: resolved
commit: pending
assignee: pi
owns: lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/universal-herdr-swarm.md
---

# ARB-STR: the queue schema rejected the repo's own ticket ids

`arbiter_enqueue`/`_arb_set_status` passed the ticket through jq
`--argjson t`, so any non-numeric id (`P3-4-spec`, `T-017`, `P3-FLAKE-1` —
the entire `maps/tickets/` frontmatter vocabulary) made jq error and the
record silently vanished (`_arb_record ""` appended an empty line). The
arbiter literally could not be used on `pm` output.

**Fix:** ticket is a string end-to-end (`--arg t`); numeric ids still work,
round-tripping as strings. `_partition_ticket_active` already compared via
`(.ticket|tostring)`, so partition↔arbiter interop is unchanged.

**Verification Step**

    /bin/bash tests/test_arbiter.sh   # 30/30 incl. §9: enqueue "P3-4-spec"
                                      # → drain → integrated, --no-ff merge
                                      # commit "integrate #P3-4-spec", re-enqueue
