// The `seekmoon` command: the host's tools as a command line, for an agent
// to run from a script. It is a client of the server in this package and
// knows no tool by name — its subcommands and options are whatever the
// server lists, so a host package that contributes a tool gets its command
// with no code here.
//
// Tools live under `seekmoon tools`; `seekmoon mcp` (`stdio.mbt`) is the
// same tools for a client that speaks MCP. A tool named `browser_get_text` is run as
// `seekmoon tools browser get-text`: the text before the first underscore
// groups related tools, and the rest is the verb. Each top-level property of
// the tool's input schema is an option of the same name, with underscores
// written as hyphens.
//
// The command finds the server, and proves which conversation it speaks for,
// from the two variables of a grant (`Server::grant`). It takes neither as an
// argument: a script has no business choosing them.

///|
/// What one run of the command came to: what it would print, and its exit
/// status. `code` is 0 for a tool that succeeded, 1 for one that failed or
/// could not be reached, and 2 for a command line that could not be run at
/// all.
pub(all) struct CliOutcome {
  code : Int32
  stdout : String
  stderr : String
}

///|
priv suberror CliError {
  // The command line cannot be run: no grant, or arguments no tool accepts.
  Usage(String)
  // The host could not be asked, or refused.
  Unavailable(String)
}

///|
/// One tool as the server lists it.
priv struct ListedTool {
  name : String
  description : String
  // The input schema's top-level properties, in the order the tool declared
  // them, and which of them it requires.
  properties : Map[String, Json]
  required : Array[String]
}

///|
/// Run `seekmoon` with `args` (the command line after the program name) in
/// the environment `env`.
pub async fn cli(args : Array[String], env : Map[String, String]) -> CliOutcome {
  try run_cli(args, env) catch {
    error if @async.is_being_cancelled() => raise error
    Usage(message) => { code: 2, stdout: "", stderr: message, }
    Unavailable(message) => { code: 1, stdout: "", stderr: message, }
    error => { code: 1, stdout: "", stderr: "\{error}", }
  } noraise {
    outcome => outcome
  }
}

///|
async fn run_cli(args : Array[String], env : Map[String, String]) -> CliOutcome {
  guard env.get(UrlEnv) is Some(url) && env.get(TokenEnv) is Some(token) else {
    raise Usage(ungranted_message())
  }
  let listed = request(url, token, "tools/list", Json::empty_object())
  guard listed is { "tools": Array(entries), .. } else {
    raise Unavailable("the SeekMoon desktop app did not list its tools")
  }
  let tools = entries.filter_map(listed_tool)
  let matches = command_tree(tools).parse(argv=args, env={}) catch {
    error => raise Usage("\{error}")
  }
  let (tool, matches) = selected_tool(tools, matches)
  let result = request(url, token, "tools/call", {
    "name": Json(tool.name),
    "arguments": tool_arguments(tool, matches),
  })
  let text = match result {
    { "content": Array(blocks), .. } =>
      blocks
      .filter_map(block => {
        match block {
          { "type": "text", "text": String(text), .. } => Some(text)
          _ => None
        }
      })
      .join("\n")
    _ => ""
  }
  if result is { "isError": True, .. } {
    { code: 1, stdout: "", stderr: text, }
  } else {
    { code: 0, stdout: text, stderr: "", }
  }
}

///|
/// What the command says when its environment holds no grant.
fn ungranted_message() -> String {
  "seekmoon talks to the SeekMoon desktop app that started this agent, and nothing here was started by one (\{UrlEnv} and \{TokenEnv} are not set)."
}

///|
/// The JSON-RPC error code for a request the host could not be asked: from
/// the range the protocol leaves to implementations.
const HostUnavailable : Int32 = -32000

///|
/// POST one JSON-RPC message to the server as written, returning its reply,
/// or `None` when the server accepted it and has nothing to say back.
async fn post_message(url : String, token : String, body : String) -> Json? {
  let (response, reply) = @http.post(url, body, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer \{token}",
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise Unavailable("could not reach the SeekMoon desktop app: \{error}")
  }
  match response.code {
    200 => Some(reply.json())
    202 => None
    // A token the server does not know is one from an earlier launch: the
    // app restarted under an agent that is still running.
    code =>
      raise Unavailable(
        "the SeekMoon desktop app refused the request (HTTP \{code}); it may have restarted since this agent started",
      )
  }
}

///|
/// One JSON-RPC request to the server, returning its `result`.
async fn request(
  url : String,
  token : String,
  method_ : String,
  params : Json,
) -> Json {
  let message : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": Json(method_),
    "params": params,
  }
  match post_message(url, token, message.stringify()) {
    Some({ "result": result, .. }) => result
    Some({ "error": { "message": String(message), .. }, .. }) =>
      raise Unavailable(message)
    _ => raise Unavailable("the SeekMoon desktop app sent an unreadable reply")
  }
}

///|
/// A `tools/list` entry, or `None` for one without a name — which this
/// package's server never sends.
fn listed_tool(entry : Json) -> ListedTool? {
  guard entry is { "name": String(name), .. } else { return None }
  let description = match entry {
    { "description": String(description), .. } => description
    _ => ""
  }
  let properties = match entry {
    { "inputSchema": { "properties": Object(properties), .. }, .. } =>
      properties
    _ => Map([])
  }
  let required = match entry {
    { "inputSchema": { "required": Array(names), .. }, .. } =>
      names.filter_map(name => {
        match name {
          String(name) => Some(name)
          _ => None
        }
      })
    _ => []
  }
  Some({ name, description, properties, required, })
}

///|
/// The words after `seekmoon tools` that run `tool`: its group and verb, or
/// the bare name for a tool whose name has no underscore.
fn command_path(tool : ListedTool) -> Array[String] {
  match tool.name.split_once("_") {
    Some((group, verb)) =>
      [group.to_owned(), verb.to_owned().replace_all(old="_", new="-")]
    None => [tool.name]
  }
}

///|
/// The option spelling of a schema property.
fn option_name(property : String) -> String {
  property.replace_all(old="_", new="-")
}

///|
fn property_kind(property : Json) -> String? {
  match property {
    { "type": String(kind), .. } => Some(kind)
    _ => None
  }
}

///|
/// The command for one tool: an option per schema property, a flag for each
/// boolean.
fn tool_command(name : String, tool : ListedTool) -> @argparse.Command {
  let flags : Array[@argparse.FlagArg] = []
  let options : Array[@argparse.OptionArg] = []
  for property, schema in tool.properties {
    let about = match schema {
      { "description": String(about), .. } => about
      _ => ""
    }
    if property_kind(schema) == Some("boolean") {
      flags.push(FlagArg(property, long=option_name(property), about~))
    } else {
      options.push(
        OptionArg(
          property,
          long=option_name(property),
          about~,
          required=tool.required.contains(property),
          // A reference or a snippet of page text may begin with a hyphen.
          allow_hyphen_values=true,
        ),
      )
    }
  }
  Command(name, flags~, options~, about=tool.description)
}

///|
/// The subcommand every tool is found under.
const ToolsCommand = "tools"

///|
/// The whole command line, built from what the server offers.
fn command_tree(tools : Array[ListedTool]) -> @argparse.Command {
  let top : Array[@argparse.Command] = []
  let groups : Map[String, Array[@argparse.Command]] = Map([])
  for tool in tools {
    match command_path(tool) {
      [group, verb] => {
        if !groups.contains(group) {
          groups[group] = []
        }
        if groups.get(group) is Some(verbs) {
          verbs.push(tool_command(verb, tool))
        }
      }
      _ => top.push(tool_command(tool.name, tool))
    }
  }
  for group, verbs in groups {
    top.push(Command(group, subcommands=verbs, subcommand_required=true))
  }
  Command(
    "seekmoon",
    about="Use the SeekMoon desktop app that started this agent.",
    subcommands=[
      Command(
        ToolsCommand,
        about="Run one of the app's tools.",
        subcommands=top,
        subcommand_required=true,
      ),
      // Listed so `--help` shows it; the executable hands this subcommand to
      // `serve_stdio` before a command line reaches here.
      mcp_command(),
    ],
    subcommand_required=true,
  )
}

///|
/// The tool a parsed command line names, with the matches of its own
/// command.
fn selected_tool(
  tools : Array[ListedTool],
  matches : @argparse.Matches,
) -> (ListedTool, @argparse.Matches) raise CliError {
  let path : Array[String] = []
  let mut innermost = matches
  while innermost.subcommand is Some((name, inner)) {
    path.push(name)
    innermost = inner
  }
  for tool in tools {
    if [ToolsCommand, ..command_path(tool)] == path {
      return (tool, innermost)
    }
  }
  // `subcommand_required` makes the parser refuse a line that names no tool.
  raise Usage("seekmoon needs a tool to run; see `seekmoon tools --help`")
}

///|
/// The `arguments` object for `tool`, read from its command's matches. A
/// string property is passed as written and a boolean is its flag; anything
/// else is given as JSON, so a number is `3` and an array is `[1, 2]`.
fn tool_arguments(
  tool : ListedTool,
  matches : @argparse.Matches,
) -> Json raise CliError {
  let arguments : Map[String, Json] = Map([])
  for property, schema in tool.properties {
    match property_kind(schema) {
      Some("boolean") =>
        if matches.flags.get(property) is Some(true) {
          arguments[property] = true
        }
      kind =>
        if matches.values.get(property) is Some([value, ..]) {
          arguments[property] = if kind == Some("string") {
            Json(value)
          } else {
            @json.parse(value) catch {
              _ =>
                raise Usage(
                  "--\{option_name(property)} takes JSON, and `\{value}` is not",
                )
            }
          }
        }
    }
  }
  Json::object(arguments)
}
