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
  queued : Bool
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
  queued~ : Bool = false,
  notify : (MessageReceipt) -> Unit,
) -> MessageSubmission {
  {
    run_id,
    steering,
    queued,
    receipt: self.message_receipts.watch(id, notify),
  }
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
/// A stopped/failed predecessor leaves ordinary composer queue entries for
/// the user's existing resume controls. A transcript-owned queued task has
/// no such row: withdraw just those entries and release their waiting cards.
fn ServeEngine::drop_unpromoted_host_inputs(self : ServeEngine) -> Unit {
  self.queued_runs.retain(queued => {
    if queued.host_owned {
      self.message_receipts.settle(queued.id, Dropped)
      false
    } else {
      true
    }
  })
}

///|
/// Submit host-owned input to an existing conversation. A live process keeps
/// its model/configuration; a reclaimed process is resumed with host defaults.
/// Work here supplies the source composer's options: idle input goes through
/// ordinary run configuration, and running input follows its steer/queue choice.
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
  here_options? : @protocol.SessionStartHereOptions,
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
        Running(run_id~, ..) if here_options is Some(options) &&
          options.followup_behavior == "queue" => {
          let reply = queue_run(manager, {
            run_id,
            action: QueueAdd(id=submission_id, text~, images=[]),
          })
          guard reply.accepted &&
            live.queued_runs.search_by(queued => queued.id == submission_id)
            is Some(index) else {
            raise EngineError("conversation stopped accepting queued input")
          }
          let queued = live.queued_runs[index]
          live.queued_runs[index] = { ..queued, host_owned: true, }
          return live.watch_message(
            queued.run_id,
            submission_id,
            steering=false,
            queued=true,
            notify,
          )
        }
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
        Idle(..) if here_options is Some(_) => ()
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
    task: text,
    images: [],
    submission_id: Some(submission_id),
    session,
    workspace: None,
    model: here_options.bind(options => options.model),
    thinking: here_options.bind(options => options.thinking),
    approval: here_options.bind(options => options.approval),
    max_steps: here_options.bind(options => options.max_steps),
  })
  guard manager.serving().get(session) is Some(slot) &&
    slot.live() is Some(live) else {
    raise EngineError("conversation stopped before delivery could be observed")
  }
  live.watch_message(reply.run_id, submission_id, steering=false, notify)
}
