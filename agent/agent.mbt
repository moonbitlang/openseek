///|
let default_max_steps : Int = 1000

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
///
/// Progress is reported through `on_event`, which defaults to printing events to
/// stdout. Non-interactive callers can ignore it; hosts such as the TUI pass
/// their own handler to drive a live display.
pub async fn run(
  api_key : String,
  model : @deepseek.Model,
  task : String,
  max_steps? : Int = default_max_steps,
  system_prompt_text? : String = default_system_prompt_for_model(model),
  on_event? : async (AgentEvent) -> Unit = stdout_event_handler,
) -> Unit {
  let client = @client.Client(
    api_key~,
    model~,
    thinking=Some(Enabled),
    reasoning_effort=Some(Max),
  )
  let tools = tool_definitions() catch {
    error => {
      on_event(AgentError("agent setup failed: \{error}"))
      return
    }
  }
  let messages : Array[@deepseek.ChatMessage] = [
    ChatMessage(System, content=system_prompt_text),
    ChatMessage(User, content=task),
  ]
  for step in 0..<max_steps {
    on_event(StepStarted(step + 1))
    let response = client.chat(messages, tools=tools.function_tools()) catch {
      error => {
        on_event(AgentError("chat failed: \{error}"))
        return
      }
    }
    if response.reasoning_content != "" {
      on_event(ReasoningMessage(response.reasoning_content))
    }
    if response.content != "" {
      on_event(AssistantMessage(response.content))
    }
    on_event(Usage(response.usage))
    if response.tool_calls.length() == 0 {
      on_event(Finished(response.content))
      return
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
    for native_call in response.tool_calls {
      on_event(
        ToolCallStarted({
          id: native_call.id,
          name: native_call.name,
          arguments: native_call.arguments,
        }),
      )
      let tool_call = @agent_tool.AgentToolCall(native_call) catch {
        error => {
          let content = "error: \{error}"
          on_event(
            ToolCallFinished({
              id: native_call.id,
              name: native_call.name,
              content,
              is_error: true,
            }),
          )
          messages.push(ChatMessage(Tool(native_call.id), content~))
          continue
        }
      }
      let result = @agent_tool.execute_tool_call(tool_call, tools)
      let output = match result {
        Control(Finish(answer)) => {
          on_event(Finished(answer))
          return
        }
        Control(Abort(reason)) => {
          on_event(Aborted(reason))
          return
        }
        Respond(output) => output
      }
      on_event(
        ToolCallFinished({
          id: native_call.id,
          name: native_call.name,
          content: output.content,
          is_error: output.is_error,
        }),
      )
      messages.push(ChatMessage(Tool(native_call.id), content=output.content))
    }
  }
  on_event(MaxStepsExhausted)
}

///|
let log : @logger.Logger = @logger.stdout(min_level=INFO)

///|
async fn stdout_event_handler(event : AgentEvent) -> Unit {
  match event {
    StepStarted(step) => log <+ "--- step \{step} ---\n"
    AssistantMessage(content) => log <+ "agent: \{content}\n"
    ReasoningMessage(_) => ()
    Usage(usage) => print_usage(usage)
    ToolCallStarted(_) => ()
    ToolCallFinished(result) =>
      if result.name != "finish" {
        let label = if result.is_error { "tool error" } else { "tool" }
        log <+ "\{label}: \{result.content}\n"
      }
    Finished(answer) => {
      log <+ "=== finished ===\n"
      log <+ "\{answer}\n"
    }
    Aborted(reason) => {
      let warn_log = log.warn()
      warn_log <+ "=== aborted ===\n"
      warn_log <+ "\{reason}\n"
    }
    MaxStepsExhausted => {
      let warn_log = log.warn()
      warn_log <+ "=== max steps exhausted ===\n"
    }
    AgentError(message) => {
      let error_log = log.error()
      error_log <+ "\{message}\n"
    }
  }
}

///|
async fn print_usage(usage : @deepseek.Usage) -> Unit {
  log <+
    "usage: prompt=\{usage.prompt_tokens} completion=\{usage.completion_tokens} cache_hit=\{usage.prompt_cache_hit_tokens} cache_miss=\{usage.prompt_cache_miss_tokens}\n"
}
