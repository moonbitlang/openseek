///|
/// Tool `subagent`: start a child agent in the background and return at once.
///
/// The child is a background job of the session (see `@agent_subagent`), so
/// the model waits, reads and stops it with the job tools it already knows:
/// `job_wait`, `job_output`, `job_stop`. Nothing holds the turn for the
/// child's lifetime, which may be hours.
pub fn definition(
  launcher : @agent_subagent.Launcher,
  kinds : Array[Kind],
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="subagent",
    description=(
      #|Start a child agent in the background on a self-contained task and get its
      #|job_id at once; it runs in its own context and session while you keep working.
      #|kind "explore": answers a question about the code with citations; input
      #|{"query": "...", "hints"?: "..."}. kind "review": an advisory audit, input
      #|{"goal": "..."} (the worktree against a goal) or {"base": "<ref>"} (the
      #|base...HEAD diff). kind "worker": makes a change, input {"task": "...",
      #|"context"?: "..."}, plus worktree {"name": "<slug>", "allowed_paths": [...]}:
      #|it works in a new git worktree forked from HEAD (commit what it needs first) and
      #|may change only allowed_paths, disjoint from other live workers'. You get a notice
      #|when it ends; job_wait waits for it, job_output reads its outcome and report,
      #|job_stop stops it. Then use the worktree tool to review (diff), integrate or
      #|discard a worker's changes. Up to four run at once. Give each a
      #|complete brief: it does not see this conversation.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "kind": {
          "type": "string",
          "enum": Json::array(kinds.map(kind => Json::string(kind.name))),
        },
        "input": {
          "type": "object",
          "description": "The child's input, exactly as its kind takes it.",
        },
        "label": {
          "type": "string",
          "description": "A few words naming the task, shown in the jobs panel.",
        },
        "max_steps": {
          "type": "integer",
          "description": "Optional step budget, capped at the kind's own.",
        },
        "worktree": worktree_schema,
      },
      "required": ["kind", "input"],
    }),
    execute=Async(arguments => start(launcher, kinds, arguments, launch=Direct)),
    concurrent_safe=true,
  )
}

///|
/// A kind of child this tool starts: its name, its step ceiling, and the
/// check its report must pass to count as captured (the report kept is what
/// the check returns).
pub(all) struct Kind {
  name : String
  ceiling : Int32
  validate : (Json) -> Result[Json, String]
  /// Whether a running child of this kind reads instructions sent to it.
  takes_instructions : Bool
  /// It changes code, in a worktree of its own: a start names the worktree
  /// and the paths it may change.
  worktree : Bool
}

///|
/// What a session that may delegate gives `build_tools`: how to make its
/// launcher over its job runtime, and the kinds the tool offers.
pub(all) struct Subagents {
  launcher : (@bgjobs.BgJobRuntime) -> @agent_subagent.Launcher
  kinds : Array[Kind]
  /// The session's standing goal and baseline for a script's audit, read
  /// when asked: `{goal, sha?, dirty?}`, or null.
  audit_context : () -> Json
}

///|

///|
/// Start a child for the model (`Direct`) or a script (`Script`): the same
/// checks and launcher either way; the model is told in words how to follow
/// the child up, a script gets `{job_id, session}` in data.
async fn start(
  launcher : @agent_subagent.Launcher,
  kinds : Array[Kind],
  arguments : Json,
  launch~ : @protocol.SubagentLaunch,
) -> @agent_tool.ToolAction {
  guard arguments is { "kind": String(name), "input": Object(_) as input, .. } else {
    return @agent_tool.respond(
      "error: subagent requires a kind and an input object",
      is_error=true,
    )
  }
  guard kinds.iter().find_first(kind => kind.name == name) is Some(kind) else {
    let names = kinds.map(kind => kind.name).join(", ")
    return @agent_tool.respond(
      "error: subagent kind must be one of \{names}, not \{Json(name).stringify()}",
      is_error=true,
    )
  }
  let slice : @agent_subagent.Slice? = match (kind.worktree, arguments) {
    (
      true,
      { "worktree": { "name": String(slug), "allowed_paths": paths, .. }, .. },
    ) if strings(paths) is Some(allowed_paths) =>
      Some({ name: slug, allowed_paths, })
    (true, _) =>
      return @agent_tool.respond(
        "error: a \{name} needs worktree {\"name\": \"<slug>\", \"allowed_paths\": [\"<path prefix>\", ...]}",
        is_error=true,
      )
    (false, { "worktree": _, .. }) =>
      return @agent_tool.respond(
        "error: only a kind that changes code takes a worktree; \{name} works in this checkout",
        is_error=true,
      )
    (false, _) => None
  }
  let label = match arguments {
    { "label": String(label), .. } if !label.is_blank() =>
      @agent_tool.brief_line(label, limit=72)
    _ => name
  }
  // Always bounded by the kind's ceiling: an omitted budget is the
  // ceiling, never the engine's own default, which may be far larger.
  let max_steps = match arguments {
    { "max_steps": Number(steps, ..), .. } if steps >= 1.0 &&
      steps < kind.ceiling.to_double() => steps.to_int()
    _ => kind.ceiling
  }
  match
    launcher.start(
      kind=name,
      input~,
      label~,
      max_steps~,
      launch~,
      validate=kind.validate,
      slice?,
    ) {
    Started(job_id~, session~) if launch is Script(_) =>
      @agent_tool.respond("started subagent \{job_id} (\{name}: \{label})", data={
        "job_id": job_id,
        "session": session,
      })
    Started(job_id~, session~) =>
      @agent_tool.respond(
        (
          $|Started subagent job \{job_id} (\{name}: \{label}), recording to session \{session}.
          $|It runs in the background; you will get a notice when it ends.
          $|Wait for it: job_wait (job_ids=["\{job_id}"])
          $|Read its outcome and report: job_output (job_id="\{job_id}")
          $|Stop it: job_stop (job_id="\{job_id}")
        ),
        brief="subagent \{name}: \{label}",
        data={ "job_id": job_id, "session": session },
      )
    Busy =>
      @agent_tool.respond(
        "error: \{launcher.max_live()} subagents are already running; wait for one to end (job_wait) and start this one again. Nothing was started.",
        is_error=true,
      )
    Unavailable(reason) =>
      @agent_tool.respond(
        "error: subagent not started: \{reason}",
        is_error=true,
      )
  }
}

///|
/// Tool `subagent_send`: give a running subagent a new instruction. The child
/// takes it at its next step, as a user's steering, and adjusts its course.
pub fn send_definition(
  launcher : @agent_subagent.Launcher,
  kinds : Array[Kind],
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="subagent_send",
    description=(
      #|Send a running subagent (by its job_id) a new instruction: a correction, a
      #|narrower question, or a request to wrap up and report what it has. It takes
      #|it at its next step. Only explore subagents take instructions.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "job_id": { "type": "string" },
        "message": { "type": "string" },
      },
      "required": ["job_id", "message"],
    }),
    execute=Async(arguments => send(launcher, kinds, arguments)),
    concurrent_safe=true,
  )
}

///|
async fn send(
  launcher : @agent_subagent.Launcher,
  kinds : Array[Kind],
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "job_id": String(job_id), "message": String(text), .. } else {
    return @agent_tool.respond(
      "error: subagent_send requires a job_id and a message",
      is_error=true,
    )
  }
  // A child of a kind that reads no instructions never will: say so, rather
  // than letting the model retry a send that cannot be delivered.
  if launcher.subagent(job_id) is Some(info) &&
    !kinds.any(kind => kind.name == info.kind && kind.takes_instructions) {
    return @agent_tool.respond(
      "error: a \{info.kind} subagent takes no instructions; to change its task, stop it (job_stop) and start another with the new brief",
      is_error=true,
    )
  }
  match launcher.send(job_id, text) {
    Sent(receipt~) =>
      @agent_tool.respond(
        "sent to subagent \{job_id}; it takes the instruction at its next step",
        data={ "job_id": job_id, "receipt": receipt },
      )
    NotReady =>
      @agent_tool.respond(
        "error: subagent \{job_id} is still starting and is not taking instructions yet; retry shortly",
        is_error=true,
      )
    Ended =>
      @agent_tool.respond(
        "error: subagent \{job_id} has ended; read its outcome with job_output",
        is_error=true,
      )
    Unknown =>
      @agent_tool.respond(
        "error: no subagent job with id \{job_id}",
        is_error=true,
      )
    Invalid(reason) => @agent_tool.respond("error: \{reason}", is_error=true)
  }
}

///|
/// The `worktree` argument of a start, for a kind that changes code.
let worktree_schema : Json = {
  "type": "object",
  "description": "A worker's worktree: a short lowercase slug naming it, and the repository-relative path prefixes it may change.",
  "properties": {
    "name": { "type": "string" },
    "allowed_paths": { "type": "array", "items": { "type": "string" } },
  },
  "required": ["name", "allowed_paths"],
}

///|
/// `json` as an array of strings, if it is one.
fn strings(json : Json) -> Array[String]? {
  guard json is Array(items) else { return None }
  let found = []
  for item in items {
    guard item is String(text) else { return None }
    found.push(text)
  }
  Some(found)
}
