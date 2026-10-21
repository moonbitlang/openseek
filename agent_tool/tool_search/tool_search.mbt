///|
/// Results returned when a call does not pass `limit`.
const DefaultLimit : Int32 = 8

///|
/// Cap on one result's text, below the agent loop's per-result clamp so a page
/// of large schemas is never cut inside an entry: a page holds only the whole
/// entries that fit, and says where the next one starts.
const MaxOutputChars : Int32 = 40000

///|
/// Cap on the part of a server's instructions shown in the tool description:
/// the description rides on every request, so only a first line fits.
const MaxInstructionsChars : Int32 = 160

///|
/// One server whose tools `tool_search` finds: its name, the instructions it
/// sent when it connected, and the tools it contributed, in registration order.
struct Source {
  name : String
  instructions : String?
  tools : Array[@agent_tool.AgentToolDefinition]
}

///|
/// Describe one server for `tool_search`.
pub fn Source::Source(
  name~ : String,
  instructions? : String,
  tools~ : Array[@agent_tool.AgentToolDefinition],
) -> Source {
  { name, instructions, tools, }
}

///|
/// One searchable tool with the server that contributed it and its ranking
/// text: name, description, and the schema's property names and descriptions.
priv struct Entry {
  server : String
  tool : @agent_tool.AgentToolDefinition
  text : String
}

///|
/// Keywords whose value is one subschema.
let single_subschema_keywords : Array[String] = [
  "items", "additionalProperties", "additionalItems", "contains", "not", "if", "then",
  "else", "propertyNames", "unevaluatedItems", "unevaluatedProperties", "contentSchema",
]

///|
/// Keywords whose value is an array of subschemas (`items` in its tuple form).
let array_subschema_keywords : Array[String] = [
  "allOf", "anyOf", "oneOf", "prefixItems", "items",
]

///|
/// Keywords whose value maps names to subschemas. The names of `properties`
/// are arguments, and those of `$defs`/`definitions` name the definitions
/// arguments refer to; pattern and dependency names are not searchable text.
let named_subschema_keywords : Array[String] = [
  "properties", "$defs", "definitions",
]

///|
/// `dependencies` mixes schemas with arrays of names; only its schemas count.
let keyed_subschema_keywords : Array[String] = [
  "patternProperties", "dependentSchemas", "dependencies",
]

///|
/// Property names and descriptions anywhere in `schema`, so a query naming an
/// argument (`repository`, `timezone`) finds the tool that takes it. Every
/// subschema container is walked; instance values (`default`, `examples`,
/// `enum`) are not schemas and are left out.
fn schema_text(schema : Json, parts : Array[String]) -> Unit {
  guard schema is Object(fields) else { return }
  if fields.get("description") is Some(String(description)) {
    parts.push(description)
  }
  for key in single_subschema_keywords {
    if fields.get(key) is Some(Object(_) as subschema) {
      schema_text(subschema, parts)
    }
  }
  for key in array_subschema_keywords {
    if fields.get(key) is Some(Array(subschemas)) {
      for subschema in subschemas {
        schema_text(subschema, parts)
      }
    }
  }
  for key in named_subschema_keywords {
    if fields.get(key) is Some(Object(subschemas)) {
      for name, subschema in subschemas {
        parts.push(name)
        schema_text(subschema, parts)
      }
    }
  }
  for key in keyed_subschema_keywords {
    if fields.get(key) is Some(Object(subschemas)) {
      for _, subschema in subschemas {
        schema_text(subschema, parts)
      }
    }
  }
}

///|
fn entry(server : String, tool : @agent_tool.AgentToolDefinition) -> Entry {
  let JsonSchema(schema) = tool.schema
  let parts = [tool.name, tool.description]
  schema_text(schema, parts)
  if tool.output_schema is Some(JsonSchema(output)) {
    schema_text(output, parts)
  }
  { server, tool, text: parts.join(" "), }
}

///|
/// The first line of `text`, at most `limit` characters, marked when cut.
fn first_line(text : String, limit : Int32) -> String {
  let line = text.trim().split("\n").next().unwrap_or("").trim()
  if line.char_length() <= limit {
    line.to_owned()
  } else {
    let cut = line.offset_of_nth_char(limit).unwrap_or(line.length())
    "\{line[:cut]}…"
  }
}

///|
/// The fixed description: how MCP tools are reached and which servers offer
/// them. Built once per registry, so it never changes between requests.
fn description(sources : Array[Source]) -> String {
  let servers = StringBuilder()
  for source in sources {
    let count = source.tools.length()
    servers.write_string("\n- \{source.name} (\{count_of(count, "tool")})")
    if source.instructions is Some(instructions) {
      let line = first_line(instructions, MaxInstructionsChars)
      if line != "" {
        servers.write_string(": \{line}")
      }
    }
  }
  (
    $|Find MCP tools and the arguments they take. MCP tools are not in your function list: call one from an mbtx script with `@openseek_tools.call(name, arguments)`, using the exact name and an arguments object that matches the schema this tool returns.
    $|
    $|Pass `query` to rank tools by keywords, `server` to list one server's tools, or both to search within one server.
    $|
    $|MCP servers:
  ) +
  servers.to_string()
}

///|
/// `count` and `noun`, plural unless the count is one.
fn count_of(count : Int32, noun : String) -> String {
  if count == 1 {
    "1 \{noun}"
  } else {
    "\{count} \{noun}s"
  }
}

///|
/// How a call came out.
priv enum Selection {
  /// Every matching tool in order, under a heading that says what they are.
  Found(heading~ : String, matches~ : Array[Entry])
  /// A valid search that matched nothing; the text suggests what to try.
  NoMatch(String)
  /// A call that names an unknown server or neither a query nor a server.
  Invalid(String)
}

///|
/// Pick the tools a call asks for: ranked by `query`, within `server` when
/// both are given, or `server`'s tools in order.
fn select(
  sources : Array[Source],
  entries : Array[Entry],
  query : String?,
  server : String?,
) -> Selection {
  let known = sources.map(source => "`\{source.name}`").join(", ")
  if server is Some(name) && !sources.iter().any(source => source.name == name) {
    return Invalid("error: no MCP server `\{name}`; servers: \{known}")
  }
  let pool = match server {
    Some(name) => entries.filter(entry => entry.server == name)
    None => entries
  }
  match (query, server) {
    (Some(query), _) => {
      let ranked = @bm25.rank(
        query~,
        documents=pool.map(entry => entry.text),
        limit=pool.length(),
      )
      let scope = server.map(name => " in `\{name}`").unwrap_or("")
      // Ranking reads the whole query; messages echo a bounded line of it, so
      // a long query cannot crowd out the page it heads.
      let shown = @agent_tool.brief_line(query, limit=80)
      if ranked.is_empty() {
        NoMatch(
          "No MCP tools\{scope} match `\{shown}`. Try other keywords, or list a server's tools with `server` (\{known}).",
        )
      } else {
        Found(
          heading="\{count_of(ranked.length(), "MCP tool")}\{scope} match `\{shown}`, best first.",
          matches=ranked.map(index => pool[index]),
        )
      }
    }
    (None, Some(name)) if pool.is_empty() =>
      NoMatch("`\{name}` offers no tools.")
    (None, Some(name)) =>
      Found(
        heading="`\{name}` offers \{count_of(pool.length(), "tool")}.",
        matches=pool,
      )
    (None, None) => Invalid("error: pass `query`, `server`, or both")
  }
}

///|
/// One tool as a result shows it: name, description, the JSON Schema of its
/// arguments and, when the server declares it, of its result's `data`.
fn render_entry(entry : Entry) -> String {
  let JsonSchema(schema) = entry.tool.schema
  let result = match entry.tool.output_schema {
    Some(JsonSchema(output)) => "\nResult `data` schema: \{output.stringify()}"
    None => ""
  }
  "\n\n## \{entry.tool.name}\n\{entry.tool.description.trim()}\nArguments schema: \{schema.stringify()}\{result}"
}

///|
/// The page of `matches` starting at `offset`: at most `limit` whole entries
/// that fit `MaxOutputChars` together (always at least one, which the bridge's
/// per-tool caps keep far below it), and where the next page starts.
fn render(
  heading : String,
  matches : Array[Entry],
  offset : Int32,
  limit : Int32,
) -> String {
  let out = StringBuilder()
  out.write_string(heading)
  // Room kept for the paging line and the closing note, which come last.
  let budget = MaxOutputChars - FooterNote.length() - 200
  let mut shown = 0
  let mut used = heading.length()
  for entry in matches[offset:] {
    let text = render_entry(entry)
    if shown == limit || (shown > 0 && used + text.length() > budget) {
      break
    }
    out.write_string(text)
    used += text.length()
    shown += 1
  }
  let next = offset + shown
  if offset > 0 || next < matches.length() {
    out.write_string(
      "\n\nShowing \{offset + 1}–\{next} of \{matches.length()}.",
    )
    if next < matches.length() {
      out.write_string(" Pass `offset: \{next}` for the next ones.")
    }
  }
  out.write_string(FooterNote)
  out.to_string()
}

///|
/// How results close: the call form.
const FooterNote : String = "\n\nCall these from an mbtx script with `@openseek_tools.call(name, arguments)`; they are not in your function list. `result.data` is `Json?`: match it."

///|
/// A non-negative integer argument: absent or null is `default`, anything
/// else that is not a whole number at least `minimum` is `None`.
fn whole_number(
  arguments : Json,
  key : String,
  default~ : Int32,
  minimum~ : Int32,
) -> Int32? {
  guard arguments is Object(fields) && fields.get(key) is Some(value) else {
    return Some(default)
  }
  match value {
    Null => Some(default)
    // `to_int` saturates, so a huge value simply means "all of them".
    Number(number, ..) if number >= minimum.to_double() &&
      number == number.floor() => Some(number.to_int())
    _ => None
  }
}

///|
/// Read `arguments` and answer one search.
fn search(
  sources : Array[Source],
  entries : Array[Entry],
  arguments : Json,
) -> @agent_tool.ToolAction {
  let query = match arguments {
    { "query": String(query), .. } if !query.is_blank() => Some(query)
    { "query": String(_) | Null, .. } => None
    { "query": _, .. } =>
      return @agent_tool.respond(
        "error: `query` must be a string",
        is_error=true,
      )
    _ => None
  }
  let server = match arguments {
    { "server": String(server), .. } if !server.is_blank() => Some(server)
    { "server": String(_) | Null, .. } => None
    { "server": _, .. } =>
      return @agent_tool.respond(
        "error: `server` must be a string",
        is_error=true,
      )
    _ => None
  }
  guard whole_number(arguments, "limit", default=DefaultLimit, minimum=1)
    is Some(limit) else {
    return @agent_tool.respond(
      "error: `limit` must be a positive integer",
      is_error=true,
    )
  }
  guard whole_number(arguments, "offset", default=0, minimum=0) is Some(offset) else {
    return @agent_tool.respond(
      "error: `offset` must be a non-negative integer",
      is_error=true,
    )
  }
  match select(sources, entries, query, server) {
    Found(heading~, matches~) if offset >= matches.length() =>
      @agent_tool.respond(
        "error: `offset` \{offset} is past the last result; \{heading}",
        is_error=true,
      )
    Found(heading~, matches~) =>
      @agent_tool.respond(
        render(heading, matches, offset, limit),
        brief=@agent_tool.brief_line(heading),
      )
    NoMatch(message) =>
      @agent_tool.respond(message, brief=@agent_tool.brief_line(message))
    Invalid(message) => @agent_tool.respond(message, is_error=true)
  }
}

///|
/// The `tool_search` tool over `sources`, the model's way to find MCP tools
/// that are reachable only from mbtx scripts.
///
/// The description names every server with its tool count, so the model knows
/// what exists without any tool schema in the request. A call ranks tools with
/// BM25 (`query`), lists one server's tools (`server`), or ranks within one
/// server (both); every result carries the exact name, description, and
/// argument schema a script needs. Results come in pages (`limit`, `offset`)
/// that also stay under a size cap. Bad arguments and an unknown server are
/// error results; no match is an ordinary result suggesting what to try.
pub fn definition(sources : Array[Source]) -> @agent_tool.AgentToolDefinition {
  let entries : Array[Entry] = []
  for source in sources {
    for tool in source.tools {
      entries.push(entry(source.name, tool))
    }
  }
  AgentToolDefinition(
    name="tool_search",
    description=description(sources),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Keywords for the tool you need, e.g. `create calendar event`.",
        },
        "server": {
          "type": "string",
          "description": "Only this MCP server's tools; alone, lists them.",
        },
        "limit": {
          "type": "integer",
          "minimum": 1,
          "description": "Maximum tools to return. Defaults to \{DefaultLimit}.",
        },
        "offset": {
          "type": "integer",
          "minimum": 0,
          "description": "Skip this many results, to page through a long list. Defaults to 0.",
        },
      },
      "additionalProperties": false,
    }),
    execute=Sync(arguments => search(sources, entries, arguments)),
  )
}
