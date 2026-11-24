---
id: mem-7PojmYSW
title: "Floorplan skill for OpenCode: installed patched copy, update procedure, exclude-glob gotcha"
tags:
  - tooling
  - floorplan
  - opencode
  - skills
author: Zeb Mikula
source: memory_propose
proposed_at: 2026-11-24T07:37:35.581Z
---
Floorplan (haydenschmitty/floorplan) ships only Claude Code and Codex manifests, but its engine is a plain agent skill, so it runs in OpenCode after two steps:

1. Copy `skills/floorplan` from the clone at `~/Developer/floorplan` into `~/.config/opencode/skills/floorplan` (global, so every project sees it). OpenCode picks it up live; no restart.
2. Patch the copied `SKILL.md`, because OpenCode ignores Claude-only syntax: replace every `${CLAUDE_SKILL_DIR}` with the absolute install path, replace the `!`-prefixed status pre-execution line and `$ARGUMENTS` with ordinary instructions, and drop reliance on `allowed-tools:` frontmatter. Patch script lives at /private/var/folders/.../opencode/patch-floorplan.mjs (outside the clone, so it is not kept by git).

Updating: `git pull` in `~/Developer/floorplan`, re-copy the folder over the installed skill, re-run the patch script. Never edit the installed copy and expect it to survive an update.

Mapping this repo: build with `FLOORPLAN_UNATTENDED=1 node ~/.config/opencode/skills/floorplan/scripts/build.mjs . --json`. Writes a git-ignoring `floorplan/` with index.html + graph.json; verify `files.unassignedPercent` under 10. The map's Ask bar drives `claude -p` or `codex exec`, never OpenCode, so name that when a user expects in-map chat.

Gotcha when authoring architecture.json: a node's `exclude` globs are inherited by all its descendants. Putting parent-level `exclude` on a parent whose children claim those same files makes every child glob match nothing and the build fails with "path … matches no included file". Leave `exclude` off the parent and rely on deepest-glob-wins.
