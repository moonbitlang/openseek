///|
pub(all) enum MessageReceipt {
  Applied
  Dropped
  Closed
}

///|
pub struct MessageSubmission {
  run_id : String
  steering : Bool
  priv receipt : @message_receipts.Receipt[MessageReceipt]
}

///|
pub fn MessageSubmission::close(self : MessageSubmission) -> Unit {
  self.receipt.close()
}

///|
pub fn MessageSubmission::result(self : MessageSubmission) -> MessageReceipt? {
  self.receipt.result()
}

///|
fn ServeEngine::watch_message(
  self : ServeEngine,
  run_id : String,
  id : String,
  steering~ : Bool,
  notify : (MessageReceipt) -> Unit,
) -> MessageSubmission {
  { run_id, steering, receipt: self.message_receipts.watch(id, notify), }
}

///|
/// These commands are still in the host queue: no bytes from them reached
/// stdin. Report them as dropped input to the waiting sender.
fn ServeEngine::drop_unwritten_message(
  self : ServeEngine,
  command : @wire.Command,
) -> Unit {
  match command {
    Prompt(submission_id=Some(id), ..) | Steer(submission_id=Some(id), ..) =>
      self.message_receipts.settle(id, Dropped)
    _ => ()
  }
}

///|
/// Submit host-owned input to an existing conversation. A live process keeps
/// its model/configuration; a reclaimed process is resumed with host defaults.
/// Reject input while compaction is in progress. A returned submission is
/// admission only; the caller confirms the durable User submission id.
/// The receipt observer outlives turn-finished and settles on the exact steer
/// receipt, a definitely unwritten command, or the engine consumer's exit.
pub async fn submit_session_message(
  manager : EngineManager,
  sink : EventSink,
  session : String,
  text : String,
  submission_id : String,
  notify : (MessageReceipt) -> Unit,
) -> MessageSubmission {
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
        Compacting(..) =>
          raise EngineError(
            "conversation is compacting; message was not submitted",
          )
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
          return live.watch_message(
            run_id,
            submission_id,
            steering=true,
            notify,
          )
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
          return live.watch_message(
            run_id,
            submission_id,
            steering=false,
            notify,
          )
        }
      }
    }
  }
  let reply = start_run(sink, manager, {
    system_prompt: None,
    task: text,
    images: [],
    submission_id: Some(submission_id),
    session,
    workspace: None,
    model: None,
    thinking: None,
    approval: None,
    max_steps: None,
  })
  guard manager.serving().get(session) is Some(slot) &&
    slot.live() is Some(live) else {
    raise EngineError("conversation stopped before delivery could be observed")
  }
  live.watch_message(reply.run_id, submission_id, steering=false, notify)
}
