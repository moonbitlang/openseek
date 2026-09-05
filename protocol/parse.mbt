///|
/// Read one JSONL line from the engine's stdout stream back into an `Event`.
///
/// The inverse of `emit`: `parse(json) == Some(event)` for every line `emit`
/// writes, which `emit/emit_test.mbt` pins per variant — it needs both halves,
/// so it lives with the writer. Fields are read from the top level: `emit`
/// writes each event's fields flat, so there is no nesting and no envelope at
/// all (events do not go through `@xlog`).
///
/// `None` means "not an event this engine emits" — an unknown `event` name, a
/// missing `event` key, or a payload whose required fields are absent or
/// mistyped. Clients stay tolerant of a newer engine by treating `None` as
/// "ignore this line" rather than as a failure.
///
/// ## When a field may be absent
///
/// A field is defaulted only when one of two things is true of it:
///
/// 1. **It was added after its event already existed**, so engines older than
///    the field still emit the event without it — and the TUI and desktop
///    launch whichever `openseek` is on PATH, making a new reader against an
///    old engine a real pairing. Every event field defaulted here is this case.
/// 2. **The engine has treated it as optional since the event shipped** — a
///    flag whose absence has always meant something definite, rather than a
///    value gone missing. No *event* field is this case; `Command`'s `auto` is,
///    which is why that rule is stated separately in `command.mbt` rather than
///    by pointing here.
///
/// Everything else is required. "No reader uses it" is *not* a reason to
/// default a field: `tool_call_id`, `usage`'s cache counters and
/// `mcp_tools_registered`'s `names` are all unread by every current client, yet
/// every engine that ever emitted those events emitted those fields, so their
/// absence means the line is not what it claims to be. Guessing there would
/// hide a real wire break behind a fabricated value.
///
/// Three fields qualify today, all under (1), each verified against `git log -S`
/// for the field versus its event's introducing commit — the check to run
/// before adding a fourth, and the one that catches a field wrongly made
/// required, as `workspace_root` was:
///
/// - `steer_applied`'s `kind` — added 9b2f6c43 (2026-06-25) to an event from
///   56140618.
/// - `session_started`'s `workspace_root` — added d5d0b208 (2026-06-13, with
///   `--dir`) to an event from d11e04c2 (2026-06-12).
/// - `tool_result`'s `brief` — added 4eacdc95 to an event from 1f761102.
pub fn parse(line : Json) -> Event? {
  guard line is Object(fields) else { return None }
  guard text(fields, "event") is Some(name) else { return None }
  match name {
    "agent_setup_failed" =>
      text(fields, "error").map(error => AgentSetupFailed(error~))
    "agent_step" => int(fields, "step").map(step => AgentStep(step~))
    "agent_aborted" =>
      text(fields, "reason").map(reason => AgentAborted(reason~))
    "agent_finished" =>
      text(fields, "answer").map(answer => AgentFinished(answer~))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "turn_failed" => text(fields, "error").map(error => TurnFailed(error~))
    "assistant_delta" =>
      text(fields, "content").map(content => AssistantDelta(content~))
    "reasoning_delta" =>
      text(fields, "content").map(content => ReasoningDelta(content~))
    "assistant_message" =>
      text(fields, "content").map(content => AssistantMessage(content~))
    "reasoning_message" =>
      text(fields, "content").map(content => ReasoningMessage(content~))
    // Decoded field by field rather than through `Usage`'s derived `FromJson`,
    // which reads a fractional number as an `Int` by truncating it: a counter
    // of `1.5` is not a token count, and every other integer on the wire is
    // rejected for exactly that. `int` is the same check used at the top level.
    "usage" => {
      guard fields.get("usage") is Some(Object(usage)) &&
        int(usage, "prompt_tokens") is Some(prompt_tokens) &&
        int(usage, "completion_tokens") is Some(completion_tokens) &&
        int(usage, "total_tokens") is Some(total_tokens) &&
        int(usage, "prompt_cache_hit_tokens") is Some(prompt_cache_hit_tokens) &&
        int(usage, "prompt_cache_miss_tokens") is Some(prompt_cache_miss_tokens) else {
        return None
      }
      Some(
        Usage(usage={
          prompt_tokens,
          completion_tokens,
          total_tokens,
          prompt_cache_hit_tokens,
          prompt_cache_miss_tokens,
        }),
      )
    }
    "tool_result" => {
      guard text(fields, "tool_call_id") is Some(tool_call_id) &&
        text(fields, "tool_name") is Some(tool_name) &&
        bool(fields, "is_error") is Some(is_error) &&
        text(fields, "content") is Some(content) else {
        return None
      }
      Some(
        ToolResult(
          tool_call_id~,
          tool_name~,
          is_error~,
          content~,
          brief=text(fields, "brief"),
        ),
      )
    }
    "tool_call_decode_error" => {
      guard text(fields, "tool_call_id") is Some(tool_call_id) &&
        text(fields, "tool_name") is Some(tool_name) &&
        text(fields, "error") is Some(error) else {
        return None
      }
      Some(ToolCallDecodeError(tool_call_id~, tool_name~, error~))
    }
    "approval_requested" => {
      guard text(fields, "id") is Some(id) &&
        text(fields, "tool_name") is Some(tool_name) &&
        text(fields, "detail") is Some(detail) else {
        return None
      }
      Some(
        ApprovalRequested(id~, tool_name~, detail~, body=text(fields, "body")),
      )
    }
    // `outcome` is carried as the wire's own string rather than decoded into a
    // closed type: a controller renders it, and an engine newer than the
    // controller must be able to settle a prompt with a word this build has
    // never heard of instead of having the whole event dropped as unreadable.
    "approval_resolved" => {
      guard text(fields, "id") is Some(id) &&
        text(fields, "outcome") is Some(outcome) else {
        return None
      }
      Some(ApprovalResolved(id~, outcome~))
    }
    // `kind` is defaulted, not required: engines older than 2026-06-25
    // (9b2f6c43, which added it) emit `steer_applied` with only `content`, and
    // the TUI launches whichever `openseek` is on PATH — so a new reader against
    // an old engine is a real pairing. "prompt" reproduces what those engines
    // meant, and is what every client defaulted to before this package existed.
    "steer_applied" =>
      text(fields, "content").map(content => {
        SteerApplied(kind=text(fields, "kind").unwrap_or("prompt"), content~)
      })
    "steer_dropped" =>
      text(fields, "content").map(content => SteerDropped(content~))
    "background_notice" =>
      text(fields, "content").map(content => BackgroundNotice(content~))
    // `goal` is null when the goal was cleared: absent and null are the same
    // value here, so the key's presence is not itself required.
    "goal_updated" => Some(GoalUpdated(goal=text(fields, "goal")))
    "goal_blocked" => text(fields, "reason").map(reason => GoalBlocked(reason~))
    "goal_unblocked" => Some(GoalUnblocked)
    "goal_check" => text(fields, "content").map(content => GoalCheck(content~))
    "goal_reminder" =>
      text(fields, "content").map(content => GoalReminder(content~))
    "goal_continue" =>
      int(fields, "remaining").map(remaining => GoalContinue(remaining~))
    "goal_budget_exhausted" =>
      int(fields, "turns").map(turns => GoalBudgetExhausted(turns~))
    "plan_reminder" =>
      text(fields, "content").map(content => PlanReminder(content~))
    "compaction_started" => {
      guard sequences(fields) is Some((from_sequence, to_sequence)) else {
        return None
      }
      Some(CompactionStarted(from_sequence~, to_sequence~))
    }
    "compaction_finished" => {
      guard sequences(fields) is Some((from_sequence, to_sequence)) &&
        text(fields, "summary") is Some(summary) else {
        return None
      }
      Some(CompactionFinished(from_sequence~, to_sequence~, summary~))
    }
    "compaction_failed" =>
      text(fields, "error").map(error => CompactionFailed(error~))
    "subrun_started" => {
      guard text(fields, "id") is Some(id) &&
        text(fields, "kind") is Some(kind) &&
        text(fields, "label") is Some(label) else {
        return None
      }
      Some(SubrunStarted(id~, kind~, label~))
    }
    "subrun_finished" => {
      guard text(fields, "id") is Some(id) &&
        text(fields, "status") is Some(status) &&
        int(fields, "steps") is Some(steps) &&
        int(fields, "prompt_tokens") is Some(prompt_tokens) &&
        int(fields, "completion_tokens") is Some(completion_tokens) else {
        return None
      }
      Some(
        SubrunFinished(id~, status~, steps~, prompt_tokens~, completion_tokens~),
      )
    }
    "workflow_started" => {
      guard text(fields, "id") is Some(id) &&
        text(fields, "journal") is Some(journal) &&
        text(fields, "events") is Some(events) &&
        int(fields, "first_child") is Some(first_child) &&
        int(fields, "child_count") is Some(child_count) else {
        return None
      }
      Some(WorkflowStarted(id~, journal~, events~, first_child~, child_count~))
    }
    "workflow_finished" => {
      guard text(fields, "id") is Some(id) else { return None }
      Some(WorkflowFinished(id~))
    }
    "auto_compaction_started" => {
      guard sequences(fields) is Some((from_sequence, to_sequence)) else {
        return None
      }
      Some(AutoCompactionStarted(from_sequence~, to_sequence~))
    }
    "auto_compaction_finished" => {
      guard sequences(fields) is Some((from_sequence, to_sequence)) &&
        text(fields, "summary") is Some(summary) else {
        return None
      }
      Some(AutoCompactionFinished(from_sequence~, to_sequence~, summary~))
    }
    "auto_compaction_failed" =>
      text(fields, "error").map(error => AutoCompactionFailed(error~))
    "context_yield" => {
      guard int(fields, "to_sequence") is Some(to_sequence) &&
        text(fields, "answer") is Some(answer) else {
        return None
      }
      Some(ContextYield(to_sequence~, answer~))
    }
    "session_started" => {
      guard text(fields, "session") is Some(session) &&
        text(fields, "session_root") is Some(session_root) else {
        return None
      }
      Some(
        SessionStarted(
          session~,
          session_root~,
          workspace_root=text(fields, "workspace_root"),
        ),
      )
    }
    "session_error" => text(fields, "error").map(error => SessionError(error~))
    "workspace_created" =>
      text(fields, "dir").map(dir => WorkspaceCreated(dir~))
    "command_error" => text(fields, "error").map(error => CommandError(error~))
    "fleet_started" => {
      guard int(fields, "runs") is Some(runs) &&
        text(fields, "task") is Some(task) else {
        return None
      }
      Some(FleetStarted(runs~, task~))
    }
    "mcp_config_ignored" =>
      text(fields, "reason").map(reason => McpConfigIgnored(reason~))
    "mcp_config_unreadable" => {
      guard text(fields, "path") is Some(path) &&
        text(fields, "error") is Some(error) else {
        return None
      }
      Some(McpConfigUnreadable(path~, error~))
    }
    "mcp_config_invalid" => {
      guard text(fields, "path") is Some(path) &&
        text(fields, "error") is Some(error) else {
        return None
      }
      Some(McpConfigInvalid(path~, error~))
    }
    "mcp_tools_registered" => {
      guard int(fields, "servers") is Some(servers) &&
        int(fields, "tools") is Some(tools) &&
        fields.get("names") is Some(Array(names)) else {
        return None
      }
      let decoded = []
      for name in names {
        guard name is String(name) else { return None }
        decoded.push(name)
      }
      Some(McpToolsRegistered(servers~, tools~, names=decoded))
    }
    "mcp_tool_duplicate" => {
      guard text(fields, "server") is Some(server) &&
        text(fields, "tool") is Some(tool) else {
        return None
      }
      Some(McpToolDuplicate(server~, tool~))
    }
    "mcp_tool_renamed" => {
      guard text(fields, "from") is Some(from) && text(fields, "to") is Some(to) else {
        return None
      }
      Some(McpToolRenamed(from~, to~))
    }
    "mcp_tools_capped" => {
      guard text(fields, "server") is Some(server) &&
        int(fields, "kept") is Some(kept) else {
        return None
      }
      Some(McpToolsCapped(server~, kept~))
    }
    "mcp_server_skipped_over_cap" =>
      text(fields, "server").map(server => McpServerSkippedOverCap(server~))
    // `error` is null when the connection yielded no error value.
    "mcp_connect_failed" =>
      text(fields, "server").map(server => {
        McpConnectFailed(server~, error=text(fields, "error"))
      })
    "mcp_list_tools_failed" => {
      guard text(fields, "server") is Some(server) &&
        text(fields, "error") is Some(error) else {
        return None
      }
      Some(McpListToolsFailed(server~, error~))
    }
    "mcp_list_tools_timeout" =>
      text(fields, "server").map(server => McpListToolsTimeout(server~))
    "mcp_no_tools" => text(fields, "server").map(server => McpNoTools(server~))
    _ => None
  }
}

///|
fn text(fields : Map[String, Json], key : String) -> String? {
  guard fields.get(key) is Some(String(value)) else { return None }
  Some(value)
}

///|
/// JSON has one number type, so an `Int` field arrives as a `Number`; reject a
/// fractional value rather than silently truncating it.
fn int(fields : Map[String, Json], key : String) -> Int? {
  guard fields.get(key) is Some(Number(value, ..)) else { return None }
  let rounded = value.to_int()
  guard rounded.to_double() == value else { return None }
  Some(rounded)
}

///|
fn bool(fields : Map[String, Json], key : String) -> Bool? {
  match fields.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// The `from_sequence`/`to_sequence` pair every compaction event carries.
fn sequences(fields : Map[String, Json]) -> (Int, Int)? {
  guard int(fields, "from_sequence") is Some(from_sequence) &&
    int(fields, "to_sequence") is Some(to_sequence) else {
    return None
  }
  Some((from_sequence, to_sequence))
}
