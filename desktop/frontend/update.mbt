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
        @cmd.none,
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
    CwdChanged(value) => (@cmd.none, { ..model, cwd: value })
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
        model.running ||
        !model.bridge_ready ||
        model.api_key.trim().is_empty() {
        (@cmd.none, model)
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
              model.cwd,
              model.api_key,
              model.session_id,
            ),
            scroll_transcript_after_render(),
          ]),
          next,
        )
      }
    }
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
            usage_tokens: 0,
            watcher_status: "",
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
        }
      }
    Failed(message) =>
      (
        scroll_transcript_after_render(),
        {
          ..model.clear_streams().append_item(Assistant(true), message),
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
        let base = {
          ..model.clear_streams(),
          running: false,
          active_run_id: None,
          status: Finished(status),
        }
        let answer = answer.trim().to_owned()
        if should_append_answer(model, answer) {
          (
            scroll_transcript_after_render(),
            base.append_item(Assistant(false), answer),
          )
        } else {
          (@cmd.none, base)
        }
      }
  }
}
