# Verified `openseek subrun` Child-Mode Contract

These examples are executed by `moon cram test tests/cram`. They exercise the
INTERNAL child mode end to end through the real binary: one JSON input line on
stdin (the `sleep` holds the pipe open the way a parent runner does — stdin EOF
is the cancel signal), standard JSONL events on stdout, and a final
`{"subrun_report": ...}` line. The `echo` kind is modelless, so the suite needs
no API key and makes no network calls. The contract itself is normative in
the `moonbitlang/workflow` library (`docs/child-contract.md`); §7 there
records this engine's side of it. Event lines carry no log envelope — they are
written straight to stdout by the protocol writer (the event's own fields and
nothing else), never through the process logger — so nothing varies between
runs and no normalization is needed.

## Echo Kind: Events Then the Typed Report Line

```mooncram
$ (printf '{"probe": 42}\n'; sleep 1) | openseek.exe subrun echo
{"event":"agent_step","step":1}
{"event":"usage","usage":{"prompt_tokens":7,"completion_tokens":3,"total_tokens":10,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":7}}
{"subrun_report":{"probe":42}}
```

## Failure Events Survive to the Wire

An unknown kind must deliver its `command_error` event — the parent's only
classification signal — before exiting; an early `exit()` would discard the
asynchronously drained queue.

```mooncram
$ (printf '{}\n'; sleep 1) | openseek.exe subrun nope
{"event":"command_error","error":"unknown subrun kind: nope"}
```

## Worker Kind: Malformed Input Reports Its Exact Defect, Keyless

The worker kind validates its geometry input BEFORE requiring an API key, so
a miswired controller gets the precise defect rather than a key complaint.

```mooncram
$ (printf '{"task": "fix things"}\n'; sleep 1) | openseek.exe subrun worker
{"event":"command_error","error":"subrun worker: worker input requires an absolute `worker_root`"}
```
