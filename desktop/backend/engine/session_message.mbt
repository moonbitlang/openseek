///|
/// Submit host-owned input to an existing conversation. A live process keeps
/// its model/configuration; a reclaimed process is resumed with host defaults.
/// None means compaction is in progress: retry after its lifecycle event.
/// Some is admission only; the caller confirms the durable User submission id.
pub async fn submit_session_message(
  manager : EngineManager,
  sink : EventSink,
  session : String,
  text : String,
  submission_id : String,
) -> String? {
  guard !text.is_blank() &&
    normalize_submission_id(Some(submission_id)) is Some(_) else {
    raise EngineError("message text and a valid submission id are required")
  }
  let sessions = manager.serving()
  if sessions.get(session) is Some(slot) {
    guard slot.pending is None else {
      raise EngineError("conversation is changing; message was not submitted")
    }
    if slot.live() is Some(live) {
      match live.phase {
        Compacting(..) => return None
        Running(run_id~, ..) => {
          let reply = steer_run(manager, {
            text,
            images: [],
            run_id: Some(run_id),
            submission_id: Some(submission_id),
          })
          guard reply.steered else {
            raise EngineError("conversation stopped accepting messages")
          }
          return Some(run_id)
        }
        Idle(..) => {
          let run_id = mint_run_id()
          let content = prompt_content(text, [])
          guard live.submit(
            @protocol.prompt(content, submission_id~),
            failure_reason="failed to write cross-conversation input",
          ) else {
            raise EngineError("conversation stopped accepting messages")
          }
          live.phase = Running(run_id~, compact_queued=false)
          live.steer_runs.begin_run()
          emit(
            sink,
            Started({
              run_id,
              submission_id: Some(submission_id),
              engine: Some(live.engine_name),
              model: Some(live.model),
              max_steps: Some(live.max_steps),
              session,
              session_root: live.session_root.map(root => root.resource_path()),
            }),
          )
          return Some(run_id)
        }
      }
    }
  }
  let reply = start_run(sink, manager, {
    task: text,
    images: [],
    submission_id: Some(submission_id),
    session,
    workspace: None,
    model: None,
    thinking: None,
    max_steps: None,
  })
  Some(reply.run_id)
}
