# OpenSeek Agent

`bobzhang/openseek/agent` is the native-only OpenSeek loop. It connects four
lower-level packages:

- `agent_session`: immutable conversation state and model-message projection;
- `agent_runtime`: per-loop workspace state and steering;
- `agent_tool`: local tool registry and tool dispatch results;
- `deepseek` and `deepseek/client`: model types and chat-completion requests.

The package owns the orchestration policy: when to append session events, when
to call the model, how to execute tool calls, and how mid-turn steering changes
the active turn.

Prompt text is deliberately outside this package. Applications choose or build
the system prompt, then pass it to `run` or store it in the `Session` supplied
to the lower-level turn APIs.

## Public API

The exported surface is small:

```mbt nocheck
@agent.run(
  api_key~,
  model=Deepseek(V4Pro),
  task="fix the tests",
  system_prompt_text="You are an OpenSeek agent.",
)

let persisted = @agent.run_turn_with_append(
  api_key~,
  model=Deepseek(V4Pro),
  session~,
  task="continue",
  append_item=(session, item) => store.append(session, item),
)

@async.with_task_group() <| group => {
  let runtime = @agent_runtime.AgentRuntime(workspace_root=".")
  let scope = @agent_runtime.AgentTaskScope(group)
  let tools = @agent.build_tools(runtime, scope)
  let next = @agent.run_turn_in_scope(
    runtime~,
    scope~,
    api_key~,
    model=Deepseek(V4Pro),
    session~,
    task="continue",
    append_item=(session, item) => session.append(item),
    tools~,
  )
}

runtime.queue_steer(Prompt("also update README"))
```

`run` is the highest-level one-shot entry point. It creates a fresh in-memory
session with id `"one-shot"`, runs one turn, logs progress, discards the final
session value, and returns `Unit`. The caller must provide `system_prompt_text`.

`run_turn_with_append` is the durable one-turn API. The `append_item` callback is
called for every committed item and returns the new authoritative session
snapshot. Filesystem-backed callers use this to persist progress even if a later
model call or tool execution fails. Callers that only need an in-memory result
can return `session.append(item)` from the callback.

`run_turn_in_scope` is the long-lived engine API. The caller owns the
`AgentRuntime`, `AgentTaskScope`, and usually a `Tools` registry built once with
`build_tools`. This is the API used by serve mode so stateful tools and queued
steering can span turns.

`runtime.queue_steer(Prompt(text))` queues raw user steering text on an
`AgentRuntime`. It does not trim or filter. The loop drops blank strings when it
drains steering at a step boundary.

## Prompt Ownership

`agent` does not import `prompt` and does not choose default prompt text. This
keeps the loop reusable with built-in prompts, test prompts, user-authored
prompts, or prompts supplied by a different application.

```mbt check
///|
test "turn APIs use the session prompt exactly as supplied" {
  let session = @agent_session.Session(
    SessionId("prompt-owner"),
    system_prompt="custom system",
  )
  debug_inspect(
    session.chat_messages()[0].content,
    content=(
      #|"custom system"
    ),
  )
}
```

The CLI remains free to call `@prompt.system_prompt_for_model(model)` before it
calls `@agent.run`, but that decision lives outside the `agent` package.

## Standard Tools

`build_tools(runtime, scope)` returns the standard local tool registry:

- `mbtx`: compile and run a self-contained MoonBit program — both the
  scripting surface (transform files, parse JSON, compute, probe the language)
  and the command runner, since processes are spawned from the program through
  the shell-free `moonbitlang/async/shell` API. Calls return inline for up to
  five seconds, then automatically hand the same execution to the background
  runtime;
- `job_output` / `job_stop`: read or stop a background job;
- `read`: read a text file;
- `edit`: replace exact text in a file;
- `multi_edit`: apply several explicit line-anchored replacements to one file;
- `write`: overwrite a file;
- `remove`: delete a file the agent itself created earlier in the session;
- `plan`: record or replace the step-by-step plan for a multi-step task;
- `goal`: report standing-goal status (`met`, `continuing`, or `blocked`;
  `met` clears the goal — setting one is the serve `goal` command's job);
- `finish`: end the task with a final answer.

There is no shell tool: every command the agent runs is an argument vector
handed to `@shell.Cmd`, so no command text is ever parsed by a shell.

File-oriented tools capture `runtime.workspace_root()` when the registry is
built. The registry also receives the runtime and task scope for stateful
tools: the background-job path uses both — completion notices are pushed
through `runtime.queue_steer`, and the job runtime plus its spill-dir cleanup
are owned by the task scope's group.

```mbt check
///|
async test "standard tools are registered in dispatch order" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime(workspace_root="/repo")
    let scope = @agent_runtime.AgentTaskScope(group)
    let tools = @agent.build_tools(runtime, scope)
    debug_inspect(
      [
        for tool in tools.function_tools() => tool.name
      ],
      content=(
        #|[
        #|  "read",
        #|  "edit",
        #|  "multi_edit",
        #|  "write",
        #|  "remove",
        #|  "plan",
        #|  "goal",
        #|  "mbtx",
        #|  "job_output",
        #|  "job_stop",
        #|  "finish",
        #|]
      ),
    )
  }
}
```

Build the registry once for a long-lived engine. If a custom registry contains
stateful tools, their records live in the registry value, not in
`AgentRuntime`; rebuilding it every turn can orphan that tool state.

## Steering

Steering is user input that arrives while a turn is active.
`runtime.queue_steer(Prompt(text))` stores the raw string as prompt steering in
the runtime's lossless steering queue:

```mbt check
///|
test "queue_steer queues raw text" {
  let runtime = @agent_runtime.AgentRuntime()
  runtime.queue_steer(Prompt("also run tests"))
  runtime.queue_steer(Prompt("   "))
  let drained = runtime.drain_steers()
  assert_eq(drained.length(), 2)
  assert_true(drained[0] is Prompt("also run tests"))
  assert_true(drained[1] is Prompt("   "))
}
```

The agent loop applies non-blank steering at step boundaries. A steer that races
with a model's final answer or a `finish` tool call keeps the turn alive: the
would-be final output is recorded as ordinary conversation state, the steer is
appended as a user message, and the loop continues. Error terminals such as
abort, cancellation, failure, or exhausted steps still end the turn.

## One-Shot Turns

`run_turn_with_append` appends the task as a user event, runs up to `max_steps`
model/tool iterations, then appends a terminal event. With `max_steps=0`, no
model request is made; this is useful for documenting the session contract
without a network dependency:

```mbt check
///|
async test "zero step run_turn_with_append appends user then failure terminal" {
  let session = @agent_session.Session(
    SessionId("readme-turn"),
    system_prompt="system",
  )
  let result = @agent.run_turn_with_append(
    api_key="unused-api-key",
    model=Deepseek(V4Flash),
    session~,
    task="hello",
    append_item=(session, item) => session.append(item),
    max_steps=0,
  )
  debug_inspect(
    [
      for event in result.events() => {
        match event.item() {
          User(message) => "user:\{message.content()}"
          Terminal(Failed(message)) => "failed:\{message}"
          _ => "other"
        }
      }
    ],
    content=(
      #|["user:hello", "failed:max steps exhausted"]
    ),
  )
}
```

Use `run_turn_with_append` when the caller needs every item at the moment it is
committed. The callback is the sequencing authority: return the session snapshot
that should be used for the rest of the turn.

```mbt check
///|
async test "run_turn_with_append calls the persistence hook for each item" {
  let session = @agent_session.Session(
    SessionId("readme-persist"),
    system_prompt="system",
  )
  let appended : Array[String] = []
  let result = @agent.run_turn_with_append(
    api_key="unused-api-key",
    model=Deepseek(V4Flash),
    session~,
    task="persist me",
    append_item=(session, item) => {
      appended.push(
        match item {
          User(message) => "user:\{message.content()}"
          Terminal(Failed(message)) => "failed:\{message}"
          _ => "other"
        },
      )
      session.append(item)
    },
    max_steps=0,
  )
  debug_inspect(
    appended,
    content=(
      #|["user:persist me", "failed:max steps exhausted"]
    ),
  )
  debug_inspect(result.last_sequence(), content="2")
}
```

## Long-Lived Engines

`run_turn_in_scope` is the API for serve mode and other controllers that keep an
engine alive across prompts. The caller supplies:

- one shared `AgentRuntime` for workspace-root context and steering;
- one `AgentTaskScope` from an enclosing `@async.with_task_group`;
- an `append_item` callback for in-memory or durable session updates;
- usually one shared `Tools` registry from `build_tools(runtime, scope)`.

At each step boundary the loop first applies non-blank steering, then may inject
a plan reminder before calling DeepSeek with the current session projection and
tool schemas. Tool calls are executed in order. The turn ends on a direct model
answer, `finish`, `abort`, cancellation, unexpected failure, or exhausted
`max_steps`.

## Operational Notes

This package is intended for trusted local automation. `mbtx` can run
arbitrary commands (its snippets spawn processes), while `edit` and `write` can
modify files visible to the process. Use the CLI package for application-level policy,
session storage, logging configuration, and serve-mode wire handling.

Run the package tests with:

```bash
moon test agent
```

## Real-World Run Notes

The DeepSeek V4-Pro TOML-parser trials showed useful cache behavior after the
stable prompt prefix, but also surfaced MoonBit-specific failure modes to keep
improving:

- The model needs concrete MoonBit examples, especially for package manifests,
  type aliases, mutable record fields, map construction, and error handling.
- Parser examples should include exact receiver annotations, string APIs, and
  unit syntax: `fn Parser::peek(self : Parser)`, `get_char`, `to_owned`, and
  `()` instead of `{}` for no-op branches.
- Long parser loops should avoid leaving `while` as the final expression of a
  function returning `Result`; put the final `Ok(...)`/`Err(...)` after the loop
  or return from explicit branches.
- Long runs should be observable while they are running. The agent writes loop
  logs through async logging so piped runs such as `2>&1 | tee run.log` receive
  step output promptly.
- Current MoonBit projects use `moon.mod`; `moon.mod.json` is legacy. Manifest
  or package-import edits should be followed quickly by a `moon check` or
  another explicit validation command.
- Use `mbtx` for exact end-to-end MoonBit command validation beyond
  compiler feedback, especially `moon test`, `moon run`, and README command
  checks. Source-writing commands (`moon fmt`, `moon info`, `git checkout`) run
  normally inside snippets — the sandbox bounds which commands exist, not
  whether they write source. Only a `read_only` subrun takes a profile that
  denies source writes.
- For snapshot updates, run plain `moon test` first and only run
  `moon test --update` after deciding the failure is a stale snapshot or
  intentional output change, not a behavior bug.
