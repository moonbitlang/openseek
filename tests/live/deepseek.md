# Live DeepSeek CLI Documentation

Unlike [`tests/cram/cli.md`](../cram/cli.md), the examples here make **real**
DeepSeek API calls — there is no mocking. They live in a separate directory so
the offline suite can run in CI without credentials, while these are opt-in:

```bash
export DEEPSEEK=sk-...            # a real provider API key
moon testcli test tests/live --timeout-ms 300000
```

`openseek run` prints its answer for a person. The machine-readable
stream is `openseek serve`: fed one `prompt` command on stdin, it runs that
turn, exits at stdin EOF, and writes one JSON object per line (JSONL) to
stdout. The MoonBit fixture captures that stream, parses each line into a `Json`
value, and uses pattern matching to inspect usage, lifecycle, and tool events.

The [live fixtures](fixtures/) run in fresh temporary directories.
They remain opt-in and are excluded from `just test-cli` and CI.

Every example gives the cheap Flash model a trivial, self-contained task and a
tiny step budget.

When the model emits assistant text, the stream may include one or more
`assistant_delta` events before the final `assistant_message`. Thinking-mode
runs may also emit `reasoning_delta` progress before the completed
`reasoning_message`; interactive clients render it live, while JSONL consumers
may ignore it. Tool-only responses, such as the forced `finish` examples below,
may skip content events and go straight to tool execution.

## `openseek run` Prints The Answer

`run` prints only the answer on stdout, once the turn finishes. Its progress
(the session, one line per tool call, and how the run ended) goes to stderr.

```mooncram moonbitlang/openseek
$ moonx moonbitlang/openseek run --no-session --model deepseek-flash --max-steps 3 "Call the finish tool immediately with the answer DONE. Use no other tool."
DONE
```

## A Real Round Trip That Finishes

This proves two things from the real log: that the request reached DeepSeek and
came back with token accounting (`real_api_round_trip`), and that the model
invoked the `finish` tool with the requested answer (`finished_with_DONE`). The
`is` guards bind a field and test it in one condition — `n > 0.0` for the token
count, and a `=~ re"…"` regex match for the answer text.

```mooncram
$ moonx fixtures/round-trip.mbtx
exit=0
real_api_round_trip=true
finished_with_DONE=true
```

## The Expected Lifecycle Events Appear

A minimal run emits an `agent_step`, a `usage` record once DeepSeek answers, and
an `agent_finished`. We collect the `"event"` values into a `Set`, which dedupes
and preserves insertion order. Joining those values prints the lifecycle in the
order it occurred, the same `{agent_step, usage, agent_finished}` no matter how many
steps the run takes. The filter is a whitelist of exactly those lifecycle
events: the stream also carries content/reasoning payload events
(`assistant_delta`, `reasoning_message`, …) whose presence and count vary per
run, and asserting the full set would break every time the engine grows a new
event kind.

```mooncram
$ moonx fixtures/lifecycle.mbtx
exit=0
events={agent_step, usage, agent_finished}
```

## Pulling A Value Out Of A Record

The `agent_finished` record carries the model's answer. A single pattern can
match the event tag and bind the answer at once, pulling the value straight out
of the log — here it is exactly what we asked the model to finish with.

```mooncram
$ moonx fixtures/final-answer.mbtx
exit=0
final_answer=DONE
```

## Watching The Agent Use A Tool

The point of the agent is that it *acts*. When a task needs work, the model
calls one of the local tools and a `tool_result` record joins the stream. Here
the task forces the `mbtx` tool; we match the `tool_result` event together with
its `tool_name`, and use a regex on its `content` to confirm the snippet really
ran and its output flowed back.

```mooncram
$ moonx fixtures/tool-result.mbtx
exit=0
used_mbtx=true
mbtx_output_seen=true
```
