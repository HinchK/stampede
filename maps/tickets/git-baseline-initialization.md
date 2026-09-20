---
id: T-014
title: "Foundations: Git Baseline Initialization"
type: wayfinder:task
status: closed
assignee: arch
resolution_commit: 95044cc
owns: .gitignore,README.md
parent: maps/universal-herdr-swarm.md
---

# Foundations: Git Baseline Initialization

## Question

How should the `loop-bot-herd-agy` repository be initialized as a standalone Git repository with proper ignoring of transient artifacts to support atomic conventional commits for all subsequent work?

## Resolution

- Initialized Git repository on branch `main`.
- Created comprehensive `.gitignore` excluding `.herdr-swarm/`, `__pycache__/`, `*.pyc`, `.DS_Store`, `.env`, `*.log`, `.vscode/`, and preview artifacts (`.clearance-rendered-preview-*/`).
- Baseline committed in commit `95044cc`: `chore: initial repository baseline (#T-014)`.
- Verified clean working tree via `git status --porcelain`.
