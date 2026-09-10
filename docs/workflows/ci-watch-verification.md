# CI monitor verification — 2026-09-10

`ci-watch.mbtx` is deterministic and uses `moonbitlang/core/argparse` for CLI
parsing/help. It calls authenticated `gh pr view --json` through an argument
array, without a shell or model. The script bounds both each child process and
the overall watch. It pins the first PR URL/head and refuses to combine
snapshots across head changes.

## Offline verification

The actual Wasm script compiled with warnings denied and passed 25 snapshot /
watch scenarios plus four invalid-argument cases in `ci_watch.py`. These cover
successful checks, external statuses, mixed skips, no checks, only neutral or
skipped checks, unknown/missing conclusions, malformed snapshots, delayed
registration, pending-to-success, late failure, head replacement, terminal
failure states, API failure, invalid JSON, and deadline expiration. Watch tests
require two matching completed snapshots. Fixtures also verify that polling
pins the PR URL, missing output fields use JSON null rather than payload
sentinels, and failed Actions checks produce the expected log-command argv.

All 17 existing hosted-workflow scenarios passed. The mbtx native suite passed
86 tests with `OPENSEEK_REFERENCES` pointing to this checkout's `share/`,
including `@builtin/ci-watch.mbtx` argument forwarding and help/error handling.
That outer-tool test is offline; it does not authenticate with GitHub.

`moon info`, `moon fmt`, `just check-prompt`, and native/JS builds passed. No
public interfaces changed. Local full checks/tests still hit existing
unsupported tuple-pattern loop syntax in `deepseek/client/openrouter_wbtest.mbt`
and desktop/editor tests with this installed compiler.

## Live verification

Ran the actual Wasm script with real `gh` authentication:

```text
ci-watch.mbtx 1427 --repo moonbitlang/openseek --once
PR: https://github.com/moonbitlang/openseek/pull/1427
Head: 0d4ca8a72cca46b35701acc8f73409d3ccd30e41
pass=10 skip=0 pending=0 fail=1
CI FAILED
exit: 1
```

The failed check was `CI / check (stable, native)`. The script supplied the job
URL and `gh run view 34437873128 --repo github.com/moonbitlang/openseek
--log-failed` as an argument array. Running that diagnostic separately
confirmed the failure: `agent_subrun/runner_test.mbt:116` expected `MaxSteps`
but observed `TimedOut` (3,271 of 3,272 native tests passed). The offline workflow
step had already passed. This was a real failed-CI observation, not a failure
of the monitor. The observed head predates the commit adding this monitor;
subsequent pushes start a separate CI generation.

The live run exercised MoonRun → gh → GitHub; the offline mbtx test separately
covers bundled dispatch/arguments. Success and watch transitions were verified
with fixtures, not by waiting for an entire live CI cycle. The monitor only
reports returned checks: it cannot prove required-check coverage, account for
workflows not yet registered, or establish merge readiness. Log retrieval is
suggested, not automatic, and no jobs were rerun.
