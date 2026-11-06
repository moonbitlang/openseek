# Verified `openseek run` Requests and Results

These examples are executed by `moon testcli test --target native tests/cram/run-requests.md`. They drive
`openseek run --input-format json` through the real binary: one JSON request
on stdin, the result in `--result-file` (the contract is `docs/run-result.md`).
The `echo` preset is modelless, and the model-backed cases point at a closed
local port, so the suite needs no API key and makes no external API calls.
The [request fixtures](fixtures/run-requests.sh) retain the stdin, timing, and
result-file assertions; each runs in a fresh temporary directory.

## A Request From a File: stdin EOF Ends the Input

In batch mode stdin is read through EOF, so a redirected file works and EOF
never cancels anything. The result echoes the request's id and the preset.

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh a-request-from-a-file-stdin-eof-ends-the-input
exit 0
{"version":1,"request_id":"r-1","kind":"echo","status":"completed","output":{"probe":42}}
```

## `--kind` and the Request's Kind Must Agree

`--kind` alone selects the preset; when the request names one too, the two
must be the same. A mismatch is refused before anything runs.

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh kind-and-the-request-s-kind-must-agree
exit 0
{"version":1,"kind":"echo","status":"completed","output":"hi"}
error: --kind explore does not match the request's kind echo
exit 1
{"version":1,"status":"failed","reason":"--kind explore does not match the request's kind echo"}
```

## Requests That Cannot Run Are Refused Up Front

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh requests-that-cannot-run-are-refused-up-front
error: unknown kind: nope
exit 1
error: worker input requires an absolute `worker_root`
exit 1
error: review takes a goal or a base, not both
exit 1
error: review requires a non-empty goal or base
exit 1
error: unsupported request version 2
exit 1
error: this engine does not support the request's `schema`
exit 1
error: a general request's input needs a non-empty `task`
exit 1
error: a task on the command line cannot be combined with --input-format json
exit 1
error: --kind needs --input-format json: a preset reads a JSON request
exit 1
error: --cancel-on-stdin-eof needs --input-format json
exit 1
error: the request on stdin is not JSON: Invalid character 'o' at line 1, column 1
exit 1
error: a delegated run (--cancel-on-stdin-eof) does not take --review-gate: it gets only what its parent's launch grants
exit 1
```

## A Refused Request Still Answers Under Its Id, and Leaves Nothing Behind

The request's `request_id` is echoed even when the request is refused, and a
preset's input is checked before the workspace exists: `ws` is never created.
A preset names its session only once it records something, so the modelless
`echo` reports none.

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh a-refused-request-still-answers-under-its-id-and-leaves-nothing-behind
error: explore requires a non-empty query
{"version":1,"request_id":"r-3","status":"failed","reason":"explore requires a non-empty query"}
no ws
{"version":1,"kind":"echo","status":"completed","output":0}
```

## A Claimed Session Is Accepted Once, With Its Token

A launcher reserves a child's session by creating its directory with a claim
file in it, then hands the child the claim's token with `--claim`. The file
records only the token's SHA-256 (here, of `t-1`). The child
accepts the claim before it records anything; without the token, or with
the wrong one, the session is an existing one and is refused. A claim is
accepted once; until the child records something (the modelless `echo` never
does) an accepted marker stays, so the id is not listed as a session. `--claim` needs `--session`, and only a `--kind` run takes it.

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh a-claimed-session-is-accepted-once-with-its-token
error: a --kind run starts a new session, and p-sr-1 already exists
exit 1
error: session p-sr-1 was claimed for another run
exit 1
exit 0
claim.accepted
error: session p-sr-1 holds no claim; it was accepted already
exit 1
error: --claim names a claimed session, so it needs --session
exit 1
error: --claim is for a --kind run: the general agent starts its own session
```

## A Parent-Managed Run: One Line In, stdin Held Open

With `--cancel-on-stdin-eof` the request is one line and the parent keeps the
pipe open (the `sleep` here). A delegated run refuses every escalation: an
inherited `OPENSEEK_APPROVAL` does not reach it, and an explicit
`--approval always` is refused. Closing stdin before a request arrives is a
failed run.

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh a-parent-managed-run-one-line-in-stdin-held-open
exit 0
{"version":1,"kind":"echo","status":"completed","output":[1,2]}
{"version":1,"kind":"echo","status":"completed","output":"inherited"}
error: a delegated run (--cancel-on-stdin-eof) refuses every escalation: --approval must be never
error: stdin closed before a request arrived
exit 1
{"version":1,"status":"failed","reason":"stdin closed before a request arrived"}
```

## A Delegated Run Takes Only What Its Launch Grants

A parent may be a sandboxed snippet whose sandbox admits the engine by an argv
prefix, so whatever follows that prefix is the snippet's. A delegated run
therefore accepts only options that grant nothing. The launcher pins `--dir`,
`--session-root`, `--result-root`, `--model` and `--api-url` in the prefix,
and a second copy cannot override it: any option given twice is refused. It starts
no MCP servers, whatever its environment says, and its result must be a new
file inside `--result-root`: a path outside it, or an existing file, is
refused and left untouched.

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh a-delegated-run-takes-only-what-its-launch-grants
error: argument '--dir' cannot be used multiple times
error: a delegated run (--cancel-on-stdin-eof) does not take --mcp-config: it gets only what its parent's launch grants
MCP config ignored: a delegated run starts no MCP servers its parent did not grant
error: --result-file must be inside --result-root DIR/out
nothing written elsewhere
error: --result-file must name a new file: DIR/out/existing.json already exists
keep
{"version":1,"kind":"echo","status":"completed","output":0}
```

A malformed `OPENSEEK_MAX_STEPS` does not refuse a request that carries its own
step ceiling: the environment is parsed only when it would apply.

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh a-delegated-run-takes-only-what-its-launch-grants-2
error: an API key is required for deepseek-flash: pass --api-key
```

## Closing stdin Cancels a Managed Run, Which Still Reports

The model endpoint is a closed local port, so the run is still retrying when
the parent closes stdin after a second. The run is cancelled and its result
says `interrupted`, with the usage it recorded (none).

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh closing-stdin-cancels-a-managed-run-which-still-reports
exit 1
{"version":1,"request_id":"r-9","status":"interrupted","reason":"cancelled","usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":0},"steps":0}
```

## One Delegated General Run per Workspace

A delegated general run holds the workspace's lease until it ends; a second
one in the same workspace is refused at once. A parallel writer should be a
`worker`, which gets its own worktree. (The background request is written by
`sh -c` rather than a `( … )` subshell: a background bash subshell re-seeks
this script's stdin when it exits, and the script would run again.)

```mooncram
$ moonx ../cli-fixture.mbtx --package ../.. fixtures/run-requests.sh one-delegated-general-run-per-workspace
error: another delegated general run is already working in WORKSPACE; run a worker for parallel writes
{"version":1,"status":"failed","reason":"another delegated general run is already working in WORKSPACE; run a worker for parallel writes"}
```
