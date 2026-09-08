///|
/// Define event-driven waiting, handled by the agent loop.
pub fn definition() -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="job_wait",
    description=(
      #|Wait for any selected background job to finish, or until user input arrives.
      #|Use when you need those results and have no other work to do. No timeout or
      #|polling is needed. Call this tool alone in its batch. Returns job states;
      #|read logs afterward with job_output. Use finish if your work is already done.
      #|Runtime watchdogs still apply; a job may be stopped at its output or time cap.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "job_ids": {
          "type": "array",
          "items": { "type": "string", "minLength": 1 },
          "minItems": 1,
        },
      },
      "required": ["job_ids"],
      "additionalProperties": false,
    }),
    execute=Sync(execute),
    // The control flag permits execution at the context ceiling. Waiting
    // needs another model step, so deliberately do not grant that privilege.
  )
}

///|
fn execute(arguments : Json) -> @agent_tool.ToolAction {
  guard arguments is { "job_ids": Array(values), .. } && !values.is_empty() else {
    return @agent_tool.respond(
      "error: job_wait requires a nonempty job_ids array",
      is_error=true,
    )
  }
  if arguments is Object(fields) && fields.keys().any(key => key != "job_ids") {
    return @agent_tool.respond(
      "error: job_wait only accepts job_ids (no timeout)",
      is_error=true,
    )
  }
  let ids : Array[String] = []
  for value in values {
    guard value is String(id) && !id.is_blank() else {
      return @agent_tool.respond(
        "error: job_wait job_ids must contain nonblank strings",
        is_error=true,
      )
    }
    if !ids.contains(id) {
      ids.push(id)
    }
  }
  @agent_tool.ToolAction::wait_jobs(ids)
}
