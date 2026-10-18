# Agent workflow

This repo (ishaanko/dubhacks26) is built by one main Claude session that delegates to subagents.

## 1. Main thread

- One orchestrating Claude session. It plans the work and splits it into tasks.
- Each subagent gets explicit file ownership up front, so no two agents edit the same file.
- Launch subagents in parallel. Sonnet does real implementation. Haiku does simple tasks.
- Review results: screenshots, build, data checks. Relay findings to the user.
- The main thread does not edit files a subagent owns.

## 2. Subagents

- Each subagent works only inside its owned paths.
- It verifies its own work (build, typecheck, or run) before committing.
- It commits and pushes its own work through the Cursor CLI, so every commit is coauthored by Cursor.

## 3. Commit rules

- Branch: `main` for the app unification work (earlier work used `test/<topic>` branches). Agents in their own worktree commit on their worktree branch; the main thread merges into `main`.
- Commit through the Cursor CLI headless mode. The trailer is `Co-authored-by: Cursor <cursoragent@cursor.com>`. No other AI coauthor trailers.
- Stage only owned paths, by explicit path. Never `git add -A`, stash, reset, checkout, or rebase. The working tree is shared with agents that are still working.
- Message style: conventional commits, `<type>(scope): description`.
- Push right after committing. Then verify the trailer with `git log -1 --format=%B`.

## 4. Command template

```
agent -p --force --output-format text "On the current branch (do not switch branches). Other agents are editing files: do NOT stage, stash, reset or touch anything except these paths. Stage exactly: <paths>. Commit with this exact message followed by a blank line and 'Co-authored-by: Cursor <cursoragent@cursor.com>':

<type>(scope): <description>

<body>

Then run: git push origin HEAD. Then print git log -1 --format=%B."
```

## 5. Current layout

- `datasets/`: fetch, validate, and analysis of open foot datasets.
- `ios/`: the archy iPhone app (onboarding, LiDAR scan, measure, insole, train). See `ios/README.md`.
- `sim/`: browser pressure-to-heatmap-to-insole simulation, plus `sim/sandbox.html` sensor sandbox.
- `services/voice/`: optional narration proxy for the iOS read-aloud.
- `hardware/`: 6-FSR DIY foot pressure kit and firmware.
- `docs/`: research dossiers and this file.
