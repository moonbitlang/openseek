///|
/// Run one bounded agent turn IN THE CALLING PROCESS with a restricted
/// toolset, and return the structured value the turn submitted through a
/// `capture_tool` — `None` when the model finished without submitting. This
/// is what a sub-run *kind* (review, explore, worker, ...) is made of;
/// nothing here spawns, and nothing here knows whether it is running inside
/// a child process at all. Three callers share it: `openseek run --kind
/// <kind>` (where the calling process IS the sub-run, when a parent launched
/// it), the
/// standalone review CLI (its own process by construction), and
/// kind-internals unit tests (which get the full lifecycle — capture,
/// reject-retry, ceiling salvage — against a mock endpoint without spawning
/// anything).
///
/// Process concerns deliberately absent: spawning, the wall deadline, cost
/// accounting, and terminal classification live in `agent_subrun`
/// (`run_subrun`), which observes a child from outside through its result
/// file and exit. Events go to the process's event stream as always.
pub async fn[T] execute_kind(
  session_id~ : String,
  system_prompt~ : String,
  task~ : String,
  tools~ : (Ref[T?]) -> @agent_tool.Tools raise,
  max_steps~ : Int,
  api_key~ : String,
  model~ : @deepseek.Model,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  retry_attempts? : Int,
  retry_backoff_ms? : Int,
  workspace_root? : String = ".",
  append_item? : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
) -> T? {
  let captured : Ref[T?] = { val: None, }
  let tools = tools(captured)
  let session = @agent_session.Session(SessionId(session_id), system_prompt~)
  // Default: the transcript lives and dies with this process. A caller
  // wires a store-backed append (a `run --kind` child with a session) to
  // make the child's transcript a first-class session.
  let append = match append_item {
    Some(append) => append
    None => (session, item) => session.append(item)
  }
  let _ : @agent_session.Session = @async.with_task_group() <| group => {
    @agent.run_turn_in_scope(
      runtime=AgentRuntime(workspace_root~),
      scope=AgentTaskScope(group),
      api_key~,
      model~,
      session~,
      content=Content([Text(task)]),
      append_item=append,
      max_steps~,
      thinking~,
      api_url?,
      retry_attempts?,
      retry_backoff_ms?,
      tools~,
    )
  }
  captured.val
}
