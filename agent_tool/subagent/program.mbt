///|
/// How long a script's `job_wait` may hold its call: under both the PTC
/// server's and the SDK's per-call deadlines, with room for admission.
const ProgramWaitMs : Int32 = 60_000

///|
/// How long one encoded `job_output` reply to a script may be: under PTC's
/// 64K-character reply cap, envelope included.
const ProgramReplyChars : Int32 = 60_000

///|
/// What a script's program gets of its own (see `@ptc.ProgramBinding`): the
/// subagent tools bound to its id, so it reaches only the children it
/// started; on close, those children are stopped; and it is pinned past the
/// wall-clock cap while it has live children, or just had.
///
/// The tools are program-callable only (the model has its own `subagent` and
/// job tools): `subagent`, `job_wait` (returns within 60 s with every listed
/// child's state), `job_output` (a child's outcome and its report, in
/// chunks that fit one reply), `job_stop`, `worktree` (integrate or discard
/// the changes of a worker it started), and `audit_context` (the session's
/// standing goal and baseline, or null).
///
/// `serialize` wraps the tool that writes the checkout (`worktree`), so it
/// takes the session's file lock as the file tools do.
pub fn program_binding(
  launcher : @agent_subagent.Launcher,
  runtime : @bgjobs.BgJobRuntime,
  kinds : Array[Kind],
  audit_context : () -> Json,
  serialize~ : (@agent_tool.AgentToolDefinition) -> @agent_tool.AgentToolDefinition,
) -> (String) -> @ptc.ProgramBinding {
  program => {
    let waiting = Ref(false)
    let tools = @agent_tool.Tools([
      program_tool(
        "subagent",
        (
          #|Start a child agent of `kind` on `input` in the background; returns
          #|data {job_id, session} at once. Up to 16 run at once in a session.
        ),
        {
          "type": "object",
          "properties": {
            "kind": {
              "type": "string",
              "enum": Json::array(kinds.map(kind => Json::string(kind.name))),
            },
            "input": { "type": "object" },
            "label": { "type": "string" },
            "max_steps": { "type": "integer" },
            "worktree": worktree_schema,
          },
          "required": ["kind", "input"],
        },
        arguments => {
          start(
            launcher,
            kinds,
            arguments,
            launch=Script(program~, call=launcher.started_by(program)),
          )
        },
      ),
      program_tool(
        "job_wait",
        (
          #|Wait until any of `job_ids` (children this script started) has ended,
          #|or at most 60 s; data.jobs gives each one's state. Remove ended ids
          #|before waiting again.
        ),
        {
          "type": "object",
          "properties": {
            "job_ids": { "type": "array", "items": { "type": "string" } },
          },
          "required": ["job_ids"],
        },
        arguments => wait(launcher, runtime, program, waiting, arguments),
      ),
      program_tool(
        "job_output",
        (
          #|A child's state, outcome and report: data.subagent, and data.report
          #|{chunk, offset, total, complete} with the report's JSON text from
          #|`offset`; read until complete, then parse the concatenation.
        ),
        {
          "type": "object",
          "properties": {
            "job_id": { "type": "string" },
            "offset": { "type": "integer" },
          },
          "required": ["job_id"],
        },
        arguments => output(launcher, runtime, program, arguments),
      ),
      program_tool(
        "job_stop",
        "Stop a child this script started; returns once it has ended.",
        {
          "type": "object",
          "properties": { "job_id": { "type": "string" } },
          "required": ["job_id"],
        },
        arguments => {
          guard arguments is { "job_id": String(job_id), .. } &&
            launcher.owns(program, job_id) else {
            return @agent_tool.respond(
              "error: job_stop takes the job_id of a child this script started",
              is_error=true,
            )
          }
          ignore(runtime.stop(job_id))
          @agent_tool.respond("stopped \{job_id}", data={ "job_id": job_id })
        },
      ),
      serialize(
        program_tool(
          "worktree",
          (
            #|Show (diff), integrate, continue or abort integrating, or discard the
            #|worktree of a worker this script started, once it has ended: `action`
            #|and its `worker` job_id. data.worktree is its state after a change.
          ),
          {
            "type": "object",
            "properties": {
              "action": {
                "type": "string",
                "enum": ["diff", "integrate", "continue", "abort", "discard"],
              },
              "worker": { "type": "string" },
            },
            "required": ["action", "worker"],
          },
          arguments => {
            act(launcher, arguments, may=job_id => {
              launcher.owns(program, job_id)
            })
          },
        ),
      ),
      program_tool(
        "audit_context",
        (
          #|The session's standing goal and its recorded baseline, {goal, sha?,
          #|dirty?}, or null when no goal stands: what an audit is held to.
        ),
        { "type": "object", "properties": {} },
        _ => {
          let context = audit_context()
          @agent_tool.respond(context.stringify(), data=context)
        },
      ),
    ]) catch {
      error => abort("subagent program tools: \{error}")
    }
    {
      tools,
      close: () => launcher.close_owner(program),
      pinned: () => launcher.pinned(program),
    }
  }
}

///|
fn program_tool(
  name : String,
  description : String,
  schema : Json,
  execute : async (Json) -> @agent_tool.ToolAction,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name~,
    description~,
    schema=JsonSchema(schema),
    execute=Async(execute),
    concurrent_safe=true,
    program_callable=true,
  )
}

///|
/// A child's state as a script reads it.
fn job_state(runtime : @bgjobs.BgJobRuntime, job_id : String) -> Json {
  match runtime.snapshot(job_id) {
    Some({ subagent: Some({ outcome: Some(outcome), .. }), .. }) =>
      {
        "job_id": job_id,
        "state": "ended",
        "outcome": @agent_subagent.describe_outcome(outcome),
      }
    Some(_) => { "job_id": job_id, "state": "running" }
    None => { "job_id": job_id, "state": "unknown" }
  }
}

///|
async fn wait(
  launcher : @agent_subagent.Launcher,
  runtime : @bgjobs.BgJobRuntime,
  program : String,
  waiting : Ref[Bool],
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "job_ids": Array(listed), .. } &&
    listed.length() is (1..<=32) else {
    return @agent_tool.respond(
      "error: job_wait takes 1 to 32 job_ids",
      is_error=true,
    )
  }
  let ids : Array[String] = []
  for id in listed {
    guard id is String(id) && launcher.owns(program, id) else {
      return @agent_tool.respond(
        "error: job_wait takes only children this script started; \{id.stringify()} is not one",
        is_error=true,
      )
    }
    ids.push(id)
  }
  guard !waiting.val else {
    return @agent_tool.respond(
      "error: this script already has a job_wait in flight; one wait can list all its children",
      is_error=true,
    )
  }
  waiting.val = true
  defer {
    waiting.val = false
  }
  ignore(@async.with_timeout_opt(ProgramWaitMs, () => runtime.wait_any(ids)))
  let jobs = Json::array(ids.map(id => job_state(runtime, id)))
  @agent_tool.respond(jobs.stringify(), data={ "jobs": jobs })
}

///|
fn output(
  launcher : @agent_subagent.Launcher,
  runtime : @bgjobs.BgJobRuntime,
  program : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "job_id": String(job_id), .. } &&
    launcher.owns(program, job_id) &&
    runtime.snapshot(job_id) is Some({ subagent: Some(info), .. }) else {
    return @agent_tool.respond(
      "error: job_output takes the job_id of a child this script started",
      is_error=true,
    )
  }
  let offset = match arguments {
    { "offset": Number(offset, ..), .. } if offset >= 0.0 => offset.to_int()
    _ => 0
  }
  let data : Map[String, Json] = {
    "job_id": Json::string(job_id),
    "state": job_state(runtime, job_id),
    "subagent": info.to_json(),
  }
  match launcher.report(info.session) {
    None => ()
    Some(report) => {
      // Offsets count characters of the report's JSON text. The chunk is
      // the largest that keeps this whole reply, encoded, under the cap.
      let text = report.stringify()
      let total = text.char_length()
      let from = if offset > total { total } else { offset }
      let mut size = total - from
      for ;; {
        let chunk = String::from_iter(text.iter().drop(from).take(size))
        let complete = from + size >= total
        data["report"] = {
          "chunk": Json::string(chunk),
          "offset": Json::number(from.to_double()),
          "total": Json::number(total.to_double()),
          "complete": Json::boolean(complete),
        }
        if Json::object(data).stringify().length() <= ProgramReplyChars ||
          size <= 1 {
          break
        }
        size = size / 2
      }
    }
  }
  let reply = Json::object(data)
  @agent_tool.respond("subagent \{job_id}: \{info.label}", data=reply)
}
