///|
let default_max_steps : Int = 1000

///|
/// Mid-turn user input riding the shared runtime event bus. Queued by
/// `steer` and folded into the conversation by the agent loop at its next
/// step boundary.
extenum @agent_runtime.AgentEvent += {
  SteerInput(String)
}

///|
/// Queue `text` as steering input for the turn running on `runtime`.
///
/// Steering lands at the next step boundary — after the in-flight model call
/// and its tool batch complete, where the loop already folds in runtime
/// updates — so completed work is never thrown away. The text is appended to
/// the session as a user message and a `steer_applied` event is emitted when
/// it takes effect. Steering an idle runtime is harmless: the input waits on
/// the bus for the next turn.
pub fn steer(runtime : @agent_runtime.AgentRuntime, text : String) -> Unit {
  runtime.emit_event(SteerInput(text))
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
/// turns (serve mode): a shared `runtime` preserves stateful tools — a
/// `moon_check` watcher started in one turn keeps reporting in the next —
/// and is also the bus `steer` feeds mid-turn input through. `scope` bounds
/// background work the turn's tools spawn, so it must outlive the turn.
/// One-shot callers should prefer `run_turn`/`run_turn_with_append`, which
/// own both for the duration of a single turn.
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
    let tools = tool_definitions(runtime, scope) catch {
      error => {
        let next = append_item(
          session,
          Terminal(Failed("agent setup failed: \{error}")),
        )
        @xlog.error() <? { "event": "agent_setup_failed", "error": "\{error}" }
        return next
      }
    }
    let messages = session.chat_messages()
    for step in 0..<max_steps {
      let drained = runtime.drain_events()
      // Steering first: a user's mid-turn redirection should precede the
      // runtime chatter the model reads alongside it.
      for event in drained {
        if event is SteerInput(text) && !text.trim().is_empty() {
          @xlog.info() <? { "event": "steer_applied", "content": text }
          session = append_item(session, User(UserMessage(text)))
          messages.push(ChatMessage(User, content=text))
        }
      }
      if runtime_update_message(drained) is Some(update) {
        @xlog.info() <? { "event": "runtime_update", "content": update }
        session = append_item(session, Runtime(RuntimeNotice(update)))
        messages.push(ChatMessage(User, content=update))
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
      if response.tool_calls.length() == 0 {
        let next = append_item(session, Terminal(Finished(response.content)))
        @xlog.info() <?
          { "event": "agent_finished", "answer": response.content }
        return next
      }
      let reasoning_content = match response.reasoning_content {
        "" => None
        content => Some(content)
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
      for native_call in response.tool_calls {
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
            let next = append_item(session, Terminal(Finished(answer)))
            @xlog.info() <? { "event": "agent_finished", "answer": answer }
            return next
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
