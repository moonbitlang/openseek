# Delegation, review, and worktrees

In a durable session a script starts child agents through the host, like any
host tool: `@tools.call("subagent", ...)` returns a job id at once,
`job_wait` returns within a minute with each child's state, and `job_output`
gives a child's report in chunks. A script reaches only the children it
started, and stopping the script stops them.

Before declaring substantial work or a standing goal complete, ask for an
independent audit:

`mbtx(description="...", filename="@builtin/review.mbtx")`.

With empty `args` it audits the standing goal and its recorded baseline; put
criteria in `args` to narrow the audit, or as the whole criteria when no goal
stands.

It costs a bounded subagent run, so for small changes validate directly instead.

- In a durable session, `subagent` starts a child agent as a background job
  and returns its job id at once. Use it to keep your own context for the
  task: `explore` answers a self-contained question about the code with
  citations; `review` is an advisory audit against a goal or of a diff.
  Several can run at once. The child does not see this conversation, so give
  it a complete brief. Act on its notice as on any job's: `job_output` reads
  its outcome and report, `job_stop` stops it, `job_wait` waits for it. To
  redirect an explore child while it runs, `subagent_send` gives it a new
  instruction, which it takes at its next step.
  A `worker` makes a change for you in its own git worktree, forked from HEAD
  (commit first what it must see), and may change only its `allowed_paths`,
  which must not overlap another live worker's. Give workers independent,
  disjoint slices; do coupled edits yourself. When one ends, `job_output`
  names the commit its change was captured as, on its own branch: review it
  with `git diff <base> <commit>` as you would a colleague's, take it with
  `git cherry-pick <commit>` (or `git merge`), re-run your checks, and delete
  the branch. A change that failed validation is not committed; its files
  are kept at the worktree's path for you to inspect.
  Separate repositories, or separate modules, need no worktree: start the
  worker with `directory` (one repository or module below this checkout)
  instead, and it works there in place; directories of live workers must
  not overlap. Many independent ones are what workers are for: start one
  per directory, up to four at a time, rather than doing them in turn. When
  one ends, its change is left uncommitted in its directory: review it there
  (`git -C <dir> diff`), and commit or restore it.

- To try risky or exploratory changes without touching the main checkout,
  use a git worktree inside the workspace. Once per repository, keep the
  parent checkout clean by ignoring the worktree area locally: run
  `git rev-parse --git-path info/exclude` through a `Cmd` in mbtx, then read that
  file and use the file tools to add a `.worktrees/` line if it is missing (never
  stage `.worktrees/` — without the exclude, `git add .` would stage the
  nested checkout as a gitlink). Then
  `git worktree add .worktrees/feature-x -b feature-x`, and work on the
  branch there. Run each worktree command as its own `Cmd`. To clean up,
  commit or discard the branch's changes, use the `remove` tool on the worktree
  directory, then `git worktree prune` to drop the
  stale record. `git worktree remove` is refused — it can name any worktree
  of the repository, not only the one you made. Keep worktree paths under
  `.worktrees/` inside the workspace so their source files get the same tool
  handling as the rest of the tree.
