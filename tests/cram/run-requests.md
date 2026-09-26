# Verified `openseek run` Requests and Results

These examples are executed by `moon cram test tests/cram`. They drive
`openseek run --input-format json` through the real binary: one JSON request
on stdin, the result in `--result-file` (the contract is `docs/run-result.md`).
The `echo` preset is modelless, and the model-backed cases point at a closed
local port, so the suite needs no API key and makes no network calls.

## A Request From a File: stdin EOF Ends the Input

In batch mode stdin is read through EOF, so a redirected file works and EOF
never cancels anything. The result echoes the request's id and the preset.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d)
> printf '{"version":1,"request_id":"r-1","kind":"echo","input":{"probe":42}}' > "$d/request.json"
> openseek.exe run --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" < "$d/request.json" > /dev/null 2>&1
> echo "exit $?"
> cat "$d/result.json"
> rm -rf "$d"
> EOF
exit 0
{"version":1,"request_id":"r-1","kind":"echo","status":"completed","output":{"probe":42}}
```

## `--kind` and the Request's Kind Must Agree

`--kind` alone selects the preset; when the request names one too, the two
must be the same. A mismatch is refused before anything runs.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d)
> printf '{"version":1,"input":"hi"}' | openseek.exe run --kind echo --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
> echo "exit $?"
> cat "$d/result.json"
> printf '{"version":1,"kind":"echo","input":"hi"}' | openseek.exe run --kind explore --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" 2>&1 > /dev/null
> echo "exit $?"
> cat "$d/result.json"
> rm -rf "$d"
> EOF
exit 0
{"version":1,"kind":"echo","status":"completed","output":"hi"}
error: --kind explore does not match the request's kind echo
exit 1
{"version":1,"status":"failed","reason":"--kind explore does not match the request's kind echo"}
```

## Requests That Cannot Run Are Refused Up Front

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d)
> try() { openseek.exe run --no-session --dir "$d/ws" "$@" 2>&1 > /dev/null; echo "exit $?"; }
> printf '{"version":1,"kind":"nope","input":{}}' | try --input-format json
> printf '{"version":1,"kind":"worker","input":{"task":"fix things"}}' | try --input-format json
> printf '{"version":2,"input":{}}' | try --input-format json
> printf '{"version":1,"input":{"task":"t"},"schema":{"type":"object"}}' | try --input-format json
> printf '{"version":1,"input":{"prompt":"t"}}' | try --input-format json
> printf '{"version":1,"input":{"task":"t"}}' | try --input-format json words
> try --kind echo words
> try --cancel-on-stdin-eof words
> printf 'not json' | try --input-format json
> printf '{"version":1,"input":{"task":"t"}}\n' | try --input-format json --cancel-on-stdin-eof --review-gate
> rm -rf "$d"
> EOF
error: unknown kind: nope
exit 1
error: worker input requires an absolute `worker_root`
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
error: --review-gate is not available with --cancel-on-stdin-eof: a delegated run does not delegate further
exit 1
```

## A Refused Request Still Answers Under Its Id, and Leaves Nothing Behind

The request's `request_id` is echoed even when the request is refused, and a
preset's input is checked before the workspace exists: `ws` is never created.
A preset names its session only once it records something, so the modelless
`echo` reports none.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d)
> printf '{"version":1,"request_id":"r-3","kind":"explore","input":{}}' | openseek.exe run --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" 2>&1 > /dev/null
> cat "$d/result.json"
> test -e "$d/ws" && echo "ws exists" || echo "no ws"
> printf '{"version":1,"kind":"echo","input":0}' | openseek.exe run --input-format json --session s-echo --session-root "$d/sessions" --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
> cat "$d/result.json"
> printf '{"version":1,"kind":"echo","input":0}\n' | env WORKFLOW_HOST='{"v":1}' openseek.exe run --input-format json --cancel-on-stdin-eof --session '' --dir "$d/ws" 2>&1 > /dev/null
> rm -rf "$d"
> EOF
error: explore requires a non-empty query
{"version":1,"request_id":"r-3","status":"failed","reason":"explore requires a non-empty query"}
no ws
{"version":1,"kind":"echo","status":"completed","output":0}
error: a run launched from a hosted workflow needs its reserved --session; delegate through @hosted.run so the child gets a transcript
```

## A Parent-Managed Run: One Line In, stdin Held Open

With `--cancel-on-stdin-eof` the request is one line and the parent keeps the
pipe open (the `sleep` here). A delegated run refuses every escalation: an
inherited `OPENSEEK_APPROVAL` does not reach it, and an explicit
`--approval always` is refused. Closing stdin before a request arrives is a
failed run.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d)
> (printf '{"version":1,"kind":"echo","input":[1,2]}\n'; sleep 1) | openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
> echo "exit $?"
> cat "$d/result.json"
> (printf '{"version":1,"kind":"echo","input":"inherited"}\n'; sleep 1) | env OPENSEEK_APPROVAL=ask openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
> cat "$d/result.json"
> printf '{"version":1,"kind":"echo","input":0}\n' | openseek.exe run --input-format json --cancel-on-stdin-eof --approval always --no-session --dir "$d/ws" 2>&1 > /dev/null
> openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --result-file "$d/result.json" < /dev/null 2>&1 > /dev/null
> echo "exit $?"
> cat "$d/result.json"
> rm -rf "$d"
> EOF
exit 0
{"version":1,"kind":"echo","status":"completed","output":[1,2]}
{"version":1,"kind":"echo","status":"completed","output":"inherited"}
error: a delegated run (--cancel-on-stdin-eof) refuses every escalation: --approval must be never
error: stdin closed before a request arrived
exit 1
{"version":1,"status":"failed","reason":"stdin closed before a request arrived"}
```

## Closing stdin Cancels a Managed Run, Which Still Reports

The model endpoint is a closed local port, so the run is still retrying when
the parent closes stdin after a second. The run is cancelled and its result
says `interrupted`, with the usage it recorded (none).

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d)
> (printf '{"version":1,"request_id":"r-9","input":{"task":"say hi"}}\n'; sleep 1) | env DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=20 OPENSEEK_RETRY_BACKOFF_MS=500 openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --api-url http://127.0.0.1:9/chat/completions --result-file "$d/result.json" > /dev/null 2>&1
> echo "exit $?"
> cat "$d/result.json"
> rm -rf "$d"
> EOF
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
$ sh <<'EOF'
> d=$(mktemp -d)
> mkdir "$d/ws"
> export DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=20 OPENSEEK_RETRY_BACKOFF_MS=500
> sh -c 'printf "{\"version\":1,\"input\":{\"task\":\"first\"}}\n"; sleep 3' | openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --api-url http://127.0.0.1:9/chat/completions --result-file "$d/first.json" > /dev/null 2>&1 &
> sleep 1
> (printf '{"version":1,"input":{"task":"second"}}\n'; sleep 1) | openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --api-url http://127.0.0.1:9/chat/completions --result-file "$d/second.json" 2>&1 > /dev/null | sed -E 's#in [^;]*/ws;#in WORKSPACE;#'
> wait
> sed -E 's#in [^;]*/ws;#in WORKSPACE;#' "$d/second.json"
> rm -rf "$d"
> EOF
error: another delegated general run is already working in WORKSPACE; run a worker for parallel writes
{"version":1,"status":"failed","reason":"another delegated general run is already working in WORKSPACE; run a worker for parallel writes"}
```
