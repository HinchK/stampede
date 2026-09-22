---
id: T-006
title: "Brief Templating Syntax and Nonce File Protocol"
type: wayfinder:prototype
status: closed
assignee: looper
prototype_asset: lib/briefs.sh
owns: lib/briefs.sh
templates_dir: briefs/
parent: maps/universal-herdr-swarm.md
github_issue: 23
github_url: "https://github.com/HinchK/stampede/issues/23"
synced_at: "2026-09-22T03:50:13Z"
---

# Brief Templating Syntax and Nonce File Protocol

## Question

What placeholder syntax (`{{REPO}}`, `{{TEST_CMD}}`, `{{DOCS_DIR}}`, `{{ARCH_NAME}}`) and file-based nonce exchange protocol should be adopted to generate project-specific briefs at launch (`.herdr-swarm/briefs/`) and deliver them to seats without hitting terminal prompt size limits or dropping characters?

## Resolution

Implemented in [`lib/briefs.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/briefs.sh) and converted briefs into template definitions in `briefs/*.in.md`:
1. **Dynamic Placeholder Architecture:**
   - Placeholders (`{{REPO}}`, `{{TEST_CMD}}`, `{{ECOSYSTEM}}`, `{{DOCS_DIR}}`, `{{SLUG}}`, and namespaced agent names `{{ARCH_NAME}}`, `{{LOOPER_NAME}}`, etc.) are resolved from `lib/profile.sh` and `lib/config.sh`.
   - Rendered briefs are generated on the fly into `${TARGET_DIR}/.herdr-swarm/briefs/*.md`.
2. **Elimination of Kultivait Hardcoding:**
   - Fixed `looper.in.md`, `arch.in.md`, `worker-docs.in.md`, and `worker-gh.in.md` so that test commands, remote repo targets, and docs directories reflect the host project's actual detected environment.
3. **File-Path Nonce Handshake (Upstream #215/#216 Lesson):**
   - Replaced multi-kilobyte inline `herdr agent prompt` dumps with a concise pointer prompt (<200 bytes):
     `STANDING BRIEF: You are seated as '<seat>'. Your standing brief is rendered at '<path>'. Read it immediately using your file viewing tools...`
   - Verified that agents load the rendered markdown directly from disk without buffer truncation.
