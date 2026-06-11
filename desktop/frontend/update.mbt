///|
fn non_empty_or(value : String, fallback : String) -> String {
  if value.trim().is_empty() {
    fallback
  } else {
    value
  }
}

///|
fn parse_runtime_update(content : String) -> RuntimeUpdateView {
  let mut status = ""
  let diagnostics : Array[String] = []
  for raw in content.split("\n") {
    let line = raw.to_owned()
    if line == "[moon_check update]" {
      continue
    }
    let is_metadata = if line.split_once("=") is Some((key, value)) {
      let key = key.to_owned()
      if runtime_metadata_keys.contains(key) {
        if key == "status" {
          status = value.to_owned()
        }
        true
      } else {
        false
      }
    } else {
      false
    }
    if !is_metadata {
      diagnostics.push(line)
    }
  }
  { status, diagnostics }
}

///|
fn runtime_update_title(update : RuntimeUpdateView) -> String {
  if update.status.is_empty() {
    "moon_check"
  } else {
    "moon_check \{update.status}"
  }
}

///|
fn should_append_answer(model : Model, answer : String) -> Bool {
  if answer.trim().is_empty() {
    false
  } else {
    match model.last_assistant_content() {
      Some(existing) => existing != answer
      None => true
    }
  }
}

///|
fn update(
  dispatch : @cmd.Dispatch[Msg],
  msg : Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match msg {
    Init =>
      (
        @cmd.batch([
          install_bridge(dispatch),
          load_saved_api_key(dispatch),
          install_clipboard_paste_bridge(),
          rotate_session(dispatch),
        ]),
        model,
      )
    BridgeReady => {
      let has_key = !model.api_key.trim().is_empty()
      (
        fetch_sessions(dispatch),
        {
          ..model,
          bridge_ready: true,
          setup_open: if has_key {
            model.setup_open
          } else {
            true
          },
          status: if has_key {
            Ready
          } else {
            SetupRequired
          },
        },
      )
    }
    BridgeUnavailable(message) =>
      (
        @cmd.none,
        { ..model, bridge_ready: false, status: Unavailable(message) },
      )
    ApiKeyLoaded(value) => {
      let api_key = value.trim().to_owned()
      let has_key = !api_key.is_empty()
      (
        @cmd.none,
        {
          ..model,
          api_key,
          setup_open: !has_key,
          setup_api_key: "",
          status: if model.bridge_ready {
            if has_key {
              Ready
            } else {
              SetupRequired
            }
          } else {
            model.status
          },
        },
      )
    }
    TaskChanged(value) => (@cmd.none, { ..model, task: value })
    ModelChanged(value) => (@cmd.none, { ..model, selected_model: value })
    MaxStepsChanged(value) => (@cmd.none, { ..model, max_steps: value })
    SetupApiKeyChanged(value) => (@cmd.none, { ..model, setup_api_key: value })
    OpenSetup => (@cmd.none, { ..model, setup_open: true, setup_api_key: "" })
    CloseSetup =>
      if model.api_key.trim().is_empty() {
        (@cmd.none, { ..model, setup_open: true, status: ApiKeyRequired })
      } else {
        (@cmd.none, { ..model, setup_open: false, setup_api_key: "" })
      }
    SaveApiKey => {
      let api_key = model.setup_api_key.trim().to_owned()
      if api_key.is_empty() {
        (@cmd.none, { ..model, status: ApiKeyRequired })
      } else {
        (
          save_api_key(api_key),
          {
            ..model,
            api_key,
            setup_api_key: "",
            setup_open: false,
            status: if model.bridge_ready {
              Ready
            } else {
              WaitingBridge
            },
          },
        )
      }
    }
    Send => {
      let task = model.task.trim().to_owned()
      if task.is_empty() ||
        !model.bridge_ready ||
        model.api_key.trim().is_empty() {
        (@cmd.none, model)
      } else if model.running {
        // Submitting while a turn runs steers it: the text is folded into
        // the running turn at its next step boundary and echoed back as a
        // `steer_applied` event. A turn being cancelled cannot be steered —
        // the steer could outlive the dying turn in the engine's queue and
        // contaminate a later prompt — so the text stays in the composer.
        match model.active_run_id {
          Some(run_id) if !(model.status is Cancelling) => {
            let pending_steers = model.pending_steers.copy()
            pending_steers.push(task)
            (
              steer_openseek(dispatch, task, run_id),
              { ..model, pending_steers, task: "" },
            )
          }
          _ => (@cmd.none, model)
        }
      } else {
        let next = model.append_item(User, task)
        let next = {
          ..next,
          running: true,
          active_run_id: None,
          status: Starting,
          usage_tokens: 0,
          task: "",
        }
        (
          @cmd.batch([
            start_openseek(
              dispatch,
              task,
              model.selected_model,
              model.max_steps,
              model.api_key,
              model.session_id,
            ),
            scroll_transcript_after_render(),
          ]),
          next,
        )
      }
    }
    SteerUndelivered(text) =>
      // The steer never reached the engine, so no `steer_applied` /
      // `steer_dropped` event will settle it — report the loss here instead.
      (
        scroll_transcript_after_render(),
        model
        .settle_pending_steer(text)
        .append_item(Assistant(true), steer_dropped_notice(text)),
      )
    Stop =>
      match model.active_run_id {
        Some(run_id) =>
          (cancel_openseek(dispatch, run_id), { ..model, status: Cancelling })
        None => (@cmd.none, model)
      }
    NewChat =>
      // Rotating the session id starts a fresh engine conversation; the
      // transcript and usage belong to the old one, so they reset with it.
      if model.running {
        (@cmd.none, model)
      } else {
        (
          rotate_session(dispatch),
          {
            ..model.clear_streams(),
            messages: [],
            pending_steers: [],
            usage_tokens: 0,
            watcher_status: "",
            cwd: "",
            active_run_id: None,
            status: if model.bridge_ready && !model.api_key.trim().is_empty() {
              Ready
            } else {
              model.status
            },
          },
        )
      }
    SessionRotated(session_id) => (@cmd.none, { ..model, session_id, })
    SessionsLoaded(items) =>
      (@cmd.none, { ..model, sessions: items, sessions_error: "" })
    SessionsFailed(message) => (@cmd.none, { ..model, sessions_error: message })
    OpenSession(session_id) =>
      // Switching conversations mid-run would tear the transcript away from
      // the engine output still streaming into it.
      if model.running ||
        session_id.is_empty() ||
        session_id == model.session_id {
        (@cmd.none, model)
      } else {
        (open_session(dispatch, session_id), model)
      }
    SessionLoaded(session_id, items) =>
      // A run that started while the load was in flight wins; dropping the
      // reply keeps the live conversation intact.
      if model.running {
        (@cmd.none, model)
      } else {
        (
          scroll_transcript_after_render(),
          {
            ..model.clear_streams(),
            session_id,
            messages: items,
            pending_steers: [],
            usage_tokens: 0,
            watcher_status: "",
            cwd: "",
            active_run_id: None,
            status: if model.bridge_ready && !model.api_key.trim().is_empty() {
              Ready
            } else {
              model.status
            },
          },
        )
      }
    Started(run_id, _task, _engine, selected_model, max_steps, cwd) =>
      (
        @cmd.none,
        {
          ..model,
          running: true,
          active_run_id: Some(run_id),
          status: Running,
          selected_model,
          max_steps: max_steps.to_string(),
          cwd,
        },
      )
    Engine(run_id, event) =>
      if !model.matches_run(run_id) {
        (@cmd.none, model)
      } else {
        match event {
          AgentStep(detail) =>
            (@cmd.none, { ..model.clear_streams(), status: Step(detail) })
          AssistantDelta(content) =>
            if content.is_empty() {
              (@cmd.none, model)
            } else {
              (
                scroll_transcript_after_render(),
                {
                  ..model,
                  streaming_response: model.streaming_response + content,
                },
              )
            }
          ReasoningDelta(content) =>
            if content.is_empty() {
              (@cmd.none, model)
            } else {
              (
                scroll_transcript_after_render(),
                {
                  ..model,
                  streaming_reasoning: model.streaming_reasoning + content,
                },
              )
            }
          // The turn's full reasoning, emitted once its streaming ends and
          // before the assistant message commits — so the transcript reads
          // thought → answer.
          ReasoningMessage(content) => {
            let next = { ..model, streaming_reasoning: "" }
            let content = content.trim().to_owned()
            if content.is_empty() {
              (@cmd.none, next)
            } else {
              (
                scroll_transcript_after_render(),
                next.append_item(Reasoning, content),
              )
            }
          }
          AssistantMessage(content) => {
            let model = model.clear_streams()
            let content = content.trim().to_owned()
            if content.is_empty() {
              (@cmd.none, model)
            } else {
              (
                scroll_transcript_after_render(),
                model.append_item(Assistant(false), content),
              )
            }
          }
          RuntimeUpdate(content) => {
            let update = parse_runtime_update(content)
            let next = { ..model, watcher_status: update.status }
            if !update.status.is_empty() || update.diagnostics.length() > 0 {
              (
                scroll_transcript_after_render(),
                next.append_item(
                  Tool(runtime_update_title(update), false),
                  update.diagnostics.join("\n"),
                ),
              )
            } else {
              (@cmd.none, next)
            }
          }
          Usage(prompt_tokens~, completion_tokens~) =>
            (
              @cmd.none,
              { ..model, usage_tokens: prompt_tokens + completion_tokens },
            )
          ToolResult(tool_name~, is_error~, content~) =>
            (
              scroll_transcript_after_render(),
              model.append_item(
                Tool(non_empty_or(tool_name, "tool"), is_error),
                content,
              ),
            )
          ToolCallDecodeError(tool_name~, reason~) => {
            let content = non_empty_or(reason, "tool call decode error")
            (
              scroll_transcript_after_render(),
              model.append_item(
                Tool(non_empty_or(tool_name, "tool"), true),
                content,
              ),
            )
          }
          AgentFinished(answer) => {
            let model = model.clear_streams()
            let answer = answer.trim().to_owned()
            if should_append_answer(model, answer) {
              (
                scroll_transcript_after_render(),
                model.append_item(Assistant(false), answer),
              )
            } else {
              (@cmd.none, model)
            }
          }
          AgentAborted(reason) => {
            let content = if reason.trim().is_empty() {
              "aborted"
            } else {
              "aborted: " + reason
            }
            (
              scroll_transcript_after_render(),
              model.clear_streams().append_item(Assistant(true), content),
            )
          }
          MaxStepsExhausted =>
            (
              scroll_transcript_after_render(),
              model
              .clear_streams()
              .append_item(Assistant(true), "max steps exhausted"),
            )
          AgentSetupFailed(reason) => {
            let content = if reason.trim().is_empty() {
              "setup failed"
            } else {
              "setup failed: " + reason
            }
            (
              scroll_transcript_after_render(),
              model.clear_streams().append_item(Assistant(true), content),
            )
          }
          // The steer took effect at a step boundary: it is part of the
          // conversation now, so echo it as a user message.
          SteerApplied(content) =>
            (
              scroll_transcript_after_render(),
              model.settle_pending_steer(content).append_item(User, content),
            )
          // The steer raced the turn's end through the pipes and was
          // rejected; the text must not vanish silently.
          SteerDropped(content) =>
            (
              scroll_transcript_after_render(),
              model
              .settle_pending_steer(content)
              .append_item(Assistant(true), steer_dropped_notice(content)),
            )
        }
      }
    Failed(message) =>
      (
        @cmd.batch([scroll_transcript_after_render(), fetch_sessions(dispatch)]),
        {
          ..model
          .clear_streams()
          .sweep_pending_steers()
          .append_item(Assistant(true), message),
          running: false,
          active_run_id: None,
          status: Failed,
        },
      )
    Error(run_id, message, _exit_code, diagnostics) =>
      if !model.matches_error_run(run_id) {
        (@cmd.none, model)
      } else {
        let content = if diagnostics.trim().is_empty() {
          message
        } else {
          message + "\n\n" + diagnostics
        }
        (
          scroll_transcript_after_render(),
          { ..model.append_item(Assistant(true), content), status: Errored },
        )
      }
    Finished(run_id, status, answer, _exit_code) =>
      if !model.matches_run(run_id) {
        (@cmd.none, model)
      } else {
        // In the normal path the engine settled every steer before this
        // terminal event; sweeping here only matters when the run died with
        // steers still in flight.
        let base = {
          ..model.clear_streams().sweep_pending_steers(),
          running: false,
          active_run_id: None,
          status: Finished(status),
        }
        let answer = answer.trim().to_owned()
        // The finished run just appended to the durable store, so the
        // sidebar list (and this conversation's title) may have changed.
        if should_append_answer(model, answer) {
          (
            @cmd.batch([
              scroll_transcript_after_render(),
              fetch_sessions(dispatch),
            ]),
            base.append_item(Assistant(false), answer),
          )
        } else {
          (fetch_sessions(dispatch), base)
        }
      }
  }
}
