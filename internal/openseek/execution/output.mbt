///|
/// Run `body` with the protocol event sink open and its stdout drain running:
/// the drain owns all stdout writes, and — spawned without `no_wait` — the
/// group only completes once the sink (closed by the `defer`, on success and
/// error alike) is fully written, so the terminal event is never lost to an
/// early process exit. The sink is opened synchronously before the spawn,
/// because `spawn_bg` does not promise the drain runs before `body` starts
/// emitting. Outside this helper the sink is closed and every event is
/// dropped, which is what a command whose stdout is a report or human text
/// wants — nothing else has to remember to close it.
pub async fn with_jsonl_stdout(body : async () -> Unit) -> Unit {
  with_stdout_drain(@emit.drain_stdout, body)
}

///|
/// Like `with_jsonl_stdout`, but stdout is text for a person: each event is
/// rendered by one `TextRenderer` as it arrives, so the answer streams token by
/// token instead of as one JSON object per token.
pub async fn with_text_stdout(body : async () -> Unit) -> Unit {
  let renderer = TextRenderer()
  with_stdout_drain(
    () => {
      @emit.drain(event => {
        let text = renderer.render(event)
        if text != "" {
          @stdio.stdout.write(text)
        }
      })
    },
    body,
  )
}

///|
async fn with_stdout_drain(
  drain : async () -> Unit,
  body : async () -> Unit,
) -> Unit {
  @emit.open()
  @async.with_task_group(group => {
    group.spawn_bg(drain)
    defer @emit.close()
    body()
  })
}

///|
/// Which stream the cursor is in the middle of, so a switch between the
/// model's reasoning and its answer starts on a fresh, labeled line.
priv enum Stream {
  Idle
  Thinking
  Answer
} derive(Eq)

///|
/// Turns the event stream into terminal text. Stateful because the text is
/// incremental: deltas continue the current line, and a status line has to
/// first end whatever was streaming. Token counts are summed across steps and
/// reported once, when the turn ends.
priv struct TextRenderer {
  mut stream : Stream
  /// The last write left the cursor mid-line.
  mut mid_line : Bool
  /// Answer deltas were printed since the last full message, so that message
  /// is already on screen.
  mut answer_streamed : Bool
  mut last_message : String?
  /// Fleet attempts share one stdout, so their deltas would interleave
  /// character by character; a fleet prints whole messages instead.
  mut fleet : Bool
  mut steps : Int
  mut prompt_tokens : Int
  mut cached_tokens : Int
  mut completion_tokens : Int
}

///|
fn TextRenderer::TextRenderer() -> TextRenderer {
  {
    stream: Idle,
    mid_line: false,
    answer_streamed: false,
    last_message: None,
    fleet: false,
    steps: 0,
    prompt_tokens: 0,
    cached_tokens: 0,
    completion_tokens: 0,
  }
}

///|
/// The text `event` adds to stdout; empty when it shows nothing.
fn TextRenderer::render(self : TextRenderer, event : @protocol.Event) -> String {
  let out = StringBuilder()
  match event {
    SessionStarted(session~, session_root~, ..) =>
      self.line(out, "session \{session} (\{session_root})")
    FleetStarted(runs~, ..) => {
      self.fleet = true
      self.line(out, "fleet: \{runs} runs")
    }
    AgentStep(step~) => {
      self.steps = step
      self.line(out, "--- step \{step}")
    }
    ReasoningDelta(content~) => self.stream_text(out, Thinking, content)
    AssistantDelta(content~) =>
      if !self.fleet {
        self.answer_streamed = true
        self.stream_text(out, Answer, content)
      }
    // Reasoning is shown only live; its full-text repeat adds nothing.
    ReasoningMessage(_) => ()
    AssistantMessage(content~) => {
      self.last_message = Some(content)
      if self.answer_streamed {
        self.end_stream(out)
      } else {
        self.block(out, content)
      }
      self.answer_streamed = false
    }
    ToolResult(tool_name~, is_error=true, content~, ..) =>
      self.line(out, "tool error: \{tool_name}: \{content}")
    ToolResult(tool_name~, brief~, ..) =>
      self.line(out, "↳ \{brief.unwrap_or(tool_name)}", indent="  ")
    ToolCallDecodeError(tool_name~, error~, ..) =>
      self.line(out, "tool error: \{tool_name}: \{error}")
    Usage(usage~) => {
      self.prompt_tokens += usage.prompt_tokens
      self.cached_tokens += usage.prompt_cache_hit_tokens
      self.completion_tokens += usage.completion_tokens
    }
    StreamRetry(attempt~, max_attempts~, reason~) =>
      self.line(out, "retrying (\{attempt}/\{max_attempts}): \{reason}")
    AgentFinished(answer~) => {
      // The answer is normally the last message, already printed.
      if answer != "" && self.last_message != Some(answer) {
        self.block(out, answer)
      }
      self.line(out, self.summary("done"))
    }
    MaxStepsExhausted =>
      self.line(out, self.summary("stopped: max steps exhausted"))
    AgentAborted(reason~) => self.line(out, "aborted: \{reason}")
    TurnFailed(error~) => self.line(out, "error: \{error}")
    AgentSetupFailed(error~) => self.line(out, "setup failed: \{error}")
    // Everything else is rare bookkeeping (goals, compaction, subruns, MCP):
    // name it and show its fields rather than hand-format each variant.
    _ =>
      match event.to_json() {
        Object(fields) => {
          let name = match fields.get("event") {
            Some(String(name)) => name
            _ => "event"
          }
          let rest = Map::from_iter(
            fields.iter().filter(field => field.0 != "event"),
          )
          let detail = if rest.is_empty() {
            ""
          } else {
            " \{Json::object(rest).stringify()}"
          }
          self.line(out, "· \{name}\{detail}")
        }
        _ => ()
      }
  }
  out.to_string()
}

///|
/// Append streamed `text` to `stream`, first ending any other stream's line.
fn TextRenderer::stream_text(
  self : TextRenderer,
  out : StringBuilder,
  stream : Stream,
  text : String,
) -> Unit {
  if text == "" {
    return
  }
  if self.stream != stream {
    self.end_stream(out)
    if stream is Thinking {
      out.write_string("thinking: ")
      self.mid_line = true
    }
    self.stream = stream
  }
  out.write_string(terminal_safe_text(text))
  self.mid_line = !text.has_suffix("\n")
}

///|
/// End whatever is streaming, so the next write starts at column 0.
fn TextRenderer::end_stream(self : TextRenderer, out : StringBuilder) -> Unit {
  if self.mid_line {
    out.write_char('\n')
    self.mid_line = false
  }
  self.stream = Idle
}

///|
/// A one-line status: untrusted text collapsed to a terminal-safe line, after a
/// trusted `indent` (which the collapse would otherwise trim).
fn TextRenderer::line(
  self : TextRenderer,
  out : StringBuilder,
  text : String,
  indent? : String = "",
) -> Unit {
  self.end_stream(out)
  out.write_string(indent)
  out.write_string(@cli.terminal_safe_line(text, limit=200))
  out.write_char('\n')
}

///|
/// A whole multi-line message, printed when it was not streamed.
fn TextRenderer::block(
  self : TextRenderer,
  out : StringBuilder,
  text : String,
) -> Unit {
  self.end_stream(out)
  out.write_string(terminal_safe_text(text.trim_end()))
  out.write_char('\n')
}

///|
fn TextRenderer::summary(self : TextRenderer, status : String) -> String {
  "\{status} · \{self.steps} step(s) · \{self.prompt_tokens} prompt tokens (\{self.cached_tokens} cached), \{self.completion_tokens} completion"
}

///|
/// Model text as the terminal should receive it: newlines and tabs kept, every
/// other C0/C1 control and DEL dropped, so an ESC in the model's output
/// renders as nothing rather than as a terminal command.
fn terminal_safe_text(text : StringView) -> String {
  guard text.iter().any(ch => is_terminal_control(ch)) else {
    return text.to_owned()
  }
  String::from_iter(text.iter().filter(ch => !is_terminal_control(ch)))
}

///|
fn is_terminal_control(ch : Char) -> Bool {
  let code = ch.to_int()
  (code < 0x20 && ch != '\n' && ch != '\t') ||
  code == 0x7F ||
  (code >= 0x80 && code <= 0x9F)
}

///|
test "text rendering streams the answer and summarizes the turn" {
  let renderer = TextRenderer()
  let events : Array[@protocol.Event] = [
    SessionStarted(
      session="s1",
      session_root="/w/.openseek",
      workspace_root=None,
    ),
    AgentStep(step=1),
    ReasoningDelta(content="hmm"),
    AssistantDelta(content="Hi"),
    AssistantDelta(content=" there\u{1b}[31m"),
    AssistantMessage(content="Hi there"),
    ToolResult(
      tool_call_id="c1",
      tool_name="read",
      is_error=false,
      content="body",
      brief=Some("read moon.mod"),
    ),
    ToolResult(
      tool_call_id="c2",
      tool_name="edit",
      is_error=true,
      content="no match\nfor old_string",
      brief=None,
    ),
    Usage(usage={
      prompt_tokens: 100,
      completion_tokens: 7,
      total_tokens: 107,
      prompt_cache_hit_tokens: 60,
      prompt_cache_miss_tokens: 40,
    }),
    GoalUpdated(goal=Some("ship")),
    AgentFinished(answer="Hi there"),
  ]
  inspect(
    events.map(event => renderer.render(event)).join(""),
    content=(
      #|session s1 (/w/.openseek)
      #|--- step 1
      #|thinking: hmm
      #|Hi there[31m
      #|  ↳ read moon.mod
      #|tool error: edit: no match for old_string
      #|· goal_updated {"goal":"ship"}
      #|done · 1 step(s) · 100 prompt tokens (60 cached), 7 completion
      #|
    ),
  )
}

///|
test "fleet text prints whole messages instead of interleaved deltas" {
  let renderer = TextRenderer()
  let events : Array[@protocol.Event] = [
    FleetStarted(runs=2, task="t"),
    AssistantDelta(content="A"),
    AssistantMessage(content="All of A"),
    AgentFinished(answer="All of A"),
  ]
  inspect(
    events.map(event => renderer.render(event)).join(""),
    content=(
      #|fleet: 2 runs
      #|All of A
      #|done · 0 step(s) · 0 prompt tokens (0 cached), 0 completion
      #|
    ),
  )
}
