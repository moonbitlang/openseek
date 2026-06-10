# Live DeepSeek CLI Documentation

Unlike [`tests/cram/cli.md`](../cram/cli.md), the examples here make **real**
DeepSeek API calls — there is no mocking. They live in a separate directory so
the offline suite can run in CI without credentials, while these are opt-in:

```bash
export DEEPSEEK=sk-...            # a real DeepSeek API key
moon cram test tests/live
```

The agent streams one JSON object per line (JSONL) to stdout. Instead of an
external tool such as `jq`, we parse that log with MoonBit itself: the published
[`bobzhang/jsonl`](https://mooncakes.io/docs/bobzhang/jsonl) package reads stdin
and hands back typed `Json` values, so the assertions are plain MoonBit `is`
pattern matches. Its `read_stdin` helper encapsulates `moonbitlang/async/stdio`,
so each script imports only `bobzhang/jsonl` plus `moonbitlang/async` — the
latter is unavoidable because `async fn main` requires it. The `grep '='` only
drops `moon`'s own dependency-resolution chatter, not any log content.

Every example gives the cheap Flash model a trivial, self-contained task and a
tiny step budget.

When the model emits assistant text, the stream may include one or more
`assistant_delta` events before the final `assistant_message`; thinking-mode
runs may also interleave `reasoning_delta` events before the content starts.
Tool-only responses, such as the forced `finish` examples below, may skip these
content events and go straight to tool execution.

## A Real Round Trip That Finishes

This proves two things from the real log: that the request reached DeepSeek and
came back with token accounting (`real_api_round_trip`), and that the model
invoked the `finish` tool with the requested answer (`finished_with_DONE`). The
`is` guards bind a field and test it in one condition — `n > 0.0` for the token
count, and a `=~ re"…"` regex match for the answer text.

```mooncram
$ openseek.exe --model deepseek-v4-flash --max-steps 3 "Call the finish tool immediately with the answer DONE. Use no other tool." 2>/dev/null \
>   | moon run --target native -e 'import {
>   "bobzhang/jsonl@0.2.0",
>   "moonbitlang/async",
> }
> 
> async fn main {
>   let mut tokens_ok = false
>   let mut finished = false
>   for value in @jsonl.read_stdin() {
>     if value is { "prompt_tokens": Number(n, ..), .. } && n > 0.0 { tokens_ok = true }
>     if value is { "answer": String(answer), .. } && answer =~ re"DONE" { finished = true }
>   }
>   println("real_api_round_trip=\{tokens_ok}")
>   println("finished_with_DONE=\{finished}")
> }' 2>/dev/null \
>   | grep '='
real_api_round_trip=true
finished_with_DONE=true
```

## The Expected Lifecycle Events Appear

A minimal run emits an `agent_step`, a `usage` record once DeepSeek answers, and
an `agent_finished`. We collect the `"event"` values into a `Set`, which dedupes
and preserves insertion order — so printing it yields the lifecycle in the order
it occurred, the same `{agent_step, usage, agent_finished}` no matter how many
steps the run takes. The filter is a whitelist of exactly those lifecycle
events: the stream also carries content/reasoning payload events
(`assistant_delta`, `reasoning_message`, …) whose presence and count vary per
run, and asserting the full set would break every time the engine grows a new
event kind.

```mooncram
$ openseek.exe --model deepseek-v4-flash --max-steps 3 "Call the finish tool immediately with the answer DONE. Use no other tool." 2>/dev/null \
>   | moon run --target native -e 'import {
>   "bobzhang/jsonl@0.2.0",
>   "moonbitlang/async",
> }
> 
> async fn main {
>   let lifecycle = ["agent_step", "usage", "agent_finished"]
>   let events = Set::new()
>   for value in @jsonl.read_stdin() {
>     if value is { "event": String(event), .. } && lifecycle.contains(event) {
>       events.add(event)
>     }
>   }
>   println("events=\{events}")
> }' 2>/dev/null \
>   | grep '='
events={agent_step, usage, agent_finished}
```

## Pulling A Value Out Of A Record

The `agent_finished` record carries the model's answer. A single pattern can
match the event tag and bind the answer at once, pulling the value straight out
of the log — here it is exactly what we asked the model to finish with.

```mooncram
$ openseek.exe --model deepseek-v4-flash --max-steps 3 "Call the finish tool immediately with the answer DONE. Use no other tool." 2>/dev/null \
>   | moon run --target native -e 'import {
>   "bobzhang/jsonl@0.2.0",
>   "moonbitlang/async",
> }
> 
> async fn main {
>   for value in @jsonl.read_stdin() {
>     if value is { "event": String("agent_finished"), "answer": String(answer), .. } {
>       println("final_answer=\{answer}")
>     }
>   }
> }' 2>/dev/null \
>   | grep '='
final_answer=DONE
```

## Watching The Agent Use A Tool

The point of the agent is that it *acts*. When a task needs work, the model
calls one of the local tools and a `tool_result` record joins the stream. Here
the task forces the `shell` tool; we match the `tool_result` event together with
its `tool_name`, and use a regex on its `content` to confirm the command really
ran and its output flowed back.

```mooncram
$ openseek.exe --model deepseek-v4-flash --max-steps 6 "Use the shell tool to run exactly: echo openseek-cram. Then call finish with the word done." 2>/dev/null \
>   | moon run --target native -e 'import {
>   "bobzhang/jsonl@0.2.0",
>   "moonbitlang/async",
> }
> 
> async fn main {
>   let mut used_shell = false
>   let mut shell_output_seen = false
>   for value in @jsonl.read_stdin() {
>     if value is { "event": String("tool_result"), "tool_name": String("shell"), "content": String(out), .. } {
>       used_shell = true
>       if out =~ re"openseek-cram" { shell_output_seen = true }
>     }
>   }
>   println("used_shell=\{used_shell}")
>   println("shell_output_seen=\{shell_output_seen}")
> }' 2>/dev/null \
>   | grep '='
used_shell=true
shell_output_seen=true
```
