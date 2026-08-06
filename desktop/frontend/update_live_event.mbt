// Live engine-event, streaming, and compaction transitions.

///|
/// Whether an event the engine emits while idle (between turns) — the
/// compaction lifecycle and background-job notices — so the routing must
/// match by last run id: the run that owned the id has already cleared
/// `active_run_id` by the time these arrive.
fn is_idle_event(event : @transcript.EngineEvent) -> Bool {
  match event {
    CompactionStarted
    | CompactionFinished(_)
    | CompactionFailed(_)
    | RuntimeUpdate(_) => true
    _ => false
  }
}

///|
/// Fold one engine event into its conversation. Returns whether the
/// transcript visibly grew (the caller turns that into a scroll command only
/// when this conversation is the one on screen) and the new conversation.
fn apply_engine_event(
  conv : Conversation,
  event : @transcript.EngineEvent,
  event_run_id : String?,
) -> (Bool, Conversation) {
  match event {
    AgentStep(step) => {
      let conv = conv.clear_streams()
      (
        false,
        // A step can only advance an open, uncancelled turn: after a Stop the
        // stage stays Cancelling (steering a dying turn is refused, so the
        // display must not flip the gate back open), and a stray step for a
        // closed run changes nothing.
        if conv.run is Open(run_id~, stage~) && !(stage is Cancelling) {
          { ..conv, run: Open(run_id~, stage=AtStep(step)) }
        } else {
          conv
        },
      )
    }
    AssistantDelta(content) =>
      if content.is_empty() {
        (false, conv)
      } else {
        (
          true,
          { ..conv, streaming_response: conv.streaming_response + content },
        )
      }
    // Full semantic events never append transcript items: the store commit is
    // the sole source of the durable reasoning/answer item. The current wire
    // protocol has no live reasoning stream, while the full assistant event
    // settles the live response.
    ReasoningMessage(_) => (false, conv)
    AssistantMessage(_) => (false, conv.clear_streams())
    RuntimeUpdate(content) => {
      let update = @transcript.parse_runtime_update(content)
      (false, { ..conv, watcher_status: update.status })
    }
    Usage(prompt_tokens~, completion_tokens~) =>
      (false, { ..conv, usage_tokens: prompt_tokens + completion_tokens })
    ToolResult(..) => (false, conv)
    // The turn loop records this as an error `tool_result`; its commit is the
    // one canonical transcript source, just like a successful tool result.
    ToolCallDecodeError(..) => (false, conv)
    AgentFinished(_)
    | ContextYield(_)
    | AgentAborted(_)
    | AgentSetupFailed(_) => (false, conv.clear_streams())
    MaxStepsExhausted => (false, conv.clear_streams())
    // The steer took effect at a step boundary. Its durable user item arrives
    // through `session.event`; the live event only settles pending UI.
    SteerApplied(content~, submission_id~) => {
      ignore(content)
      if submission_id is Some(submission_id) {
        let (next, _) = conv.acknowledge_submission(
          submission_id,
          SteerInput,
          event_run_id,
        )
        (false, next)
      } else {
        // Legacy receipt: lifecycle information only. Text is not ownership
        // in a multi-client session, even when it happens to match.
        (false, conv)
      }
    }
    // The steer raced the turn's end through the pipes and was rejected; the
    // text must not vanish silently.
    SteerDropped(content~, submission_id~) =>
      if submission_id is Some(submission_id) {
        let (next, removed) = conv.reject_submission(
          submission_id,
          SteerInput,
          event_run_id,
          steer_dropped_notice(content),
        )
        (removed, next)
      } else {
        (false, conv)
      }
    AutoCompactionFinished(_) => (false, conv)
    CompactionStarted => (false, { ..conv, compaction: Compacting })
    CompactionFinished(_) => (false, { ..conv, compaction: NotCompacting })
    CompactionFailed(reason) => {
      let content = if reason.trim().is_empty() {
        "compaction failed"
      } else {
        "compaction failed: \{reason}"
      }
      (
        true,
        { ..conv, compaction: NotCompacting }.append_local_notice(
          Assistant(is_danger=true),
          content,
        ),
      )
    }
  }
}

///|
test "assistant deltas accumulate into the streaming response" {
  let dispatch = test_dispatch()
  let (_, first) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("Hello"), session=None),
    running_model(),
  )
  let (_, second) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta(", world"), session=None),
    first,
  )
  inspect(second.active().streaming_response, content="Hello, world")
  inspect(second.active().messages.length(), content="0")
}

///|
test "update is pure: replaying a delta on the same model is idempotent" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial",
  })
  let (_, once) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("!"), session=None),
    model,
  )
  let (_, twice) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("!"), session=None),
    model,
  )
  inspect(once.active().streaming_response, content="partial!")
  inspect(twice.active().streaming_response, content="partial!")
}

///|
test "deltas from an unknown run are dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r99"), AssistantDelta("stale"), session=None),
    running_model(),
  )
  inspect(next.active().streaming_response, content="")
}

///|
test "reasoning message waits for its durable commit" {
  let dispatch = test_dispatch()
  let model = running_model()
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("full thought"), session=None),
    model,
  )
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "assistant message only settles the transient response" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "answ",
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantMessage("answer"), session=None),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "agent setup failure is lifecycle-only until its durable terminal" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial answer",
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AgentSetupFailed("could not initialize"), session=None),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "a new agent step clears the live stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "left",
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AgentStep(Some(2)), session=None),
    model,
  )
  inspect(next.active().streaming_response, content="")
}

///|
test "finished run clears any leftover stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "leftover",
  })
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().is_running(), content="false")
}

///|
test "finished run reloads the named durable session for an old host" {
  let dispatch = test_dispatch()
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    running_model(),
  )
  guard finished.active().sync
    is Reloading(generation=1, reload_after_current=false, ..) else {
    fail("Finished did not start the compatibility snapshot")
  }
  // Old hosts send no session.event; their post-Finished full snapshot is
  // therefore the only canonical source the commit-aware frontend consumes.
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None },
        { kind: Assistant(is_danger=false), content: "done", ts: None },
      ],
      watermark=3,
      event_boundaries=[(3, true, 2)],
      generation=1,
    ),
    finished,
  )
  inspect(loaded.active().messages.length(), content="2")
  inspect(loaded.active().messages[1].content, content="done")
  inspect(loaded.active().watermark, content="3")
  assert_true(loaded.active().sync is Synced)
}

///|
test "Finished queues one follow-up behind an older in-flight snapshot" {
  let dispatch = test_dispatch()
  let model = {
    ..running_model().replace_conversation({
      ..running_conversation(),
      sync: test_reloading([]),
    }),
    transcript_request_generation: 1,
  }
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="finished",
    answer=None,
    durable_sequence=None,
  )
  let (_, finished) = update_dev(dispatch, finish, model)
  guard finished.active().sync
    is Reloading(generation=1, reload_after_current=true, ..) else {
    fail("Finished did not remember the post-boundary reload")
  }
  // A duplicate lifecycle notification is idempotent: it is not a second
  // durable boundary and must not queue another generation.
  let (_, duplicate) = update_dev(dispatch, finish, finished)
  guard duplicate.active().sync
    is Reloading(generation=1, reload_after_current=true, ..) else {
    fail("duplicate Finished changed the queued follow-up")
  }
  let (_, followed) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    duplicate,
  )
  guard followed.active().sync
    is Reloading(generation=2, reload_after_current=false, ..) else {
    fail("the older snapshot did not hand off to one fresh generation")
  }
}

///|
test "a finish the user watched leaves no unseen dot" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    running_model(),
  )
  inspect(next.active().unseen_finish, content="false")
}

///|
test "a background finish marks its conversation until it is opened" {
  let dispatch = test_dispatch()
  // The run belongs to "desktop-test"; the user is looking at another chat.
  let model = { ..running_model(), active_session: "desktop-elsewhere" }
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(conv) else {
    fail("conversation missing")
  }
  inspect(conv.unseen_finish, content="true")
  let opened = next.activate(@interop.ChannelId::Local, "desktop-test")
  guard opened.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(seen) else {
    fail("conversation missing after activate")
  }
  inspect(seen.unseen_finish, content="false")
}

///|
test "an idle background notice routes by the last run id" {
  let dispatch = test_dispatch()
  // The run already finished: `active_run_id` is cleared, only the last-run
  // memory ties the id back to its conversation.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    last_run_id: Some("r7"),
  })
  let notice = "[moon_check update]\nstatus=failed\nmain.mbt:1 error"
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), RuntimeUpdate(notice), session=None),
    model,
  )
  inspect(next.active().watcher_status, content="failed")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "run semantic errors never duplicate their terminal commit" {
  let dispatch = test_dispatch()
  let semantic = Error(
    run_id=Some("r7"),
    message="engine error",
    diagnostics=None,
    exit_code=None,
  )
  let terminal = SessionCommitted(
    session="desktop-test",
    sequence=1,
    ts=None,
    item=@protocol.Terminal(@protocol.Failed("engine error")),
  )
  let (_, semantic_first) = update_dev(dispatch, semantic, running_model())
  inspect(semantic_first.active().overlay.length(), content="0")
  let (_, committed_after) = update_dev(dispatch, terminal, semantic_first)
  inspect(committed_after.active().messages.length(), content="1")
  inspect(committed_after.active().overlay.length(), content="0")
  let (_, committed_first) = update_dev(dispatch, terminal, running_model())
  let (_, semantic_after) = update_dev(dispatch, semantic, committed_first)
  inspect(semantic_after.active().messages.length(), content="1")
  inspect(semantic_after.active().overlay.length(), content="0")
}

///|
test "a process-exit error keeps its host diagnostics as a local notice" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Error(
      run_id=Some("r7"),
      message="engine process exited",
      diagnostics=Some("fatal stderr"),
      exit_code=Some(9),
    ),
    running_model(),
  )
  inspect(next.active().overlay.length(), content="1")
  assert_true(next.active().overlay[0].content.contains("fatal stderr"))
}

///|
test "agent error decoder preserves exit codes and normalizes missing messages" {
  guard error_msg({
      run_id: Some("r7"),
      message: Some("exited"),
      exit_code: Some(9),
      diagnostics: None,
    })
    is Some(Error(exit_code=Some(9), ..)) else {
    fail("expected the exit code")
  }
  guard error_msg({
      run_id: None,
      message: None,
      exit_code: None,
      diagnostics: None,
    })
    is Some(Error(message="error", ..)) else {
    fail("expected the generic error label")
  }
}

///|
test "finished and durable-boundary decoders preserve exact EOF frontiers" {
  guard finished_msg({
      run_id: "r7",
      status: "failed",
      answer: None,
      exit_code: Some(9),
      durable_sequence: Some(12),
    })
    is Some(Finished(durable_sequence=Some(12), ..)) else {
    fail("expected the final-scan sequence")
  }
  guard durable_boundary_msg({
      run_id: "r7",
      session: "desktop-test",
      sequence: 12,
    })
    is Some(DurableBoundary(sequence=12, ..)) else {
    fail("expected the delayed durable boundary")
  }
}

///|
/// A prompt submitted mid-compaction must not start: the serve engine would
/// queue it behind the compaction, out of Stop's reach. The draft stays put.
test "a prompt submitted during compaction stays in the composer" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Compacting,
    task: "do the thing",
  })
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="do the thing")
  inspect(next.active().messages.length(), content="0")
}

///|
/// A `/compact` sent mid-turn queues behind the open run in the engine. The
/// composer must say so immediately, swallow a duplicate, and keep the send
/// gate held through the gap between the turn's end and the engine's
/// compaction_started.
test "a mid-turn /compact stays visibly queued until compaction starts" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..running_conversation(),
    last_run_id: Some("r7"),
  })
  let (_, queued) = run_slash_command(dispatch, model, "compact")
  assert_true(queued.active().compaction is Queued)
  // One compaction at a time: the repeat is swallowed, not re-sent.
  let (_, again) = run_slash_command(dispatch, queued, "compact")
  assert_true(again.active().compaction is Queued)
  // The turn ends before compaction_started arrives; a prompt sent into
  // that gap would queue behind the compaction, out of Stop's reach.
  let (_, ended) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="completed",
      answer=None,
      durable_sequence=None,
    ),
    again,
  )
  assert_true(ended.active().compaction is Queued)
  let drafted = ended.replace_conversation({
    ..ended.active(),
    task: "next prompt",
  })
  let (_, held) = update(dispatch, Send, drafted)
  inspect(held.active().task, content="next prompt")
  // The engine reaches the queued compaction: queued flips into compacting.
  let (_, started) = update_dev(
    dispatch,
    Engine(Some("r7"), CompactionStarted, session=None),
    held,
  )
  assert_true(started.active().compaction is Compacting)
}

///|
/// An idle `/compact` has no engine acknowledgment yet — the host may still
/// be spawning a serve engine for it (a resumed conversation compacted
/// before its first prompt) — but the request must hold the send gate
/// immediately: a prompt sent into that window would be consumed and
/// rejected by the host instead of held in the composer.
test "an idle /compact holds the send gate until the engine confirms" {
  let dispatch = test_dispatch()
  let (_, requested) = run_slash_command(dispatch, test_model(), "compact")
  assert_true(requested.active().compaction is Requested)
  // A repeat while the request is in flight is swallowed, not re-sent.
  let (_, again) = run_slash_command(dispatch, requested, "compact")
  assert_true(again.active().compaction is Requested)
  // A draft sent during the spawn/write window stays in the composer.
  let drafted = again.replace_conversation({
    ..again.active(),
    task: "next prompt",
  })
  let (_, held) = update(dispatch, Send, drafted)
  inspect(held.active().task, content="next prompt")
  inspect(held.active().messages.length(), content="0")
  // The engine confirms; the session stamp routes it (no run id exists yet).
  let (_, started) = update_dev(
    dispatch,
    Engine(None, CompactionStarted, session=Some("desktop-test")),
    held,
  )
  assert_true(started.active().compaction is Compacting)
}

///|
/// Rabbita purity: the automatic-checkpoint semantic event is lifecycle-only;
/// its Summary card comes from the durable commit.
test "update is pure: automatic checkpoint waits for its commit" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial",
  })
  let (_, once) = update_dev(
    dispatch,
    Engine(Some("r7"), AutoCompactionFinished("checkpoint recap"), session=None),
    model,
  )
  let (_, twice) = update_dev(
    dispatch,
    Engine(Some("r7"), AutoCompactionFinished("checkpoint recap"), session=None),
    model,
  )
  inspect(model.active().overlay.length(), content="0")
  inspect(once.active().overlay.length(), content="0")
  inspect(twice.active().overlay.length(), content="0")
  inspect(once.active().streaming_response, content="partial")
  inspect(twice.active().streaming_response, content="partial")
  assert_true(
    once.active().compaction is NotCompacting &&
    twice.active().compaction is NotCompacting,
  )
}

///|
/// Rabbita purity: context-yield guidance is a deterministic model update.
/// The raw stream event clears partial streams but does not close the run;
/// the host's following Finished message owns that transition.
test "update is pure: context yield waits for its commit" {
  let dispatch = test_dispatch()
  let answer = "[context ceiling] continue in a new turn"
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial",
  })
  let (_, once) = update_dev(
    dispatch,
    Engine(Some("r7"), ContextYield(answer), session=None),
    model,
  )
  let (_, twice) = update_dev(
    dispatch,
    Engine(Some("r7"), ContextYield(answer), session=None),
    model,
  )
  inspect(model.active().overlay.length(), content="0")
  inspect(once.active().overlay.length(), content="0")
  inspect(twice.active().overlay.length(), content="0")
  inspect(once.active().streaming_response, content="")
  inspect(twice.active().streaming_response, content="")
  assert_true(once.active().is_running() && twice.active().is_running())
}

///|
/// The successful ceiling path re-opens Send without synthesizing durable
/// transcript items. Its Summary and guidance arrive through commits.
test "context yield settles after its automatic checkpoint" {
  let dispatch = test_dispatch()
  let answer = "[context ceiling] continue in a new turn"
  let (_, checkpointed) = update_dev(
    dispatch,
    Engine(Some("r7"), AutoCompactionFinished("checkpoint recap"), session=None),
    running_model(),
  )
  let (_, yielded) = update_dev(
    dispatch,
    Engine(Some("r7"), ContextYield(answer), session=None),
    checkpointed,
  )
  assert_true(yielded.active().is_running())
  let (_, settled) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="context_yield",
      answer=Some(answer),
      durable_sequence=None,
    ),
    yielded,
  )
  inspect(settled.active().overlay.length(), content="0")
  assert_true(settled.active().compaction is NotCompacting)
  assert_false(settled.active().is_running())
  guard settled.display_status() is Finished(outcome) else {
    fail("expected a finished status")
  }
  assert_true(outcome is ContextYield)
  inspect(outcome.label(), content="Context limit reached")
  assert_true(settled.display_status().kind() is Warn)
}

///|
/// Compaction completion settles lifecycle state; its Summary is commit-only.
test "compaction_finished waits for its durable summary" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Compacting,
    last_run_id: Some("r7"),
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      CompactionFinished("earlier turns compacted"),
      session=None,
    ),
    model,
  )
  inspect(next.active().overlay.length(), content="0")
  assert_true(next.active().compaction is NotCompacting)
}

///|
/// A conversation resumed and compacted before its first prompt of this
/// app-lifetime has no run id anywhere — the spawned engine stamps run 0 and
/// the conversation's `last_run_id` is still `None` — so compaction events
/// must route by the session the host stamps on them.
test "compaction events route by session when no run id matches" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    last_run_id: None,
  })
  let (_, started) = update_dev(
    dispatch,
    Engine(None, CompactionStarted, session=Some("desktop-test")),
    model,
  )
  assert_true(started.active().compaction is Compacting)
  let (_, next) = update_dev(
    dispatch,
    Engine(
      None,
      CompactionFinished("earlier turns compacted"),
      session=Some("desktop-test"),
    ),
    started,
  )
  inspect(next.active().overlay.length(), content="0")
  assert_true(next.active().compaction is NotCompacting)
}

///|
/// The host synthesizes compaction_failed when the engine dies with a
/// compaction still queued behind the dead turn; that terminal event must
/// settle the queued notice like any other compaction failure.
test "compaction_failed settles a still-queued compaction" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Queued,
    last_run_id: Some("r7"),
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), CompactionFailed("engine exited"), session=None),
    model,
  )
  assert_true(next.active().compaction is NotCompacting)
  inspect(next.active().overlay.length(), content="1")
}

///|
/// A rejected compact request (no engine, host error) never produces
/// compaction events, so the rejection itself clears the queued notice and
/// lands the error in the transcript.
test "CompactRejected clears the queued notice and reports the error" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Queued,
  })
  let (_, next) = update_dev(
    dispatch,
    CompactRejected(session="desktop-test", message="no engine"),
    model,
  )
  assert_true(next.active().compaction is NotCompacting)
  inspect(next.active().overlay.length(), content="1")
}
