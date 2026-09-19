---
id: T-002
title: "Profile Detection and Fail-Closed Target Policy"
type: wayfinder:prototype
status: open
assignee: unassigned
blocked_by: []
parent: maps/universal-herdr-swarm.md
---

# Profile Detection and Fail-Closed Target Policy

## Question

What exact fallback and caching strategy should `lib/profile.sh` follow when detecting repository remotes, ecosystem manifests, and test runners, and how does `.herdr-swarm/profile.env` enforce fail-closed behavior to completely prevent defaulting to `Standard-Pentest/kultivait` or allowing a fake-green test gate (`TEST_CMD="true"`)?
