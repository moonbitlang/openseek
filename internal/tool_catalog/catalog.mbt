///|
/// Tools a page lists when a search does not pass `limit`.
const DefaultLimit : Int32 = 8

///|
/// How many of a page's entries, best first, carry an example call.
const ExampleCount : Int32 = 2

///|
/// Cap on a page's text, below the agent loop's per-result clamp so a page of
/// large schemas is never cut inside an entry: a page holds only the whole
/// entries that fit, and says where the next one starts.
const MaxTextChars : Int32 = 40000

///|
/// Cap on a page's text and `data` together, each JSON-encoded as a PTC reply
/// carries them, kept under the 64 KiB a reply may take.
const MaxReplyChars : Int32 = 60000

///|
/// Cap on the server instructions a page opens with.
const MaxInstructionsChars : Int32 = 4000

///|
/// Cap on the line a listing gives an unavailable server's error.
const MaxErrorLineChars : Int32 = 160

///|
/// Cap on one tool's description, so a misbehaving server cannot crowd a page.
const MaxDescriptionChars : Int32 = 1024

///|
/// Cap on one serialized schema. With the description cap it bounds an entry,
/// so a page always has room for one: its records carry both schemas whole.
const MaxSchemaChars : Int32 = 16384

///|
/// One MCP tool under its server's own name: what it does, the JSON Schema of
/// its arguments and, when the server declares one, of its result.
struct Tool {
  name : String
  description : String
  input_schema : Json
  output_schema : Json?
}

///|
/// Describe one tool for the catalog. Server-supplied parts are bounded: a
/// description over `MaxDescriptionChars` is cut and marked, an arguments
/// schema that is not an object or is over `MaxSchemaChars` becomes the open
/// object schema (the server still validates its arguments), and an oversized
/// result schema is dropped, since it only helps whoever reads `data`.
pub fn Tool::Tool(
  name~ : String,
  description~ : String,
  input_schema~ : Json,
  output_schema? : Json,
) -> Tool {
  let description = if description.char_length() <= MaxDescriptionChars {
    description
  } else {
    let cut = description
      .offset_of_nth_char(MaxDescriptionChars)
      .unwrap_or(description.length())
    "\{description[:cut]}…"
  }
  let input_schema = if input_schema is Object(_) &&
    input_schema.stringify().length() <= MaxSchemaChars {
    input_schema
  } else {
    { "type": "object" }
  }
  let output_schema = output_schema.filter(schema => {
    schema.stringify().length() <= MaxSchemaChars
  })
  { name, description, input_schema, output_schema, }
}

///|
/// What connecting a server came to.
priv enum Availability {
  /// Connected, with its tools in registration order (possibly none).
  Available(Array[Tool])
  /// Not connected, with the error.
  Unavailable(String)
}

///|
/// One configured MCP server as the catalog shows it.
struct Source {
  name : String
  instructions : String?
  availability : Availability
}

///|
/// A server that connected, with the instructions it sent and its tools in
/// registration order.
pub fn Source::Source(
  name~ : String,
  instructions? : String,
  tools~ : Array[Tool],
) -> Source {
  { name, instructions, availability: Available(tools), }
}

///|
/// A configured server that did not connect, and why.
pub fn Source::unavailable(name~ : String, error~ : String) -> Source {
  { name, instructions: None, availability: Unavailable(error), }
}

///|
/// One searchable tool with the server that contributed it and its ranking
/// text: server, name, description, and the schemas' property names and
/// descriptions.
priv struct Entry {
  server : String
  tool : Tool
  text : String
}

///|
/// The MCP tools of every configured server, which scripts search through
/// `@mcp.search`. Built once per registry; searching reads it only.
struct Catalog {
  sources : Array[Source]
  entries : Array[Entry]
}

///|
/// The catalog of `sources`, in their order.
pub fn Catalog::Catalog(sources : Array[Source]) -> Catalog {
  let entries : Array[Entry] = []
  for source in sources {
    if source.availability is Available(tools) {
      for tool in tools {
        entries.push(entry(source.name, tool))
      }
    }
  }
  { sources, entries, }
}

///|
/// One answered search: `text` for the model once a script prints it, and
/// `data` for the script, `{"tools", "total", "next_offset"?,
/// "instructions"?}`, listing the same tools with their raw schemas.
pub struct Page {
  text : String
  data : Json
}

///|
/// A search the catalog refuses: invalid arguments or an unknown server.
pub suberror SearchError {
  SearchError(String)
}

///|
pub extend SearchError with Show::{to_string, output}

///|
impl Show for SearchError with fn output(self, logger) {
  let SearchError(message) = self
  logger.write_string(message)
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
fn entry(server : String, tool : Tool) -> Entry {
  let parts = [server, tool.name, tool.description]
  schema_text(tool.input_schema, parts)
  if tool.output_schema is Some(output) {
    schema_text(output, parts)
  }
  { server, tool, text: parts.join(" "), }
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
/// How a search came out.
priv enum Selection {
  /// Every matching tool in order, under a heading that says what they are.
  Found(heading~ : String, matches~ : Array[Entry])
  /// Nothing to list; the text says why and what to try.
  Empty(String)
}

///|
/// Pick the tools a search asks for: ranked by `query`, within `server` when
/// both are given, `server`'s tools in order, or every tool in order.
fn Catalog::select(
  self : Catalog,
  query : String?,
  server : Source?,
) -> Selection {
  let pool = match server {
    Some(source) => self.entries.filter(entry => entry.server == source.name)
    None => self.entries
  }
  let scope = server.map(source => " in `\{source.name}`").unwrap_or("")
  match (query, server) {
    (_, Some({ availability: Unavailable(error), name, .. })) =>
      Empty("`\{name}` is unavailable: \{error}")
    (Some(query), _) => {
      let ranked = @bm25.rank(
        query~,
        documents=pool.map(entry => entry.text),
        limit=pool.length(),
      )
      // Ranking reads the whole query; messages echo a bounded line of it, so
      // a long query cannot crowd out the page it heads.
      let shown = @agent_tool.brief_line(query, limit=80)
      if ranked.is_empty() {
        Empty(
          "No MCP tools\{scope} match `\{shown}`. Try other keywords, or run `@mcp.search()` with no arguments to list every tool.",
        )
      } else {
        Found(
          heading="\{count_of(ranked.length(), "MCP tool")}\{scope} match `\{shown}`, best first.",
          matches=ranked.map(index => pool[index]),
        )
      }
    }
    (None, Some(source)) if pool.is_empty() =>
      Empty("`\{source.name}` offers no tools.")
    (None, Some(source)) =>
      Found(
        heading="`\{source.name}` offers \{count_of(pool.length(), "tool")}.",
        matches=pool,
      )
    (None, None) if self.sources.is_empty() =>
      Empty("No MCP servers are configured.")
    (None, None) if pool.is_empty() => Empty("No MCP tools are available.")
    (None, None) => {
      let servers = self.sources.filter(source => {
        source.availability is Available(tools) && !tools.is_empty()
      })
      Found(
        heading="\{count_of(pool.length(), "MCP tool")} across \{count_of(servers.length(), "server")}.",
        matches=pool,
      )
    }
  }
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
/// The servers that did not connect, one line each, for a listing of every
/// tool: without them the model would take a missing service as absent.
fn Catalog::unavailable_note(self : Catalog) -> String {
  let lines = StringBuilder()
  for source in self.sources {
    if source.availability is Unavailable(error) {
      lines.write_string(
        "\n- `\{source.name}`: \{first_line(error, MaxErrorLineChars)}",
      )
    }
  }
  let lines = lines.to_string()
  if lines == "" {
    ""
  } else {
    "\n\nThese servers are configured but unavailable:\{lines}"
  }
}

///|
/// `source`'s instructions as a page opens with them: whole up to
/// `MaxInstructionsChars`, marked when cut, or `None` when it sent none.
fn instructions_of(source : Source) -> String? {
  guard source.instructions is Some(text) && !text.is_blank() else {
    return None
  }
  let text = text.trim()
  if text.char_length() <= MaxInstructionsChars {
    Some(text.to_owned())
  } else {
    let cut = text
      .offset_of_nth_char(MaxInstructionsChars)
      .unwrap_or(text.length())
    Some("\{text[:cut]}… (cut at \{MaxInstructionsChars} characters)")
  }
}

///|
/// One tool as a page shows it: server and name, description, its arguments
/// and (when the server declares it) its result's `data`, both sketched as the
/// `Json` a script builds and matches, and, `with_example`, an example to
/// start from. Without `with_notes` the argument descriptions are left out
/// too.
fn render_entry(
  entry : Entry,
  with_example~ : Bool,
  with_notes~ : Bool = true,
) -> String {
  let input = entry.tool.input_schema
  let output = entry.tool.output_schema
  let result = match output {
    Some(output) => "\nResult `data`: \{sketch_line(output)}"
    None => ""
  }
  let example = if with_example {
    example(entry.server, entry.tool.name, input, output)
  } else {
    ""
  }
  let notes = if with_notes { argument_notes(input) } else { "" }
  "\n\n## \{entry.server} / \{entry.tool.name}\n\{entry.tool.description.trim()}\nArguments: \{sketch_line(input)}\{notes}\{result}\{example}"
}

///|
/// One tool when even a lone entry would not fit a page: its server, name,
/// and description, with its schemas left to the page's records.
fn brief_entry(entry : Entry) -> String {
  "\n\n## \{entry.server} / \{entry.tool.name}\n\{entry.tool.description.trim()}\nIts schemas are too large to show here: read `input_schema` and `output_schema` from this page's `tools`."
}

///|
/// The ways a page can show one tool, the fullest first: with its notes and,
/// `with_example`, an example; then the shapes alone; then no shapes.
fn renderings(entry : Entry, with_example~ : Bool) -> Array[String] {
  [
    render_entry(entry, with_example~),
    render_entry(entry, with_example=false, with_notes=false),
    brief_entry(entry),
  ]
}

///|
/// One tool as a script reads it in `data`: its server, its name, its
/// description, and the raw JSON Schemas of its arguments and, when the
/// server declares one, its result.
fn entry_data(entry : Entry) -> Json {
  let fields : Map[String, Json] = {
    "server": Json(entry.server),
    "name": Json(entry.tool.name),
    "description": Json(entry.tool.description),
    "input_schema": entry.tool.input_schema,
  }
  if entry.tool.output_schema is Some(output) {
    fields["output_schema"] = output
  }
  Json::object(fields)
}

///|
/// The length of `text` as a JSON string, without its quotes.
fn encoded(text : String) -> Int32 {
  Json::string(text).stringify().length() - 2
}

///|
/// How a page with tools closes: the call form and how the shapes read as
/// patterns.
const FooterNote : String = "\n\nCall one from the same script with `@mcp.call(server, tool, arguments)`. Shapes name the MoonBit `Json` constructors that match them: `String(s)`, `Number(n, ..)` (integers too), `True` / `False`, `Null`, `Array(items)`, and objects as `{ \"key\": pattern, .. }`; `?` marks a field that may be absent. `result.data` is `Json?`, and `Json` has no fields or `stringify` on `Json?`: match it."

///|
/// The page of `matches` starting at `offset`: at most `limit` whole entries
/// whose text fits `MaxTextChars` and whose text and `data` together fit
/// `MaxReplyChars`, and where the next page starts. Each entry takes its
/// fullest rendering that fits; a page always shows at least one, in its
/// briefest rendering if nothing fits, which the catalog's per-tool caps keep
/// within both limits. `opening` comes
/// before the heading and `closing` after the entries.
fn render(
  opening : String,
  heading : String,
  matches : Array[Entry],
  offset : Int32,
  limit : Int32,
  closing : String,
) -> (String, Array[Json], Int32?) {
  let out = StringBuilder()
  out.write_string(opening)
  out.write_string(heading)
  let fixed = opening + heading + closing + FooterNote
  // Room kept for the paging line, which comes after the entries.
  let budget = MaxTextChars - fixed.length() - 200
  // `opening` holds the instructions, which `data` carries a second time.
  let reply_budget = MaxReplyChars - encoded(fixed) - encoded(opening) - 400
  let listed : Array[Json] = []
  let mut used = 0
  let mut reply_used = 0
  for entry in matches[offset:] {
    if listed.length() == limit {
      break
    }
    let data = entry_data(entry)
    let data_cost = data.stringify().length() + 1
    // The best matches carry an example; the rest follow the same form.
    let options = renderings(entry, with_example=listed.length() < ExampleCount)
    let fitting = options
      .iter()
      .find_first(text => {
        used + text.length() <= budget &&
        reply_used + encoded(text) + data_cost <= reply_budget
      })
    let text = match fitting {
      Some(text) => text
      None if listed.is_empty() => options[options.length() - 1]
      None => break
    }
    let cost = encoded(text) + data_cost
    out.write_string(text)
    listed.push(data)
    used += text.length()
    reply_used += cost
  }
  let next = offset + listed.length()
  if offset > 0 || next < matches.length() {
    out.write_string(
      "\n\nShowing \{offset + 1}–\{next} of \{matches.length()}.",
    )
    if next < matches.length() {
      out.write_string(" Pass `offset=\{next}` for the next ones.")
    }
  }
  out.write_string(closing)
  out.write_string(FooterNote)
  let next_offset = if next < matches.length() { Some(next) } else { None }
  (out.to_string(), listed, next_offset)
}

///|
/// Answer one search. `query` ranks tools with BM25, `server` lists one
/// server's tools in order, both rank within one server, and neither lists
/// every tool; a blank string is the same as leaving it out. Pages hold at
/// most `limit` tools (default 8, at least 1) from `offset` (default 0), and
/// stay under the size caps.
///
/// A search that names a server opens its first page with that server's
/// instructions; one that names an unavailable server says why it is. No
/// match is an ordinary page without tools. An unknown server, a `limit`
/// below 1, a negative `offset`, and an `offset` past the last result raise
/// `SearchError`.
pub fn Catalog::search(
  self : Catalog,
  query? : String,
  server? : String,
  limit~ : Int32 = DefaultLimit,
  offset~ : Int32 = 0,
) -> Page raise SearchError {
  let query = query.filter(query => !query.is_blank())
  let server = match server.filter(name => !name.is_blank()) {
    None => None
    Some(name) =>
      match self.sources.search_by(source => source.name == name) {
        Some(index) => Some(self.sources[index])
        None if self.sources.is_empty() =>
          raise SearchError("no MCP server `\{name}`: none are configured")
        None => {
          let known = self.sources.map(source => "`\{source.name}`").join(", ")
          raise SearchError("no MCP server `\{name}`; servers: \{known}")
        }
      }
  }
  guard limit >= 1 else {
    raise SearchError("`limit` must be a positive integer")
  }
  guard offset >= 0 else {
    raise SearchError("`offset` must be a non-negative integer")
  }
  let instructions = match server {
    Some(source) if offset == 0 => instructions_of(source)
    _ => None
  }
  let opening = match (server, instructions) {
    (Some(source), Some(text)) =>
      "Instructions from `\{source.name}`:\n\{text}\n\n"
    _ => ""
  }
  let closing = if offset == 0 && query is None && server is None {
    self.unavailable_note()
  } else {
    ""
  }
  let data : Map[String, Json] = Map([])
  let text = match self.select(query, server) {
    Found(heading~, matches~) if offset >= matches.length() =>
      raise SearchError(
        "`offset` \{offset} is past the last result; \{heading}",
      )
    Found(heading~, matches~) => {
      let (text, listed, next_offset) = render(
        opening, heading, matches, offset, limit, closing,
      )
      data["tools"] = Json::array(listed)
      data["total"] = Json(matches.length())
      if next_offset is Some(next) {
        data["next_offset"] = Json(next)
      }
      text
    }
    Empty(message) => {
      data["tools"] = []
      data["total"] = Json(0)
      opening + message + closing
    }
  }
  if instructions is Some(text) {
    data["instructions"] = Json(text)
  }
  { text, data: Json::object(data), }
}
