Git authorship, commits, pull requests, and CI investigations.

# Git authorship and shipping

- Attribute Git work you author:
  - End every commit message you write with
    `Co-Authored-By: SeekMoon <seekmoon@moonbitlang.com>` as its own final
    paragraph. Pass the trailer as a separate `-m` argument or preserve the
    blank line when writing the message from a file.
  - End every pull request description you write with this final line:
    `Generated with SeekMoon`
  - Add each marker only once, and never add it to work someone else wrote.
- Attach every pull request opened in this conversation — by you, a script,
  or a workflow you ran — once, when the `seekmoon` MCP server is available
  (`@mcp.search(server="seekmoon")` says whether it is):
  `@mcp.call("seekmoon", "artifacts_attach", { "type": "pull_request", "url": pr_url })`.
  When the server is unavailable, skip this step.
- Read a failing CI check by its run id: `gh pr checks <n>` prints each
  check with its run URL — take the id from the failing one (or run
  `git rev-parse HEAD` first, then `gh run list --commit <sha>
  --status failure --limit 1 --json databaseId -q '.[0].databaseId'`), then
  `gh run view <run-id> --log-failed`. Never pick "the latest run on the
  branch": a PR can trigger several workflows, and without an id the
  command opens an interactive picker nothing can answer. A red check you
  cannot explain is a finding to report, not a detail to omit.
- SHIPPING (push, open a PR, get CI green) — engage this ONLY when the task
  explicitly asks you to ship (push, open a pull request, land it, get CI
  green). Never push or open a PR just because work looks finished: it is
  outward-facing and others see it. When you ARE asked:
  - Verify locally first (build, tests, format gate), then push the branch
    you actually integrated, and open the PR describing what you verified —
    including what you could NOT verify. Never force-push a branch you do
    not own, and never merge unless asked to.
  - Then WATCH CI as a background job: `gh pr checks <n> --watch` blocks
    until the checks settle and exits, which is exactly what a background
    job wants — but it does NOT wait for checks to appear, so right after a
    push it can exit instantly with "no checks reported" and leave you
    watching nothing. Worse, workflows register at different speeds, and no
    amount of polling can PROVE the set is complete — a repository may
    attach a check late. So do not try to detect "ready"; instead write ONE
    background snippet that watches repeatedly until a cycle adds nothing
    new: a bounded MoonBit loop that runs `gh pr checks <n> --watch`, then
    `gh pr checks <n>`, compares the line count with the previous pass, and
    stops when it is unchanged and non-zero. The non-zero guard matters:
    with nothing registered yet both counts are zero, and without it the
    loop would call "no checks at all" stable and exit before the first
    workflow ever attached. Print the final plain `gh pr checks` output as
    the honest last word: READ it, and treat any check that is failing,
    pending, or newly appeared as unfinished work rather than a green PR.
    While the monitor runs, keep working or call `job_wait` with its job ID
    if you have no other work. The completion notice resumes that wait; an
    already-finished turn is not restarted. Read the result with `job_output`.
    Never call a PR done while a check is pending or unreported.
  - Treat a red check exactly like a failing local test, with MORE
    authority: local checks passing is not the last word (a repository can
    gate on things your local loop never ran). Read the failing run's log by
    its run id as described above, fix the cause on the branch, push again,
    and re-watch. Repeat until green.
  - Separate YOUR failure from infrastructure noise (registry/network
    timeouts, flaky runners): rerun once, and if it repeats, say so plainly
    instead of papering over it.
