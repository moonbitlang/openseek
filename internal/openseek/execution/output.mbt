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
/// Like `with_jsonl_stdout`, but for a person: the answer goes to stdout and
/// the run's progress to stderr, each event rendered by one `TextRenderer`.
/// One drain task writes both streams, so on a terminal that shows both,
/// their lines keep the events' order.
pub async fn with_text_output(body : async () -> Unit) -> Unit {
  let renderer = TextRenderer()
  with_stdout_drain(
    () => {
      @emit.drain(event => {
        let text = renderer.render(event)
        if text.progress != "" {
          @stdio.stderr.write(text.progress)
        }
        if text.answer != "" {
          @stdio.stdout.write(text.answer)
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
/// What one event adds to each output stream.
priv struct Rendered {
  answer : String
  progress : String
}

///|
/// Turns the event stream into minimal text, in the spirit of the desktop's
/// minimal transcript: stdout gets only the answer, and stderr gets a quiet
/// line per tool call, failures, and how the run ended. Reasoning, step
/// numbers, token counts and bookkeeping events stay in the session log.
///
/// The answer is printed whole when the turn finishes, not streamed: until
/// then a model message may still turn out to be intermediate, and stdout
/// must hold only the answer so `run … > answer.md` captures just that.
priv struct TextRenderer {
  /// The session this run records to, for the hint that names it.
  mut session : String?
  /// The latest model message, held back in case it is the answer. If the turn
  /// goes on instead, it was intermediate and becomes a progress line.
  mut pending : String?
  /// Fleet attempts share both streams and their events interleave.
  mut fleet : Bool
  /// Answers printed so far, so a fleet's answers can be told apart.
  mut answers : Int
}

///|
fn TextRenderer::TextRenderer() -> TextRenderer {
  { session: None, pending: None, fleet: false, answers: 0, }
}

///|
/// The text `event` adds to stdout and stderr; empty when it shows nothing.
fn TextRenderer::render(
  self : TextRenderer,
  event : @protocol.Event,
) -> Rendered {
  let answer = StringBuilder()
  let progress = StringBuilder()
  match event {
    SessionStarted(session~, session_root~, ..) => {
      self.session = Some(session)
      line(progress, "session \{session} (\{session_root})")
    }
    FleetStarted(runs~, ..) => {
      self.fleet = true
      line(progress, "fleet: \{runs} runs")
    }
    WorkspaceCreated(dir~) => line(progress, "created \{dir}")
    // A message followed by another step was intermediate.
    AgentStep(_) => self.flush(progress)
    // A fleet's attempts interleave, so their messages are never held.
    AssistantMessage(content~) => {
      self.flush(progress)
      if !content.is_blank() && !self.fleet {
        self.pending = Some(content)
      }
    }
    // Waiting on a background job is coordination, not work of its own.
    ToolResult(tool_name="job_wait", is_error=false, ..) => self.flush(progress)
    ToolResult(tool_name~, is_error=true, content~, ..) => {
      self.flush(progress)
      line(progress, "tool error: \{tool_name}: \{first_line(content)}")
    }
    ToolResult(tool_name~, brief~, ..) => {
      self.flush(progress)
      line(progress, "· \{brief.unwrap_or(tool_name)}")
    }
    ToolCallDecodeError(tool_name~, error~, ..) => {
      self.flush(progress)
      line(progress, "tool error: \{tool_name}: \{error}")
    }
    StreamRetry(attempt~, max_attempts~, reason~) => {
      self.flush(progress)
      line(progress, "retrying (\{attempt}/\{max_attempts}): \{reason}")
    }
    AgentFinished(answer=result) => {
      // The answer is `result` alone. A `finish`-tool answer arrives with no
      // message of its own, so a different latest message was intermediate;
      // a blank answer prints nothing rather than borrowing that message.
      if self.pending is Some(message) && message != result {
        self.flush(progress)
      }
      self.pending = None
      let text = result
      if !text.is_blank() {
        // A fleet prints one answer per attempt; separate them.
        if self.answers > 0 {
          answer.write_string("---\n")
        }
        answer.write_string(terminal_safe_text(text.trim_end()))
        answer.write_char('\n')
        self.answers += 1
      }
    }
    MaxStepsExhausted => {
      self.flush(progress)
      line(progress, "stopped: max steps exhausted\{self.continue_hint()}")
    }
    ContextYield(..) => {
      self.flush(progress)
      line(
        progress,
        "stopped at the model's context window\{self.continue_hint()}",
      )
    }
    AgentAborted(reason~) => {
      self.flush(progress)
      line(progress, "aborted: \{reason}")
    }
    TurnFailed(error~) => {
      self.flush(progress)
      line(progress, "error: \{error}")
    }
    AgentSetupFailed(error~) => line(progress, "setup failed: \{error}")
    McpConnectFailed(server~, ..) =>
      line(progress, "MCP server `\{server}` failed to connect")
    McpListToolsFailed(server~, ..) | McpListToolsTimeout(server~) =>
      line(progress, "MCP server `\{server}` did not list its tools")
    McpConfigUnreadable(path~, error~) | McpConfigInvalid(path~, error~) =>
      line(progress, "MCP config error (\{path}): \{error}")
    McpConfigIgnored(reason~) => line(progress, "MCP config ignored: \{reason}")
    // Reasoning, deltas, usage, goals, compaction, subruns, jobs and the rest
    // are in the session log.
    _ => ()
  }
  { answer: answer.to_string(), progress: progress.to_string(), }
}

///|
/// Write the pending message as a progress line: the turn went on, so it was
/// not the answer. A fleet drops it, since attempts' messages interleave.
fn TextRenderer::flush(self : TextRenderer, progress : StringBuilder) -> Unit {
  if self.pending is Some(message) && !self.fleet {
    line(progress, message)
  }
  self.pending = None
}

///|
/// How to pick a stopped run back up, when it recorded a session.
fn TextRenderer::continue_hint(self : TextRenderer) -> String {
  match self.session {
    Some(session) => " · continue with --session \{session}"
    None => ""
  }
}

///|
/// A one-line status: untrusted text collapsed to a terminal-safe line.
fn line(out : StringBuilder, text : String) -> Unit {
  out.write_string(@cli.terminal_safe_line(text, limit=200))
  out.write_char('\n')
}

///|
/// The first non-blank line of a tool's output: its headline (`mbtx` leads
/// with what failed and where), where the whole output collapsed onto one
/// line reads as noise.
fn first_line(text : String) -> String {
  for line in text.split("\n") {
    let line = line.trim()
    if line != "" {
      return line.to_owned()
    }
  }
  ""
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
