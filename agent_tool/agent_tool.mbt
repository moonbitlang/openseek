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
  { name: call.name, arguments, }
}

///|
/// A JSON Schema describing the arguments a tool accepts. Wraps a raw `Json`
/// value so registry entries advertise schemas explicitly.
pub(all) struct JsonSchema(Json) derive(Debug)

///|
/// A locally registered tool: the name and JSON Schema sent to DeepSeek, plus a
/// callable executor that runs when DeepSeek requests this tool. Construct via
/// `AgentToolDefinition(name~, description~, schema~, execute~)`.
pub struct AgentToolDefinition {
  name : String
  description : String
  schema : JsonSchema
  execute : ToolExecutor
  /// A control tool's action is loop flow (`Control(Finish/Abort)`), not
  /// tool output — its "result" is a few bytes. The loop uses this to know,
  /// WITHOUT executing, that a call is safe to honor at the context
  /// ceiling: the built-in `finish` declares it, and a custom completion
  /// override must too or it is skip-closed like any other call there.
  ///
  /// This is a BUILT-IN-ONLY privilege: the ceiling salvage executes
  /// control-registered calls sight-unseen (decodable ones; the rest are
  /// skip-closed) precisely when context headroom is gone, so a definition
  /// built from dynamic input (an MCP server's listing, any config-supplied
  /// tool) must never set it — arbitrary work with unbounded output at the
  /// ceiling is exactly what the salvage guard exists to prevent (mcp/tools
  /// pins this with tests on BOTH construction sites: the bridge and the
  /// build_grouped re-wrap).
  control : Bool
  /// Safe to execute CONCURRENTLY with adjacent same-flagged calls in one
  /// tool batch: the tool must not mutate the workspace or loop state,
  /// must not return `Control` actions, and its result must not depend on
  /// a sibling call's result. The built-in subagent launchers (explore,
  /// the callable review) declare it — each runs an isolated child
  /// process — so a batch of independent delegations overlaps instead of
  /// serializing. Like `control`, this is a BUILT-IN-ONLY privilege:
  /// never set it on a definition built from dynamic input (MCP listings,
  /// config-supplied tools).
  priv concurrent_safe : Bool
} derive(Debug(ignore=ToolExecutor))

///|
/// Builds a tool definition with a name, JSON Schema for the arguments, and
/// the executor the framework invokes when DeepSeek requests this tool.
pub fn AgentToolDefinition::AgentToolDefinition(
  name~ : String,
  description~ : String,
  schema~ : JsonSchema,
  execute~ : ToolExecutor,
  control? : Bool = false,
  concurrent_safe? : Bool = false,
) -> AgentToolDefinition {
  { name, description, schema, execute, control, concurrent_safe, }
}

///|
/// Whether this tool declared itself a control tool (see the field doc).
pub fn AgentToolDefinition::is_control(self : AgentToolDefinition) -> Bool {
  self.control
}

///|
/// Whether this tool declared itself safe for adjacent-call concurrency
/// (see the field doc).
pub fn AgentToolDefinition::is_concurrent_safe(
  self : AgentToolDefinition,
) -> Bool {
  self.concurrent_safe
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
  /// Optional one-line human summary of what this call did (e.g. `ran ls → 12
  /// files`). Display-only: persisted on the `ToolResult` for the visualizer and
  /// never sent to the model. `None` when the tool supplies no brief.
  brief : String?
} derive(Debug)

///|
/// Constructs typed tool output. `is_error` defaults to `false` for ordinary
/// successful tool responses; `brief` is omitted unless the tool supplies a
/// one-line summary.
fn ToolOutput::ToolOutput(
  content : String,
  is_error? : Bool = false,
  brief? : String,
) -> ToolOutput {
  { content, is_error, brief, }
}

///|
/// Agent-level control requested by a tool action.
pub enum AgentControl {
  /// Stop the loop and surface the string as the final answer to the user.
  Finish(String)
  /// Stop the loop because execution cannot usefully continue.
  Abort(String)
} derive(Debug)

///|
/// The action returned by a tool executor. Normal tools respond to the model;
/// control tools request an agent-loop state transition.
pub enum ToolAction {
  /// Append the output as a `Tool(id)` chat message and keep looping.
  Respond(ToolOutput)
  /// Request a loop-control action such as finishing the task.
  Control(AgentControl)
} derive(Debug)

///|
/// Builds a normal tool response action. `brief` is an optional one-line summary
/// surfaced in the visualizer (see `ToolOutput::brief`); it never reaches the
/// model.
pub fn respond(
  content : String,
  is_error? : Bool = false,
  brief? : String,
) -> ToolAction {
  Respond(ToolOutput(content, is_error~, brief?))
}

///|
/// Build a one-line tool brief: collapse `text` to a single line, trim it, and
/// cap it to `limit` characters (appending `…` when cut). Iterates by character
/// so a cap never splits a surrogate pair. Line breaks and tabs become spaces;
/// other C0 controls and DEL are dropped — briefs and labels reach terminals
/// raw, so `\r`/ESC must not survive into a "single line". Helper for tools
/// assembling a brief.
pub fn brief_line(text : String, limit? : Int = 72) -> String {
  let sanitized = StringBuilder()
  for ch in text {
    if ch is ('\n' | '\r' | '\t') {
      sanitized.write_char(' ')
    } else if ch.to_int() < 0x20 || ch.to_int() == 0x7F {
      continue
    } else {
      sanitized.write_char(ch)
    }
  }
  let one = sanitized.to_string().trim()
  if one.length() <= limit {
    "\{one}"
  } else {
    // `iter()` yields characters, so `take` cuts on a character boundary.
    "\{String::from_iter(one.iter().take(limit))}…"
  }
}

///|
/// The final path segment of `path` (after the last `/` or `\`), for briefs that
/// name a file without its directory. Returns `path` unchanged when it has no
/// separator.
pub fn brief_basename(path : String) -> String {
  // Greedy to the last `/` or `\`; the remainder is the basename.
  if path =~ (re"^(.|\n)*[/\\]", after~) {
    after.to_owned()
  } else {
    path
  }
}

///|
/// Builds an action that finishes the agent loop.
pub fn ToolAction::finish(answer : String) -> ToolAction {
  Control(Finish(answer))
}

///|
/// Builds an action that aborts the agent loop.
fn ToolAction::abort(reason : String) -> ToolAction {
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
  let by_name : Map[String, AgentToolDefinition] = Map([])
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
///
/// A tool's own execution failure is caught HERE and turned into an error
/// `ToolAction`, so the model sees it as an ordinary (recoverable) tool result
/// and the turn continues — one boundary that spares every tool from wrapping
/// each of its own filesystem/IO calls just to report a failure.
///
/// Cancellation is the exception: it is re-raised so the loop can abort the
/// turn (see the terminal handler in `AgentLoop`, which maps it to
/// `Interrupted`). That is also why this function stays raise-able rather than
/// `noraise`: since `async` defaults to raising, marking it `noraise` would
/// force cancellation to be caught and swallowed here too, and the turn would
/// no longer be cancellable mid-tool-call.
pub async fn execute_tool_call(
  call : AgentToolCall,
  tools : Tools,
) -> ToolAction {
  match tools.find(call.name) {
    Some(tool) =>
      tool.execute.run(call.arguments) catch {
        error =>
          if @async.is_being_cancelled() || @async.is_cancellation_error(error) {
            raise error
          } else {
            // Keep the transcript label the local catches used to provide:
            // most file tools carry a `path` argument, so the brief can still
            // name the file the failed call was about.
            let brief = match call.arguments {
              { "path": String(path), .. } =>
                Some("\{call.name} \{brief_basename(path)}")
              _ => None
            }
            respond(
              "error: \{call.name} failed: \{error}",
              is_error=true,
              brief?,
            )
          }
      }
    None => respond("error: unknown tool \{call.name}", is_error=true)
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
  let response = respond("ok")
  guard response is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "ok")
  assert_false(output.is_error)
  let error_response = respond("bad", is_error=true)
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
/// One minimal registry entry for the dispatch tests. The privileges
/// (`control`, `concurrent_safe`) are the constructor's own defaults, so no
/// test below has to restate them just to build an ordinary tool.
fn test_tool(
  name? : String = "echo",
  description? : String = "Echo.",
  schema? : Json = { "type": "object" },
  execute? : ToolExecutor = Sync(_args => respond("ok")),
) -> AgentToolDefinition {
  AgentToolDefinition(name~, description~, schema=JsonSchema(schema), execute~)
}

///|
test "Tools::find returns the registered definition by name" {
  let tools = Tools([test_tool()])
  guard tools.find("echo") is Some(definition) else { fail("missing echo") }
  assert_eq(definition.name, "echo")
  assert_true(tools.find("ghost") is None)
}

///|
test "Tools::Tools raises on duplicate tool names" {
  let _ = Tools([
    test_tool(description="First.", execute=Sync(_args => respond("first"))),
    test_tool(description="Second.", execute=Sync(_args => respond("second"))),
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
    test_tool(
      execute=Sync(args => {
        match args {
          { "value": String(v), .. } => respond(v)
          _ => respond("no value", is_error=true)
        }
      }),
    ),
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
    { "value": String(v), .. } => respond(v)
    _ => respond("no value", is_error=true)
  }
}

///|
async test "execute_tool_call dispatches to async executor" {
  let tools = Tools([
    test_tool(description="Async echo.", execute=Async(async_echo)),
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
async test "execute_tool_call turns a tool failure into a recoverable error result" {
  // Local to the test on purpose: an always-failing executor must not be
  // callable from anywhere else in the package.
  async fn async_boom(_args : Json) -> ToolAction {
    @async.pause()
    fail("disk on fire")
  }

  let tools = Tools([
    test_tool(
      name="boom",
      description="Always fails.",
      execute=Async(async_boom),
    ),
  ])
  let call = AgentToolCall(ToolCall(id="call_1", name="boom", arguments="{}"))
  // The tool's failure is caught at the dispatch boundary and returned as an
  // error action the model can react to — the turn is NOT aborted.
  let result = execute_tool_call(call, tools)
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("boom failed"))
}

///|
test "Tools::function_tools preserves description and schema" {
  let tools = Tools([
    test_tool(description="Echo what comes in.", schema={
      "type": "object",
      "properties": Json::empty_object(),
    }),
  ])
  let function_tools = tools.function_tools()
  assert_eq(function_tools.length(), 1)
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
    test_tool(
      name="first",
      description="First.",
      execute=Sync(_args => respond("1")),
    ),
    test_tool(
      name="second",
      description="Second.",
      execute=Sync(_args => respond("2")),
    ),
    test_tool(
      name="third",
      description="Third.",
      execute=Sync(_args => respond("3")),
    ),
  ])
  let function_tools = tools.function_tools()
  assert_eq(function_tools.length(), 3)
  let names = [ for t in function_tools => t.name ]
  assert_true(names.contains("first"))
  assert_true(names.contains("second"))
  assert_true(names.contains("third"))
}

///|
pub extend AgentControl with Debug::{to_repr}

///|
pub extend AgentToolDefinition with Debug::{to_repr}

///|
pub extend JsonSchema with Debug::{to_repr}

///|
pub extend ToolAction with Debug::{to_repr}

///|
pub extend ToolOutput with Debug::{to_repr}
