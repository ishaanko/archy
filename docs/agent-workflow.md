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

- Branch: always a `test/<topic>` branch (currently `test/data-sim`). Never commit to or push to `main`.
- Commit through the Cursor CLI headless mode. The trailer is `Co-authored-by: Cursor <cursoragent@cursor.com>`. No other AI coauthor trailers.
- Stage only owned paths, by explicit path. Never `git add -A`, stash, reset, checkout, or rebase. The working tree is shared with agents that are still working.
- Message style: conventional commits, `<type>(scope): description`.
- Push right after committing. Then verify the trailer with `git log -1 --format=%B`.

## 4. Command template

```
agent -p --force --output-format text "On branch test/data-sim (do not switch branches). Other agents are editing files: do NOT stage, stash, reset or touch anything except these paths. Stage exactly: <paths>. Commit with this exact message followed by a blank line and 'Co-authored-by: Cursor <cursoragent@cursor.com>':

<type>(scope): <description>

<body>

Then run: git push origin test/data-sim. Then print git log -1 --format=%B."
```

## 5. Current layout

- `datasets/`: fetch, validate, and analysis of open foot datasets.
- `sim/`: browser pressure-to-heatmap-to-insole simulation, plus `sim/sandbox.html` sensor sandbox.
- `hardware/`: 6-FSR DIY foot pressure kit and firmware.
- `docs/`: research dossiers and this file.
