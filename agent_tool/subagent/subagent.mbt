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
      #|{"query": "...", "hints"?: [...]}. kind "review": an advisory audit, input
      #|{"goal": "..."} (the worktree against a goal) or {"base": "<ref>"} (the
      #|base...HEAD diff). You get a notice when it ends; job_wait waits for it,
      #|job_output reads its outcome and report, job_stop stops it. Up to four run at
      #|once. Give each a complete brief: it does not see this conversation.
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
      },
      "required": ["kind", "input"],
    }),
    execute=Async(arguments => execute(launcher, kinds, arguments)),
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
}

///|
/// What a session that may delegate gives `build_tools`: how to make its
/// launcher over its job runtime, and the kinds the tool offers.
pub(all) struct Subagents {
  launcher : (@bgjobs.BgJobRuntime) -> @agent_subagent.Launcher
  kinds : Array[Kind]
}

///|
async fn execute(
  launcher : @agent_subagent.Launcher,
  kinds : Array[Kind],
  arguments : Json,
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
  let label = match arguments {
    { "label": String(label), .. } if !label.is_blank() =>
      @agent_tool.brief_line(label, limit=72)
    _ => name
  }
  let max_steps = match arguments {
    { "max_steps": Number(steps, ..), .. } if steps >= 1.0 => {
      let steps = steps.to_int()
      Some(if steps > kind.ceiling { kind.ceiling } else { steps })
    }
    _ => None
  }
  match
    launcher.start(
      kind=name,
      input~,
      label~,
      max_steps?,
      launch=Direct,
      validate=kind.validate,
    ) {
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
