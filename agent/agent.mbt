///|
let default_max_steps : Int = 1000

///|
/// Queue `text` as steering input for the turn running on `runtime`.
///
/// Steering lands at the next step boundary — after the in-flight model call
/// and its tool batch complete, where the loop already folds in runtime
/// updates — so completed work is never thrown away. User input also wins
/// over model-initiated completion: a steer that arrives while the final
/// call is in flight keeps the turn alive (the would-be answer becomes an
/// ordinary assistant message, or the finish call's batch is closed out)
/// and the conversation continues with the steer. Only error terminals
/// (abort, failure, exhausted steps) still end the turn; a steer queued
/// then applies to the next one. The text is appended to the session as a
/// user message and a `steer_applied` event is emitted when it takes
/// effect. The channel is lossless (unlike the runtime event bus, which
/// discards under flood), so a steer can never be pushed out by noisy
/// watcher updates.
pub fn steer(runtime : @agent_runtime.AgentRuntime, text : String) -> Unit {
  runtime.queue_steer(text)
}

///|
/// Build the agent's standard tool registry bound to `runtime` and `scope`.
///
/// Stateful tools live in the registry value itself: `moon_check` keeps its
/// watcher records in the closure this builds, not in `AgentRuntime`. A
/// serve-mode caller that wants watchers to survive from one turn to the
/// next must therefore build the registry once and pass it to every
/// `run_turn_in_scope` call — rebuilding it each turn would orphan the old
/// watchers and start duplicates.
pub fn[X] build_tools(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
) -> @agent_tool.Tools raise {
  tool_definitions(runtime, scope)
}

///|
/// Returns the base built-in system prompt.
pub fn default_system_prompt() -> String {
  @prompt.system_prompt_for_model(V4Pro)
}

///|
/// Returns the default system prompt for a DeepSeek model.
pub fn default_system_prompt_for_model(model : @deepseek.Model) -> String {
  @prompt.system_prompt_for_model(model)
}

///|
/// Runs the OpenSeek agent loop for a single task.
pub async fn run(
  api_key : String,
  model : @deepseek.Model,
  task : String,
  max_steps? : Int = default_max_steps,
  system_prompt_text? : String = default_system_prompt_for_model(model),
  thinking? : @deepseek.ThinkingMode = Enabled,
  reasoning_effort? : @deepseek.ReasoningEffort = Max,
  api_url? : String,
) -> Unit {
  let session = @agent_session.Session(
    SessionId("one-shot"),
    system_prompt=system_prompt_text,
  )
  ignore(
    run_turn(
      api_key,
      model,
      session,
      task,
      max_steps~,
      thinking~,
      reasoning_effort~,
      api_url?,
    ),
  )
}

///|
/// Runs one user turn against an in-memory session and returns the updated
/// session. Callers that need durable persistence should use
/// `run_turn_with_append`.
pub async fn run_turn(
  api_key : String,
  model : @deepseek.Model,
  session : @agent_session.Session,
  task : String,
  max_steps? : Int = default_max_steps,
  thinking? : @deepseek.ThinkingMode = Enabled,
  reasoning_effort? : @deepseek.ReasoningEffort = Max,
  api_url? : String,
) -> @agent_session.Session {
  run_turn_with_append(
    api_key,
    model,
    session,
    task,
    append_item=(session, item) => session.append(item),
    max_steps~,
    thinking~,
    reasoning_effort~,
    api_url?,
  )
}

///|
/// Runs one user turn and calls `append_item` for every session event as soon as
/// it is committed. This lets a filesystem-backed caller preserve progress even
/// if the engine process exits later in the turn.
pub async fn run_turn_with_append(
  api_key : String,
  model : @deepseek.Model,
  session : @agent_session.Session,
  task : String,
  append_item~ : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  max_steps? : Int = default_max_steps,
  thinking? : @deepseek.ThinkingMode = Enabled,
  reasoning_effort? : @deepseek.ReasoningEffort = Max,
  api_url? : String,
) -> @agent_session.Session {
  @async.with_task_group() <| group => {
    run_turn_in_scope(
      AgentRuntime(),
      AgentTaskScope(group),
      api_key,
      model,
      session,
      task,
      append_item~,
      max_steps~,
      thinking~,
      reasoning_effort~,
      api_url?,
    )
  }
}

///|
async test "run_turn_with_append closes failed persisted turns" {
  let initial = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let mut calls = 0
  let mut persisted = initial
  let _ = run_turn_with_append(
    "unused",
    V4Pro,
    initial,
    "hello",
    append_item=(session, item) => {
      calls = calls + 1
      if calls == 2 {
        fail("persist terminal failed")
      }
      let next = session.append(item)
      persisted = next
      next
    },
    max_steps=0,
  ) catch {
    error => {
      assert_true("\{error}".contains("persist terminal failed"))
      assert_eq(calls, 3)
      let events = persisted.events()
      assert_eq(events.length(), 2)
      assert_true(events[0].item() is User(_))
      guard events[1].item() is Terminal(Failed(message)) else {
        fail("expected failed terminal")
      }
      assert_true(message.contains("persist terminal failed"))
      return
    }
  }
  fail("expected failed append to be re-raised")
}

///|
/// Runs one user turn inside a caller-owned runtime and task scope.
///
/// This is the building block for callers that keep an engine alive across
/// turns (serve mode): the shared `runtime` carries steering input and
/// runtime updates across the turn boundary, and a `tools` registry built
/// once with `build_tools` preserves stateful tools — a `moon_check` watcher
/// started in one turn keeps reporting in the next. When `tools` is omitted
/// a fresh registry is built for this turn only. `scope` bounds background
/// work the turn's tools spawn, so it must outlive every turn that may have
/// spawned some. One-shot callers should prefer
/// `run_turn`/`run_turn_with_append`, which own everything for the duration
/// of a single turn.
pub async fn[X] run_turn_in_scope(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
  api_key : String,
  model : @deepseek.Model,
  session : @agent_session.Session,
  task : String,
  append_item~ : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  max_steps? : Int = default_max_steps,
  thinking? : @deepseek.ThinkingMode = Enabled,
  reasoning_effort? : @deepseek.ReasoningEffort = Max,
  api_url? : String,
  tools? : @agent_tool.Tools,
) -> @agent_session.Session {
  let client = @client.Client(
    api_key~,
    model~,
    thinking=Some(thinking),
    // The API rejects a request that sets reasoning_effort while thinking is
    // disabled — effort only means something during thinking — so the effort
    // rides along only when thinking is on.
    reasoning_effort=match thinking {
      Enabled => Some(reasoning_effort)
      Disabled => None
    },
    api_url?,
  )
  let mut session = append_item(session, User(UserMessage(task)))
  try {
    let tools = match tools {
      Some(tools) => tools
      None =>
        tool_definitions(runtime, scope) catch {
          error => {
            let next = append_item(
              session,
              Terminal(Failed("agent setup failed: \{error}")),
            )
            @xlog.error() <?
              { "event": "agent_setup_failed", "error": "\{error}" }
            return next
          }
        }
    }
    let messages = session.chat_messages()
    let mut last_runtime_fingerprint = ""
    steps~: for step in 0..<max_steps {
      // Steering first: a user's mid-turn redirection should precede the
      // runtime chatter the model reads alongside it.
      session = apply_steer_texts(
        pending_steers(runtime),
        session,
        messages,
        append_item~,
      )
      if runtime_update_message(runtime.drain_events()) is Some(update) {
        // Watcher updates whose substance matches the previous notice are
        // skipped: the model already has this state, and re-appending it
        // only grows the context (volatile counters aside, most updates
        // from a quiet watcher are identical).
        let fingerprint = @moon_check.update_fingerprint(update)
        if fingerprint != last_runtime_fingerprint {
          last_runtime_fingerprint = fingerprint
          @xlog.info() <? { "event": "runtime_update", "content": update }
          session = append_item(session, Runtime(RuntimeNotice(update)))
          messages.push(ChatMessage(User, content=update))
        }
      }
      @xlog.info() <? { "event": "agent_step", "step": step + 1 }
      let response = client.chat_stream(
        messages,
        tools=tools.function_tools(),
        on_content_delta=delta => {
          if delta != "" {
            @xlog.info() <? { "event": "assistant_delta", "content": delta }
          }
        },
        on_reasoning_delta=delta => {
          if delta != "" {
            @xlog.info() <? { "event": "reasoning_delta", "content": delta }
          }
        },
      )
      // Reasoning first, so a consumer appending events in order shows the
      // thinking above the answer it led to.
      if response.reasoning_content != "" {
        @xlog.info() <?
          {
            "event": "reasoning_message",
            "content": response.reasoning_content,
          }
      }
      if response.content != "" {
        @xlog.info() <?
          { "event": "assistant_message", "content": response.content }
      }
      print_usage(response.usage)
      let reasoning_content = match response.reasoning_content {
        "" => None
        content => Some(content)
      }
      if response.tool_calls.length() == 0 {
        let pending = pending_steers(runtime)
        if pending.length() == 0 {
          let next = append_item(session, Terminal(Finished(response.content)))
          @xlog.info() <?
            { "event": "agent_finished", "answer": response.content }
          return next
        }
        // The model considers itself done, but the user redirected while the
        // final call was in flight: user input wins over model-initiated
        // completion. The would-be answer stays as an ordinary assistant
        // message and the turn continues with the steers folded in.
        messages.push(
          ChatMessage(Assistant, content=response.content, reasoning_content?),
        )
        session = append_item(
          session,
          Assistant(AssistantMessage(response.content, reasoning_content?)),
        )
        session = apply_steer_texts(pending, session, messages, append_item~)
        continue steps~
      }
      let assistant_message : @deepseek.ChatMessage = ChatMessage(
        Assistant,
        content=response.content,
        tool_calls=response.tool_calls,
        reasoning_content?,
      )
      messages.push(assistant_message)
      session = append_item(
        session,
        Assistant(
          AssistantMessage(
            response.content,
            tool_calls=response.tool_calls,
            reasoning_content?,
          ),
        ),
      )
      for call_index, native_call in response.tool_calls {
        let tool_call = @agent_tool.AgentToolCall(native_call) catch {
          error => {
            @xlog.error() <?
              {
                "event": "tool_call_decode_error",
                "tool_call_id": native_call.id,
                "tool_name": native_call.name,
                "error": "\{error}",
              }
            messages.push(
              ChatMessage(Tool(native_call.id), content="error: \{error}"),
            )
            session = append_item(
              session,
              Tool(
                ToolResult(
                  tool_call_id=native_call.id,
                  tool_name=native_call.name,
                  content="error: \{error}",
                  is_error=true,
                ),
              ),
            )
            continue
          }
        }
        let result = @agent_tool.execute_tool_call(tool_call, tools)
        let output = match result {
          Control(Finish(answer)) => {
            session = append_item(
              session,
              Tool(
                ToolResult(
                  tool_call_id=native_call.id,
                  tool_name=tool_call.name,
                  content="finished: \{answer}",
                ),
              ),
            )
            let pending = pending_steers(runtime)
            if pending.length() == 0 {
              let next = append_item(session, Terminal(Finished(answer)))
              @xlog.info() <? { "event": "agent_finished", "answer": answer }
              return next
            }
            // User input wins over the finish tool as well. Continuing the
            // turn must keep the conversation API-valid: every call in the
            // assistant's batch needs a result message, so the finish call's
            // result and skipped notes for the unexecuted remainder are
            // pushed before the steers.
            messages.push(
              ChatMessage(Tool(native_call.id), content="finished: \{answer}"),
            )
            for rest_index in (call_index + 1)..<response.tool_calls.length() {
              let skipped = response.tool_calls[rest_index]
              let note = "skipped: the user steered the turn before this call ran"
              @xlog.info() <?
                {
                  "event": "tool_result",
                  "tool_call_id": skipped.id,
                  "tool_name": skipped.name,
                  "is_error": true,
                  "content": note,
                }
              messages.push(ChatMessage(Tool(skipped.id), content=note))
              session = append_item(
                session,
                Tool(
                  ToolResult(
                    tool_call_id=skipped.id,
                    tool_name=skipped.name,
                    content=note,
                    is_error=true,
                  ),
                ),
              )
            }
            session = apply_steer_texts(
              pending,
              session,
              messages,
              append_item~,
            )
            continue steps~
          }
          Control(Abort(reason)) => {
            session = append_item(
              session,
              Tool(
                ToolResult(
                  tool_call_id=native_call.id,
                  tool_name=tool_call.name,
                  content="aborted: \{reason}",
                  is_error=true,
                ),
              ),
            )
            let next = append_item(session, Terminal(Aborted(reason)))
            @xlog.warn() <? { "event": "agent_aborted", "reason": reason }
            return next
          }
          Respond(output) => output
        }
        @xlog.info() <?
          {
            "event": "tool_result",
            "tool_call_id": native_call.id,
            "tool_name": tool_call.name,
            "is_error": output.is_error,
            "content": output.content,
          }
        messages.push(ChatMessage(Tool(native_call.id), content=output.content))
        session = append_item(
          session,
          Tool(
            ToolResult(
              tool_call_id=native_call.id,
              tool_name=tool_call.name,
              content=output.content,
              is_error=output.is_error,
            ),
          ),
        )
      }
    }
    let next = append_item(session, Terminal(Failed("max steps exhausted")))
    @xlog.warn() <? { "event": "max_steps_exhausted" }
    next
  } catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) => {
      ignore(
        append_item(session, Terminal(Interrupted("cancelled"))) catch {
          _ => session
        },
      )
      raise error
    }
    error => {
      ignore(
        append_item(session, Terminal(Failed("agent failed: \{error}"))) catch {
          _ => session
        },
      )
      raise error
    }
  }
}

///|
fn runtime_update_message(events : Array[@agent_runtime.AgentEvent]) -> String? {
  @moon_check.runtime_update_text(events)
}

///|
/// Queued steering input worth applying: drained losslessly, blanks dropped.
fn pending_steers(runtime : @agent_runtime.AgentRuntime) -> Array[String] {
  [
    for text in runtime.drain_steers() if !text.trim().is_empty() => text
  ]
}

///|
/// Fold steering texts into the conversation: each becomes a durable user
/// message, a model-visible chat message, and a `steer_applied` event.
async fn apply_steer_texts(
  texts : Array[String],
  session : @agent_session.Session,
  messages : Array[@deepseek.ChatMessage],
  append_item~ : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
) -> @agent_session.Session {
  let mut current = session
  for text in texts {
    @xlog.info() <? { "event": "steer_applied", "content": text }
    current = append_item(current, User(UserMessage(text)))
    messages.push(ChatMessage(User, content=text))
  }
  current
}

///|
fn print_usage(usage : @deepseek.Usage) -> Unit {
  @xlog.info() <?
    {
      "event": "usage",
      "prompt_tokens": usage.prompt_tokens,
      "completion_tokens": usage.completion_tokens,
      "cache_hit_tokens": usage.prompt_cache_hit_tokens,
      "cache_miss_tokens": usage.prompt_cache_miss_tokens,
    }
}
