///|
/// The severity an event is reported at.
///
/// A property of the event, not of the call site: `compaction_failed` was once
/// logged at `warn` from one place and `error` from two, which no reader could
/// see and nothing could catch. It lives here rather than beside `Event`
/// because `@xlog` is native-only and the decoder has to stay portable.
fn level(event : @protocol.Event) -> @xlog.Level {
  match event {
    AgentSetupFailed(_)
    | TurnFailed(_)
    | ToolCallDecodeError(..)
    | CompactionFailed(_)
    | SessionError(_)
    | CommandError(_) => Error
    AgentAborted(_)
    | MaxStepsExhausted
    | SteerDropped(_)
    | SteerUnconfirmed(_)
    | GoalBudgetExhausted(_)
    | AutoCompactionFailed(_)
    | McpConfigIgnored(_)
    | McpConfigUnreadable(..)
    | McpConfigInvalid(..)
    | McpToolDuplicate(..)
    | McpToolRenamed(..)
    | McpToolsCapped(..)
    | McpServerSkippedOverCap(_)
    | McpConnectFailed(..)
    | McpListToolsFailed(..)
    | McpListToolsTimeout(_)
    | McpNoTools(_) => Warn
    _ => Info
  }
}

///|
/// Write `event` to the process log, which is the engine's stdout JSONL stream.
///
/// `loc` is autofilled from the *caller*, then forwarded to `@xlog`, so each
/// line's `source` still points at the code that reported the event rather than
/// at this function.
///
/// The shape comes from `Event::to_json` — the one encoder — so the engine and
/// the desktop host, which forwards a synthesized event of its own, cannot
/// spell the same event two ways. They did once.
///
/// `@xlog.event` returns `None` when the level is disabled, and that is checked
/// before serializing, so a filtered event costs nothing beyond the enum it was
/// handed.
#callsite(autofill(loc))
pub fn emit(event : @protocol.Event, loc~ : SourceLoc) -> Unit {
  guard @xlog.event(level(event), loc~) is Some(entry) else { return }
  guard event.to_json() is Object(fields) else { return }
  entry.write_object_begin()
  for key, value in fields {
    entry.write_object_field(key, value)
  }
  entry.write_object_end()
}
