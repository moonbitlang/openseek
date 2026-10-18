///|
/// Tool `worktree`: what becomes of a worker's changes once it has ended.
/// A worker commits nothing here: its changes wait on a branch in its own
/// worktree until this session integrates or discards them.
pub fn worktree_definition(
  launcher : @agent_subagent.Launcher,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="worktree",
    description=(
      #|Act on a worker subagent's worktree once the worker has ended. action "list": the
      #|worktrees of this session's workers, each with its worker's session and state.
      #|"integrate": merge a worker's committed changes into this checkout, which must have
      #|no uncommitted changes to tracked files; re-run your checks after. If that
      #|conflicts, resolve the markers here with the file tools, then "continue" (or
      #|"abort", which leaves the branch and worktree). "discard": remove the worktree and
      #|its branch without integrating. Name the worker by its job_id, or by its session
      #|from "list".
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "action": {
          "type": "string",
          "enum": ["list", "integrate", "continue", "abort", "discard"],
        },
        "worker": {
          "type": "string",
          "description": "The worker's job_id or session; not for list.",
        },
      },
      "required": ["action"],
    }),
    execute=Async(arguments => {
      if arguments is { "action": "list", .. } {
        return list(launcher)
      }
      act(launcher, arguments, may=_ => true)
    }),
  )
}

///|
/// The worktrees of the session's workers, in words.
async fn list(launcher : @agent_subagent.Launcher) -> @agent_tool.ToolAction {
  match launcher.worktrees() {
    Err(reason) =>
      @agent_tool.respond(
        "error: could not list worktrees: \{reason}",
        is_error=true,
      )
    Ok([]) => @agent_tool.respond("No worker of this session has a worktree.")
    Ok(found) => {
      let lines = found.map(entry => {
        let (session, worktree) = entry
        "- \{worktree.name} (session \{session}): branch \{worktree.branch} at \{worktree.path}, \{@agent_subagent.describe_state(worktree.state)}"
      })
      @agent_tool.respond(lines.join("\n"), brief="worktrees", data={
        "worktrees": Json::array(
          found.map(entry => {
            "session": entry.0,
            "worktree": entry.1.to_json(),
          }),
        ),
      })
    }
  }
}

///|
/// Integrate, continue, abort or discard the worktree of the worker
/// `arguments.worker`, if `may` allows it.
async fn act(
  launcher : @agent_subagent.Launcher,
  arguments : Json,
  may~ : (String) -> Bool,
) -> @agent_tool.ToolAction {
  let action : @agent_subagent.WorktreeAction? = match arguments {
    { "action": "integrate", .. } => Some(Integrate)
    { "action": "continue", .. } => Some(Continue)
    { "action": "abort", .. } => Some(Abort)
    { "action": "discard", .. } => Some(Discard)
    _ => None
  }
  guard action is Some(action) &&
    arguments is { "worker": String(worker), .. } &&
    may(worker) else {
    return @agent_tool.respond(
      "error: worktree takes an action (integrate, continue, abort or discard) and the worker it names",
      is_error=true,
    )
  }
  match launcher.worktree(worker, action) {
    Changed(worktree, detail~) =>
      @agent_tool.respond(
        (
          $|Worktree \{worktree.name} (branch \{worktree.branch}): \{@agent_subagent.describe_state(worktree.state)}.
          $|\{detail.join("\n")}
        ),
        brief="worktree \{worktree.name}",
        data={ "worktree": worktree.to_json() },
      )
    Refused(reason) =>
      @agent_tool.respond("error: nothing changed: \{reason}", is_error=true)
    Unknown =>
      @agent_tool.respond(
        "error: no worker of this session named \{worker} has a worktree",
        is_error=true,
      )
  }
}
