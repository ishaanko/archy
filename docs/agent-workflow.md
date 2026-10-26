# Agent workflow

Much of this repo was built by one main Claude session that hands work to subagents.

## Main thread

- Plans the work and splits it into tasks.
- Gives each subagent explicit file ownership up front, so no two agents edit the same file.
- Runs subagents in parallel. Sonnet does implementation, Haiku does simple tasks.
- Checks results with screenshots, builds and data checks, then reports back.
- Does not edit files a subagent owns.

## Subagents

- Work only inside their owned paths.
- Verify their own work (build, typecheck, or run) before committing.
- Stage only owned paths, by explicit path. Never `git add -A`, stash, reset, checkout or rebase, because the working tree is shared with agents still running.
- Agents in their own worktree commit on that worktree's branch. The main thread merges into `main`.

## Commits

Conventional commits: `<type>(scope): description`.
