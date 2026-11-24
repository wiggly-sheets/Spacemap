---
id: mem-GtmYcBvb
title: Keep the PR-gated memory workflow enabled; squash-merge memory PRs and keep machine paths out of bodies
tags:
  - workflow
  - memory
  - feedback
author: Zeb Mikula
source: memory_propose
proposed_at: 2026-11-24T08:15:34.617Z
---
In wiggly-sheets/Spacemap the user chose to keep the opencode-plugin-memory PR flow running ("itll help you agents out"), even though the repo is public and each approved memory adds a branch plus a merge commit to `main`.

Rules that follow from that decision:
- Never untrack or gitignore `memory/`. The plugin's bot stages with `git add --all memory` inside a throwaway worktree, so ignoring the folder silently breaks every proposal. Only `.memory/` (staging, audit log) is machine-local and ignored.
- Squash-merge memory PRs so `main` does not accumulate merge commits.
- Memory bodies go public: do not put home-directory paths, temp paths, hostnames, or account details in them. Describe the rule or the lookup, not this machine.
- The plugin has no local-only or enable/disable switch; the only off switch is removing it from the `plugins` array in the opencode config.
