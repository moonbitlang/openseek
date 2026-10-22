///|
/// Tools a page lists when a search does not pass `limit`.
const DefaultLimit : Int32 = 8

///|
/// Cap on a page's text, what a printed page should cost the model's context.
/// A page holds only the whole entries that fit, and says where the next one
/// starts.
const MaxTextChars : Int32 = 40000

///|
/// Cap on the line a listing gives an unavailable server's error.
const MaxErrorLineChars : Int32 = 160

///|
/// Cap on the query a page's heading echoes, so a long query cannot crowd out
/// the page it heads.
const MaxQueryEchoChars : Int32 = 80

///|
/// One MCP tool under its server's own name: what it does, the JSON Schema of
/// its arguments and, when the server declares one, of its result. The host
/// bounds every server-supplied part before the catalog reaches the script.
pub struct Tool {
  name : String
  description : String
  input_schema : Json
  output_schema : Json?
}

///|
/// Describe one tool for the catalog.
pub fn Tool::Tool(
  name~ : String,
  description~ : String,
  input_schema~ : Json,
  output_schema? : Json,
) -> Tool {
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
/// One searchable tool with the server that contributed it. Its ranking text
/// holds the server, name, description, and the schemas' property names and
/// descriptions.
pub struct Entry {
  server : String
  tool : Tool
  priv text : String
}

///|
/// The MCP tools of every configured server, which scripts search through
/// `@mcp.search`. Built once from the downloaded catalog; searching reads it
/// only.
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
/// One answered search: `text` for the model once a script prints it, and the
/// same tools as records for the script.
pub struct Page {
  /// The page rendered for the model.
  text : String
  /// The named server's instructions, on a first page.
  instructions : String?
  /// The tools the page shows, in its order.
  tools : Array[Entry]
  /// How many tools matched across every page.
  total : Int32
  /// Where the next page starts, while matches remain.
  next_offset : Int32?
}

///|
/// A search the catalog refuses: invalid arguments or an unknown server.
pub suberror SearchError {
  SearchError(String)
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
      // Ranking reads the whole query; messages echo a bounded line of it.
      let shown = one_line(query, MaxQueryEchoChars)
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
/// `text` on one line, at most `limit` characters, marked when cut: line breaks
/// and tabs become spaces and other control characters are dropped, so echoed
/// input cannot break the page's layout.
fn one_line(text : String, limit : Int32) -> String {
  let line = StringBuilder()
  for ch in text {
    match ch {
      '\n' | '\r' | '\t' => line.write_char(' ')
      '\u{00}'..<='\u{1F}' | '\u{7F}' => ()
      _ => line.write_char(ch)
    }
  }
  let line = line.to_string().trim()
  if line.char_length() <= limit {
    line.to_owned()
  } else {
    "\{String::from_iter(line.iter().take(limit))}…"
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
/// `source`'s instructions as a page opens with them, or `None` when it sent
/// none.
fn instructions_of(source : Source) -> String? {
  guard source.instructions is Some(text) && !text.is_blank() else {
    return None
  }
  Some(text.trim().to_owned())
}

///|
/// One tool as a page shows it: server and name, description, and the JSON
/// Schema of its arguments and, when the server declares one, of its result's
/// `data`.
fn render_entry(entry : Entry) -> String {
  let result = match entry.tool.output_schema {
    Some(output) => "\nResult `data` schema: \{output.stringify()}"
    None => ""
  }
  "\n\n## \{entry.server} / \{entry.tool.name}\n\{entry.tool.description.trim()}\nArguments schema: \{entry.tool.input_schema.stringify()}\{result}"
}

///|
/// One tool when its shapes do not fit what is left of a page: its server,
/// name, and description, with its schemas left to the page's records.
fn brief_entry(entry : Entry) -> String {
  "\n\n## \{entry.server} / \{entry.tool.name}\n\{entry.tool.description.trim()}\nIts schemas do not fit this page: read `input_schema` and `output_schema` from this page's `tools`."
}

///|
/// The ways a page can show one tool, the fullest first: with its schemas,
/// then without.
fn renderings(entry : Entry) -> Array[String] {
  [render_entry(entry), brief_entry(entry)]
}

///|
/// How a page with tools closes: the call form.
const FooterNote : String = "\n\nCall one from the same script with `@mcp.call(server, tool, arguments)`, where `arguments` matches its arguments schema. `result.data` is `Json?`: match it."

///|
/// The page of `matches` starting at `offset`: at most `limit` whole entries
/// whose text fits `MaxTextChars`, and where the next page starts. Each entry
/// takes its fullest rendering that fits; a page always shows at least one, in
/// its briefest rendering if nothing fits. `opening` comes before the heading
/// and `closing` after the entries.
fn render(
  opening : String,
  heading : String,
  matches : Array[Entry],
  offset : Int32,
  limit : Int32,
  closing : String,
) -> (String, Array[Entry], Int32?) {
  let out = StringBuilder()
  out.write_string(opening)
  out.write_string(heading)
  let fixed = opening + heading + closing + FooterNote
  // Room kept for the paging line, which comes after the entries.
  let budget = MaxTextChars - fixed.length() - 200
  let listed : Array[Entry] = []
  let mut used = 0
  for entry in matches[offset:] {
    if listed.length() == limit {
      break
    }
    let options = renderings(entry)
    let fitting = options
      .iter()
      .find_first(text => used + text.length() <= budget)
    let text = match fitting {
      Some(text) => text
      None if listed.is_empty() => options[options.length() - 1]
      None => break
    }
    out.write_string(text)
    listed.push(entry)
    used += text.length()
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
/// stay under the text cap.
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
  match self.select(query, server) {
    Found(heading~, matches~) if offset >= matches.length() =>
      raise SearchError(
        "`offset` \{offset} is past the last result; \{heading}",
      )
    Found(heading~, matches~) => {
      let (text, tools, next_offset) = render(
        opening, heading, matches, offset, limit, closing,
      )
      { text, instructions, tools, total: matches.length(), next_offset, }
    }
    // No match has no pages after the first either.
    Empty(message) if offset > 0 =>
      raise SearchError(
        "`offset` \{offset} is past the last result; \{message}",
      )
    Empty(message) =>
      {
        text: opening + message + closing,
        instructions,
        tools: [],
        total: 0,
        next_offset: None,
      }
  }
}
