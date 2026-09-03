# OpenSeek Architecture

How the pieces fit together: the module map, the core data model, and the
life of one agent turn. Package-level details live in each package's README
(see the table in the [root README](../README.md)); this page is the map, not
the territory. Diagrams are [Mermaid](https://mermaid.js.org/), rendered
natively by GitHub.

## System overview

One shared engine, three frontends. `cmd/openseek` is the engine (headless
automation: `run`/`serve`/`review`/`sessions`/`mcp`; the desktop app and the
viz server are separate executables that spawn or read from it): its `serve`
mode reads JSONL commands on stdin and streams typed JSONL events
(`bobzhang/openseek_protocol`) on stdout. The terminal UI (`openseek_tui`,
built on `cmd/tui`), the desktop app, and headless `run` all drive that same
engine and event stream. Durable state lives in append-only session files that
the visualizer reads directly.

```mermaid
flowchart LR
  subgraph frontends [Frontends]
    TUI["openseek_tui — terminal UI<br/>(cmd/tui, built on the tui framework)"]
    DESKTOP["openseek_desktop — desktop app<br/>(CEF shell + JS frontend)"]
    VIZ["inspect + viz —<br/>session visualizer (browser)"]
  end

  subgraph engine ["openseek engine (cmd/openseek)"]
    SERVE["serve / run / review / sessions / mcp"]
    AGENT["agent — turn loop"]
    TOOLS["agent_tool — registry:<br/>shell·shell_output·shell_stop<br/>read·edit·multi_edit·write<br/>remove·plan·goal·finish"]
    MCP["mcp — client + tool bridge<br/>(mcp__server__tool)"]
    PROMPT["prompt + agent_skill —<br/>system prompt & skills"]
    SESSION["agent_session (+ store) —<br/>durable event log"]
  end

  subgraph outside [Outside]
    API["DeepSeek / Kimi chat API"]
    MCPSRV["MCP servers<br/>(stdio & Streamable HTTP)"]
    FILES[("openseek_session-&lt;id&gt;.jsonl<br/>under .openseek/")]
  end

  TUI -- "JSONL commands (stdin)" --> SERVE
  DESKTOP -- "JSONL commands" --> SERVE
  SERVE -- "protocol events (stdout)" --> TUI
  SERVE -- "protocol events" --> DESKTOP
  SERVE --> AGENT
  PROMPT --> AGENT
  AGENT -- "chat + tool schemas" --> API
  AGENT -- dispatch --> TOOLS
  MCP -- "tool definitions<br/>(extra_tools)" --> TOOLS
  MCP --> MCPSRV
  AGENT -- append --> SESSION
  SESSION --> FILES
  FILES --> VIZ
```

The engine ↔ frontend wire contract is `bobzhang/openseek_protocol`: commands
in (`prompt`, `steer`, `cancel`, `compact`, `goal`), events out (steps,
deltas, tool results, goal/plan reminders, compaction, terminals). The
protocol module is backend-neutral so any frontend — including the JS ones —
can decode it; only `protocol/emit` (the writer) is native-only.

## Core data model

The durable log and the tool boundary are the two type families everything
else leans on.

```mermaid
classDiagram
  class Session {
    id: SessionId
    system_prompt: String
    events: Vector~SessionEvent~
    append(SessionItem) Session
    chat_messages() Array~ChatMessage~
    compact(content, from, to) Session
    current_goal() StandingGoal?
  }
  class SessionEvent {
    sequence: Int
    unix_ms: Int64
    item: SessionItem
  }
  class SessionItem {
    <<enumeration>>
    User(UserMessage)
    Assistant(AssistantMessage)
    Tool(ToolResult)
    Runtime(RuntimeNotice)
    Summary(SessionSummary)
    Terminal(TurnTerminal)
  }
  class TurnTerminal {
    <<enumeration>>
    Finished(String)
    Aborted(String)
    Interrupted(String)
    Failed(String)
  }
  Session "1" *-- "many" SessionEvent
  SessionEvent *-- SessionItem
  SessionItem ..> TurnTerminal

  class Tools {
    find(name) AgentToolDefinition?
    function_tools() Array~ToolDefinition~
  }
  class AgentToolDefinition {
    name: String
    description: String
    schema: JsonSchema
    execute: ToolExecutor
    control: Bool
  }
  class ToolExecutor {
    <<enumeration>>
    Sync(fn)
    Async(async fn)
  }
  class ToolAction {
    <<enumeration>>
    Respond(ToolOutput)
    Control(Finish | Abort)
  }
  class AgentRuntime {
    workspace_root() String
    queue_steer(SteerInput)
    drain_steers() Array~SteerInput~
  }
  Tools "1" *-- "many" AgentToolDefinition
  AgentToolDefinition *-- ToolExecutor
  ToolExecutor ..> ToolAction : returns
```

Key invariants:

- **The session is the only memory.** `Session::chat_messages()` projects the
  event log into the provider's chat shape each turn; nothing conversational
  lives outside the log. Compaction appends a `Summary` item covering a
  `[from, to]` range — raw events are never rewritten — and the projection
  replaces covered events with their summary while keeping uncovered events
  and every surviving summary.
- **Events are append-only and sequenced.** `SessionEvent.sequence` is
  contiguous; the store (`agent_session/store`) persists a header line plus
  one JSON event per line, so a torn final line is recoverable
  (`agent_session/log` reads leniently).
- **Tools are data.** A tool is a name, a JSON schema, and an executor.
  Normal tools return `Respond(ToolOutput)`; control tools (`finish`) end the
  turn via `Control`. MCP tools enter the same registry namespaced as
  `mcp__<server>__<tool>`, so the loop dispatches them identically.

## One turn, end to end

A `serve` turn as driven by the TUI (headless `run` is the same loop without
the stdin command pump):

```mermaid
sequenceDiagram
  participant UI as TUI / desktop
  participant Serve as openseek serve
  participant Turn as agent turn loop
  participant DS as DeepSeek/Kimi API
  participant Tool as agent_tool / mcp
  participant Store as session store

  UI->>Serve: {"command":"prompt","text":…}
  Serve->>Turn: run_turn_in_scope(session, task)
  Turn->>Store: append User(task)
  loop until a plain final answer, a control tool, or the context ceiling
    Turn-->>UI: AgentStep
    Turn->>DS: chat(messages, tool schemas)
    DS-->>Turn: streamed deltas, then the assistant message
    Turn-->>UI: AssistantDelta stream · ReasoningMessage · AssistantMessage
    alt assistant returned tool calls
      Turn->>Store: append Assistant (message + tool calls)
      Turn->>Tool: execute_tool_call(name, args)
      Tool-->>Turn: ToolAction (Respond / Control)
      Turn->>Store: append Tool result
      Turn-->>UI: ToolResult event (Respond actions)
    else plain final answer
      Note over Turn,Store: no Assistant append — the answer persists only in the Terminal
    end
    Note over Turn: queued steers/notices are folded in between steps
  end
  Turn->>Store: append Terminal(Finished(answer))
  alt normal completion
    Turn-->>UI: AgentFinished(answer)
  else context ceiling
    Turn-->>UI: ContextYield ("[context ceiling]" answer)
  end
```

Two pressure valves shape long turns:

- **Steps**: with `--max-steps` unset, a turn is bounded by the model's
  context window instead of a step count — when the window fills, the loop
  checkpoints (auto-compaction) and yields a `[context ceiling]` answer that
  the next turn continues from.
- **Steering**: `steer` commands and background-job completion notices are
  queued losslessly in `AgentRuntime` and surfaced to the model at the next
  step boundary, so a running turn can absorb new instructions without
  restarting.

## Where things live on disk

```text
.openseek/                       # per-workspace session root (--session-root)
  sessions/<id>/
    openseek_session-<id>.jsonl  # header line + append-only events
    session.lock                 # store coordination file
.openseek/skills/<name>.md       # workspace skills (shadow global ones)
~/.openseek/skills/              # global skill library (--global-skills-dir)
```

The visualizer (`openseek` sessions in a browser: `inspect`) and
`sessions list` both read these files directly. The engine's durable state is
exactly these per-session directories; the desktop app additionally keeps its
own metadata under the session root (`workspaces.json`, `archived/sessions`)
and its settings in webview localStorage.
