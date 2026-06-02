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
an `agent_finished`. Matching on the `"event"` field with string-literal
patterns confirms each one shows up without pinning their order or count.

```mooncram
$ openseek.exe --model deepseek-v4-flash --max-steps 3 "Call the finish tool immediately with the answer DONE. Use no other tool." 2>/dev/null \
>   | moon run --target native -e 'import {
>   "bobzhang/jsonl@0.2.0",
>   "moonbitlang/async",
> }
> 
> async fn main {
>   let mut saw_step = false
>   let mut saw_usage = false
>   let mut saw_finished = false
>   for value in @jsonl.read_stdin() {
>     if value is { "event": String("agent_step"), .. } { saw_step = true }
>     if value is { "event": String("usage"), .. } { saw_usage = true }
>     if value is { "event": String("agent_finished"), .. } { saw_finished = true }
>   }
>   println("saw_agent_step=\{saw_step}")
>   println("saw_usage=\{saw_usage}")
>   println("saw_agent_finished=\{saw_finished}")
> }' 2>/dev/null \
>   | grep '='
saw_agent_step=true
saw_usage=true
saw_agent_finished=true
```
