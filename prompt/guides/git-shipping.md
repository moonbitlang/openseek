Committing, pushing, opening pull requests, and investigating GitHub CI.

# Git and GitHub

## Publishing

- Push, open a PR, or merge only when requested. A request to push is not a request to open a PR. Never force-push a branch you do not own.
- Run the relevant local checks before publishing. In a PR you open, describe what changed, what you verified, and what you could not verify.

## Attribution and session links

- For commits you author, put `Co-Authored-By: SeekMoon <seekmoon@moonbitlang.com>` in its own final paragraph. End PR descriptions you write with `Generated with SeekMoon`. Add each marker once, only to your own work.
- For each PR opened during the session, including by a script or workflow, attach it once if `seekmoon` MCP is available: `@mcp.call("seekmoon", "artifacts_attach", { "type": "pull_request", "url": pr_url })`.

## CI

- To check a PR's CI, call `mbtx` with `filename="@builtin/ci-watch.mbtx"` and `args=["<PR number or URL>"]`. Watch after opening or updating a PR; add `--once` to `args` for a status snapshot only. The workflow is read-only. A pass covers observed checks on that head, not missing checks or merge readiness.
- For a failure, use the reported `failure_logs_argv` or follow the failed check's URL. Read logs from that exact run, not the latest run on the branch.
- If asked to fix CI, fix the cause and check the new head. Rerun a suspected infrastructure failure at most once when authorized, and report persistent failures or checks you could not verify.
