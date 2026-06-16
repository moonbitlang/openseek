///|
/// Agent-local executable form of a native `@deepseek.ToolCall`.
///
/// `@deepseek.ToolCall` is the protocol value returned by the API: it keeps the
/// DeepSeek `id` and raw JSON argument string so the assistant tool-call message
/// and later `Tool(id)` result message can preserve the wire format. Once the
/// agent is ready to dispatch a local tool, `AgentToolCall` keeps only the tool
/// name and parsed `Json` arguments. The original id stays on the native call
/// used by the conversation loop when it appends the tool result message.
pub struct AgentToolCall {
  /// Local tool name selected by DeepSeek, such as `shell`, `read`, `write`, or
  /// `finish`.
  name : String
  /// Parsed JSON arguments for the selected local tool. Dispatchers validate the
  /// required fields for each tool before execution.
  arguments : Json
}

///|
/// Parses a `@deepseek.ToolCall` into an `AgentToolCall`. Raises when the raw
/// arguments string is not valid JSON.
pub fn AgentToolCall::AgentToolCall(
  call : @deepseek.ToolCall,
) -> AgentToolCall raise {
  let arguments = @json.parse(call.arguments) catch {
    _ => fail("\{call.name} arguments are not valid JSON")
  }
  { name: call.name, arguments }
}

///|
/// A JSON Schema describing the arguments a tool accepts. Wraps a raw `Json`
/// value so registry entries advertise schemas explicitly.
pub(all) struct JsonSchema(Json)

///|
/// A locally registered tool: the name and JSON Schema sent to DeepSeek, plus a
/// callable executor that runs when DeepSeek requests this tool. Construct via
/// `AgentToolDefinition(name~, description~, schema~, execute~)`.
pub struct AgentToolDefinition {
  name : String
  description : String
  schema : JsonSchema
  execute : ToolExecutor
}

///|
/// Builds a tool definition with a name, JSON Schema for the arguments, and
/// the executor the framework invokes when DeepSeek requests this tool.
pub fn AgentToolDefinition::AgentToolDefinition(
  name~ : String,
  description~ : String,
  schema~ : JsonSchema,
  execute~ : ToolExecutor,
) -> AgentToolDefinition {
  { name, description, schema, execute }
}

///|
/// Wraps a tool executor as either an async or synchronous function. The
/// framework runs both uniformly through `ToolExecutor::run`.
pub(all) enum ToolExecutor {
  Async(async (Json) -> ToolAction)
  Sync((Json) -> ToolAction)
}

///|
async fn ToolExecutor::run(self : ToolExecutor, arguments : Json) -> ToolAction {
  match self {
    Async(execute) => execute(arguments)
    Sync(execute) => execute(arguments)
  }
}

///|
/// Normal output produced by a tool and sent back to the model as a
/// `Tool(id)` chat message.
pub struct ToolOutput {
  /// Text content sent to the model.
  content : String
  /// Whether the host should treat this as a tool-level error. The content is
  /// still sent to the model so it can recover or choose another action.
  is_error : Bool
} derive(Debug)

///|
/// Constructs typed tool output. `is_error` defaults to `false` for ordinary
/// successful tool responses.
pub fn ToolOutput::ToolOutput(
  content : String,
  is_error? : Bool = false,
) -> ToolOutput {
  { content, is_error }
}

///|
/// Agent-level control requested by a tool action.
pub(all) enum AgentControl {
  /// Stop the loop and surface the string as the final answer to the user.
  Finish(String)
  /// Stop the loop because execution cannot usefully continue.
  Abort(String)
} derive(Debug)

///|
/// The action returned by a tool executor. Normal tools respond to the model;
/// control tools request an agent-loop state transition.
pub(all) enum ToolAction {
  /// Append the output as a `Tool(id)` chat message and keep looping.
  Respond(ToolOutput)
  /// Request a loop-control action such as finishing the task.
  Control(AgentControl)
} derive(Debug)

///|
/// Builds a normal tool response action.
pub fn ToolAction::respond(
  content : String,
  is_error? : Bool = false,
) -> ToolAction {
  Respond(ToolOutput(content, is_error~))
}

///|
/// Builds an action that finishes the agent loop.
pub fn ToolAction::finish(answer : String) -> ToolAction {
  Control(Finish(answer))
}

///|
/// Builds an action that aborts the agent loop.
pub fn ToolAction::abort(reason : String) -> ToolAction {
  Control(Abort(reason))
}

///|
/// A name-indexed collection of `AgentToolDefinition` values. Construct via
/// `Tools(definitions)`, which raises if any two definitions share a name.
pub struct Tools {
  priv by_name : Map[String, AgentToolDefinition]
}

///|
/// Builds a `Tools` registry from the given definitions. Raises when two
/// definitions share a name — duplicates are treated as a programming bug,
/// since the model dispatches by name and a silent override would mask one
/// of the tools.
pub fn Tools::Tools(definitions : Array[AgentToolDefinition]) -> Tools raise {
  let by_name : Map[String, AgentToolDefinition] = {}
  for definition in definitions {
    if by_name.contains(definition.name) {
      fail("duplicate tool name: \{definition.name}")
    }
    by_name[definition.name] = definition
  }
  { by_name, }
}

///|
/// Returns the registered definition whose name matches `name`, or `None`.
pub fn Tools::find(self : Tools, name : String) -> AgentToolDefinition? {
  self.by_name.get(name)
}

///|
/// Encodes the registry as the DeepSeek `tools[]` payload the chat completions
/// API expects.
pub fn Tools::function_tools(self : Tools) -> Array[@deepseek.ToolDefinition] {
  [
    for definition in self.by_name.values() => {
      let JsonSchema(schema) = definition.schema
      ToolDefinition(definition.name, definition.description, schema)
    }
  ]
}

///|
/// Dispatches a parsed tool call against `tools`. Returns an error response
/// action when no definition matches.
pub async fn execute_tool_call(
  call : AgentToolCall,
  tools : Tools,
) -> ToolAction {
  match tools.find(call.name) {
    Some(tool) => tool.execute.run(call.arguments)
    None =>
      ToolAction::respond("error: unknown tool \{call.name}", is_error=true)
  }
}

///|
test "parse native tool call arguments" {
  let call = AgentToolCall(
    ToolCall(id="call_123", name="shell", arguments="{\"cmd\":\"moon check\"}"),
  )
  assert_eq(call.name, "shell")
  guard call.arguments is { "cmd": String(cmd), .. } else {
    fail("missing cmd")
  }
  assert_eq(cmd, "moon check")
}

///|
test "reject invalid native tool call arguments" {
  let _ = AgentToolCall(ToolCall(id="call_123", name="shell", arguments="{")) catch {
    error => {
      assert_true("\{error}".contains("shell arguments are not valid JSON"))
      return
    }
  }
  fail("invalid arguments parsed")
}

///|
test "ToolAction helpers build structured actions" {
  let response = ToolAction::respond("ok")
  guard response is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "ok")
  assert_false(output.is_error)
  let error_response = ToolAction::respond("bad", is_error=true)
  guard error_response is Respond(error_output) else {
    fail("expected error Respond")
  }
  assert_eq(error_output.content, "bad")
  assert_true(error_output.is_error)
  let finished = ToolAction::finish("done")
  guard finished is Control(Finish(answer)) else { fail("expected Finish") }
  assert_eq(answer, "done")
  let aborted = ToolAction::abort("stop")
  guard aborted is Control(Abort(reason)) else { fail("expected Abort") }
  assert_eq(reason, "stop")
}

///|
test "Tools::function_tools converts the registry to deepseek tool definitions" {
  let tools = Tools([
    {
      name: "echo",
      description: "Echo the input.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(_args => ToolAction::respond("ok")),
    },
  ])
  let function_tools = tools.function_tools()
  assert_eq(function_tools.length(), 1)
  assert_eq(function_tools[0].name, "echo")
}

///|
test "Tools::find returns the registered definition by name" {
  let tools = Tools([
    {
      name: "echo",
      description: "Echo.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(_args => ToolAction::respond("ok")),
    },
  ])
  guard tools.find("echo") is Some(definition) else { fail("missing echo") }
  assert_eq(definition.name, "echo")
  assert_true(tools.find("ghost") is None)
}

///|
test "Tools::Tools raises on duplicate tool names" {
  let _ = Tools([
    {
      name: "echo",
      description: "First.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(_args => ToolAction::respond("first")),
    },
    {
      name: "echo",
      description: "Second.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(_args => ToolAction::respond("second")),
    },
  ]) catch {
    error => {
      assert_true("\{error}".contains("duplicate tool name: echo"))
      return
    }
  }
  fail("expected duplicate to raise")
}

///|
async test "execute_tool_call reports unknown tool" {
  let call = AgentToolCall(ToolCall(id="call_1", name="ghost", arguments="{}"))
  let result = execute_tool_call(call, Tools([]))
  guard result is Respond(output) else {
    fail("unknown tool should produce Respond")
  }
  assert_eq(output.content, "error: unknown tool ghost")
  assert_true(output.is_error)
}

///|
async test "execute_tool_call dispatches to registered executor" {
  let tools = Tools([
    {
      name: "echo",
      description: "Echo.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(args => {
        match args {
          { "value": String(v), .. } => ToolAction::respond(v)
          _ => ToolAction::respond("no value", is_error=true)
        }
      }),
    },
  ])
  let call = AgentToolCall(
    ToolCall(id="call_1", name="echo", arguments="{\"value\":\"hi\"}"),
  )
  let result = execute_tool_call(call, tools)
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "hi")
  assert_false(output.is_error)
}

///|
async fn async_echo(args : Json) -> ToolAction {
  @async.pause()
  match args {
    { "value": String(v), .. } => ToolAction::respond(v)
    _ => ToolAction::respond("no value", is_error=true)
  }
}

///|
async test "execute_tool_call dispatches to async executor" {
  let tools = Tools([
    {
      name: "echo",
      description: "Async echo.",
      schema: JsonSchema({ "type": "object" }),
      execute: Async(async_echo),
    },
  ])
  let call = AgentToolCall(
    ToolCall(id="call_1", name="echo", arguments="{\"value\":\"async-hi\"}"),
  )
  let result = execute_tool_call(call, tools)
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "async-hi")
  assert_false(output.is_error)
}

///|
test "Tools::function_tools preserves description and schema" {
  let tools = Tools([
    {
      name: "echo",
      description: "Echo what comes in.",
      schema: JsonSchema({ "type": "object", "properties": {} }),
      execute: Sync(_args => ToolAction::respond("ok")),
    },
  ])
  let function_tools = tools.function_tools()
  assert_eq(function_tools[0].name, "echo")
  assert_eq(function_tools[0].description, "Echo what comes in.")
  let text = function_tools[0].parameters.stringify()
  assert_true(text.contains("\"type\":\"object\""))
  assert_true(text.contains("\"properties\""))
}

///|
test "Tools::Tools accepts an empty registry" {
  let tools = Tools([])
  assert_eq(tools.function_tools().length(), 0)
  assert_true(tools.find("anything") is None)
}

///|
test "Tools::function_tools yields one entry per definition" {
  let tools = Tools([
    {
      name: "first",
      description: "First.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(_args => ToolAction::respond("1")),
    },
    {
      name: "second",
      description: "Second.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(_args => ToolAction::respond("2")),
    },
    {
      name: "third",
      description: "Third.",
      schema: JsonSchema({ "type": "object" }),
      execute: Sync(_args => ToolAction::respond("3")),
    },
  ])
  let function_tools = tools.function_tools()
  assert_eq(function_tools.length(), 3)
  let names = [ for t in function_tools => t.name ]
  assert_true(names.contains("first"))
  assert_true(names.contains("second"))
  assert_true(names.contains("third"))
}
