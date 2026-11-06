# Commit-graph fsck diagnosis — 2026-11-05

**Date:** 2026-11-05 · **Author:** hygiene sprint · **Scope:** local clone of `HinchK/stampede`

## Commands

```bash
git fsck --full --no-dangling
git commit-graph write --reachable --changed-paths
git fsck --full --no-dangling
```

## Before

- Exit code: 16
- Unreadable commit-graph OIDs:

```
error: Could not read 0a60dd1f49aef8a3a9b8c20ac38fa546f442c0af
failed to parse commit 0a60dd1f49aef8a3a9b8c20ac38fa546f442c0af from object database for commit-graph
error: Could not read 3a127314f655239ae2cc5d1d99a4e7a2aab9fd2d
failed to parse commit 3a127314f655239ae2cc5d1d99a4e7a2aab9fd2d from object database for commit-graph
error: Could not read 3e8250a84f2a823390c16d86b169592c4c82f68e
failed to parse commit 3e8250a84f2a823390c16d86b169592c4c82f68e from object database for commit-graph
error: Could not read 5a7d5475df927f2d21d2f43f556859884785b0ce
failed to parse commit 5a7d5475df927f2d21d2f43f556859884785b0ce from object database for commit-graph
error: Could not read 70b37c3f9a3cd2be273bc7a12409cc45b3817870
failed to parse commit 70b37c3f9a3cd2be273bc7a12409cc45b3817870 from object database for commit-graph
error: Could not read 8540e2a067991421f8b7d8c7732937a6014457eb
failed to parse commit 8540e2a067991421f8b7d8c7732937a6014457eb from object database for commit-graph
error: Could not read 8bd91c7dd4f72ce407736ea564c3fed5043a352c
failed to parse commit 8bd91c7dd4f72ce407736ea564c3fed5043a352c from object database for commit-graph
error: Could not read 99a00b1b8b9ad92eda8a1150265a2baadebe9bed
failed to parse commit 99a00b1b8b9ad92eda8a1150265a2baadebe9bed from object database for commit-graph
error: Could not read a303f23cb6a0f4f13aa66024a84f58e4a4bfec26
failed to parse commit a303f23cb6a0f4f13aa66024a84f58e4a4bfec26 from object database for commit-graph
error: Could not read a714aaff6ada4d5f0e63cb34086eb9d2c681f614
failed to parse commit a714aaff6ada4d5f0e63cb34086eb9d2c681f614 from object database for commit-graph
error: Could not read ada7b5d70da5c25e36c8055b3095dc56b2603064
failed to parse commit ada7b5d70da5c25e36c8055b3095dc56b2603064 from object database for commit-graph
error: Could not read eaaf10ccbebcc1a79770ebfb6490e071e5865181
failed to parse commit eaaf10ccbebcc1a79770ebfb6490e071e5865181 from object database for commit-graph
```

## After

- Exit code: 0
- Missing objects remaining: none

## Conclusion

Stale commit-graph: rewrite made `git fsck --full --no-dangling` exit 0. Reachable history was intact; the graph files named deleted commits.

No objects were pruned. `.git/` was not committed.
