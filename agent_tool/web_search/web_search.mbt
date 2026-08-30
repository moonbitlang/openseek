///|
/// Default endpoint base: DeepSeek's Anthropic-compatible Messages API, `/v1`
/// included (`/messages` is appended). This is NOT the chat-completions base
/// the agent's own client talks to (`https://api.deepseek.com`), so the tool
/// deliberately does not reuse `--api-url` — only the API key is shared.
const DefaultBaseUrl : String = "https://api.deepseek.com/anthropic/v1"

///|
/// Default Anthropic-format model name for the auxiliary search call. The
/// flash tier: the call exists to trigger native search and return result
/// blocks, not to think.
const DefaultSearchModel : String = "deepseek-v4-flash"

///|
/// `anthropic-version` header value sent on every request.
const AnthropicVersion : String = "2023-06-01"

///|
/// Upper bound on generated tokens for the Messages request. The searching
/// model's prose is discarded (only result blocks and citations survive), so
/// this caps cost, not quality.
const DefaultMaxTokens : Int = 4096

///|
/// Maximum native `web_search` server-tool uses per request.
const DefaultMaxUses : Int = 5

///|
/// Upper bound on sources returned to the model. Owned by this consumer, not
/// the provider: the model just asks a question; the product controls how
/// much context comes back.
const DefaultMaxResults : Int = 8

///|
/// Wall bound on one whole search call. Server-side search runs a model turn
/// with up to `max_uses` searches, so it is bounded like a chat request, not
/// like a plain HTTP fetch.
const DefaultTimeoutMs : Int = 120_000

///|
/// Input cap: a query is a question, not a document.
const MaxQueryChars : Int = 2_000

///|
/// One citeable source parsed out of a `web_search_tool_result` block.
/// `snippet` is joined in from a `text` block's citations by URL — the result
/// items themselves typically carry none.
priv struct WebSource {
  url : String
  title : String?
  snippet : String?
  published_at : String?
}

///|
/// Normalized search outcome: sources already deduped and cut to the result
/// cap, plus whether that cut dropped anything.
priv struct SearchOutcome {
  sources : Array[WebSource]
  truncated : Bool
}

///|
/// A search failure with a clean model-facing message (no source-location
/// prefix), surfaced through the tool-error path.
priv suberror SearchFailure {
  SearchFailure(String)
}

///|
impl Show for SearchFailure with fn output(
  self : SearchFailure,
  logger : &Logger,
) -> Unit {
  let SearchFailure(message) = self
  logger.write_string(message)
}

///|
/// Tool definition for `web_search`: search the web through DeepSeek's native
/// server-side search and return a bounded, citeable source list.
///
/// ## Arguments
/// - `query` (string, required): the search query; non-blank, at most
///   `MaxQueryChars` characters.
///
/// ## Result
/// - `Respond` with a markdown source list (`- [title](url) — snippet
///   (published)`), a refine-the-query note when the result cap dropped
///   sources, and a standing cite-your-sources instruction.
/// - Malformed arguments, provider errors, and timeouts produce
///   `Respond(is_error=true)` so the model can rephrase or move on — a failed
///   search never breaks the turn.
///
/// The backend is one DeepSeek Anthropic-compatible Messages call carrying the
/// native `web_search_20250305` server tool: each search costs a model turn,
/// but returns structured result blocks; absence of those blocks is an error
/// rather than a prose-scraping fallback. Only the DeepSeek API key is shared
/// with the agent's own client — the endpoint base is separate (see
/// `DefaultBaseUrl`), so `--api-url` proxies are not consulted.
pub fn definition(
  api_key~ : String,
  base_url? : String = DefaultBaseUrl,
  model? : String = DefaultSearchModel,
  max_results? : Int = DefaultMaxResults,
  max_uses? : Int = DefaultMaxUses,
  max_tokens? : Int = DefaultMaxTokens,
  timeout_ms? : Int = DefaultTimeoutMs,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="web_search",
    concurrent_safe=true,
    description=(
      #|Search the web for current information. Returns a list of source URLs with titles and snippets. Use it when the answer may have changed since your training data or lives outside this workspace — current releases, external documentation, error messages you do not recognize. Independent questions? Issue SEVERAL web_search calls in the same step — they run concurrently. Cite the relevant source URLs as markdown links in your answer.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "query": { "type": "string", "description": "The search query." },
      },
      "required": ["query"],
      "additionalProperties": false,
    }),
    execute=Async(arguments => {
      execute(
        api_key, base_url, model, max_results, max_uses, max_tokens, timeout_ms,
        arguments,
      )
    }),
  )
}

///|
async fn execute(
  api_key : String,
  base_url : String,
  model : String,
  max_results : Int,
  max_uses : Int,
  max_tokens : Int,
  timeout_ms : Int,
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "query": String(query), .. } && !query.is_blank() else {
    return @agent_tool.respond(
      "error: web_search requires a non-empty string `query`",
      is_error=true,
    )
  }
  guard query.length() <= MaxQueryChars else {
    return @agent_tool.respond(
      "error: web_search query exceeds \{MaxQueryChars} chars — ask one focused question",
      is_error=true,
    )
  }
  let outcome = perform_search(
    api_key~,
    base_url~,
    model~,
    max_results~,
    max_uses~,
    max_tokens~,
    timeout_ms~,
    query,
  ) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error =>
      return @agent_tool.respond(
        "error: web_search failed: \{error}",
        is_error=true,
        brief=failure_brief(query),
      )
  }
  @agent_tool.respond(
    format_output(outcome),
    brief=success_brief(query, outcome.sources.length()),
  )
}

///|
/// Briefs cap the query segment FIRST (well under `brief_line`'s overall
/// 72-char cap), so the discriminating suffix — `· N source(s)` vs `(failed)`
/// — survives for long queries instead of both briefs truncating identically.
fn success_brief(query : String, count : Int) -> String {
  let capped = @agent_tool.brief_line(query, limit=40)
  @agent_tool.brief_line("web_search \{capped} · \{count} source(s)")
}

///|
fn failure_brief(query : String) -> String {
  let capped = @agent_tool.brief_line(query, limit=40)
  @agent_tool.brief_line("web_search \{capped} (failed)")
}

///|
/// Escape the square brackets markdown link labels delimit, so a
/// provider-controlled title cannot break the `[label](url)` shape.
fn markdown_label(text : String) -> String {
  text.replace_all(old="[", new="\\[").replace_all(old="]", new="\\]")
}

///|
/// One search: POST the Messages request with the native server tool, bounded
/// by `timeout_ms`, and map the response to a normalized outcome.
async fn perform_search(
  api_key~ : String,
  base_url~ : String,
  model~ : String,
  max_results~ : Int,
  max_uses~ : Int,
  max_tokens~ : Int,
  timeout_ms~ : Int,
  query : String,
) -> SearchOutcome {
  let body : Json = {
    "model": model.to_json(),
    "max_tokens": max_tokens.to_json(),
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Perform a web search for the query: \{query}".to_json(),
          },
        ],
      },
    ],
    "tools": [
      {
        "type": "web_search_20250305",
        "name": "web_search",
        "max_uses": max_uses.to_json(),
      },
    ],
  }
  // Official DeepSeek expects `x-api-key`; an Anthropic-compatible proxy may
  // expect `Authorization: Bearer` — send both so either resolves.
  let attempt = () => {
    @http.post("\{base_url}/messages", body, headers={
      "Content-Type": "application/json",
      "X-Api-Key": api_key,
      "Authorization": "Bearer \{api_key}",
      "Anthropic-Version": AnthropicVersion,
    })
  }
  guard @async.with_timeout_opt(timeout_ms, attempt) is Some((resp, data)) else {
    raise SearchFailure("web search timed out after \{timeout_ms}ms")
  }
  let text = data.text()
  guard resp.code >= 200 && resp.code < 300 else {
    raise SearchFailure(
      "DeepSeek search API error \{resp.code}: \{error_detail(text)}",
    )
  }
  let payload = @json.parse(text) catch {
    _ => raise SearchFailure("DeepSeek search response is not JSON")
  }
  parse_search_response(payload, max_results~)
}

///|
/// Best-effort human message from an error body: the Anthropic-style
/// `error.message` (or flat `error`/`message` string) when present, else the
/// raw body capped to one short line — gateways return HTML pages that must
/// not flood the transcript.
fn error_detail(text : String) -> String {
  let parsed = @json.parse(text) catch {
    _ => return @agent_tool.brief_line(text, limit=200)
  }
  match parsed {
    { "error": { "message": String(message), .. }, .. } => message
    { "error": String(message), .. } => message
    { "message": String(message), .. } => message
    _ => @agent_tool.brief_line(text, limit=200)
  }
}

///|
/// Map a DeepSeek Anthropic Messages response to a normalized outcome. Walks
/// `web_search_tool_result` blocks for citeable `web_search_result` items,
/// joins each to its citation excerpt as `snippet` (the excerpt lives in a
/// separate `text` block's `citations[]`, keyed by URL, first occurrence
/// wins), dedupes by URL (a `max_uses > 1` request can surface the same URL
/// across searches), and cuts to `max_results`. Raises when native search
/// produced no result block at all — that is a provider misfire, not an empty
/// result.
fn parse_search_response(
  payload : Json,
  max_results~ : Int,
) -> SearchOutcome raise {
  guard payload is { "content": Array(blocks), .. } else {
    raise SearchFailure("DeepSeek search response has no content blocks")
  }
  // url → cited_text from every text block's citations; the snippet source.
  let snippets : Map[String, String] = Map([])
  for block in blocks {
    guard block is { "type": "text", .. } else { continue }
    guard block is { "citations": Array(citations), .. } else { continue }
    for citation in citations {
      guard citation is { "url": String(url), "cited_text": String(cited), .. } &&
        url != "" &&
        cited != "" else {
        continue
      }
      if !snippets.contains(url) {
        snippets[url] = cited
      }
    }
  }
  let mut found_result_block = false
  let sources : Array[WebSource] = []
  let error_codes : Array[String] = []
  let mut dropped = false
  for block in blocks {
    guard block is { "type": "web_search_tool_result", .. } else { continue }
    found_result_block = true
    // A server-side search failure arrives as an OBJECT content
    // (`{"type":"web_search_tool_result_error","error_code":...}`) instead of
    // the item array. Collect the code rather than skipping, so an all-error
    // response raises below instead of rendering as a clean "No results
    // found." the model would trust.
    if block is { "content": { .. } as error_content, .. } {
      let code = match error_content {
        { "error_code": String(code), .. } => code
        _ => "unknown error"
      }
      error_codes.push(code)
      continue
    }
    guard block is { "content": Array(items), .. } else { continue }
    for item in items {
      guard item is { "type": "web_search_result", "url": String(url), .. } &&
        url != "" else {
        continue
      }
      if sources.iter().any(source => source.url == url) {
        continue
      }
      if sources.length() >= max_results {
        dropped = true
        continue
      }
      let title = match item {
        { "title": String(title), .. } if title != "" => Some(title)
        _ => None
      }
      let published_at = match item {
        { "page_age": String(age), .. } if age != "" => Some(age)
        _ => None
      }
      sources.push({ url, title, snippet: snippets.get(url), published_at, })
    }
  }
  guard found_result_block else {
    raise SearchFailure(
      "DeepSeek returned no web_search_tool_result blocks; the request may not have triggered native web search",
    )
  }
  // Partial failures (one errored search among successful ones) still return
  // the gathered sources; only an all-error response is a tool error.
  if sources.is_empty() && !error_codes.is_empty() {
    raise SearchFailure(
      "DeepSeek native web search failed server-side: \{error_codes.join(", ")}",
    )
  }
  { sources, truncated: dropped, }
}

///|
/// Format a search outcome as one model-facing text block: a markdown source
/// list with snippet and date metadata (or `No results found.`), a
/// refine-the-query note when truncated, and a standing cite-your-sources
/// instruction.
fn format_output(outcome : SearchOutcome) -> String {
  let parts : Array[String] = []
  if outcome.sources.length() > 0 {
    let lines = [
      for source in outcome.sources => {
        // Provider-controlled text: collapse to one line and cap each field
        // (only the source COUNT is bounded upstream), and escape the square
        // brackets markdown link labels delimit — otherwise a title or
        // excerpt can break the `- [label](url) — meta` line shape or flood
        // the transcript.
        let label = markdown_label(
          match source.title {
            Some(title) => @agent_tool.brief_line(title, limit=120)
            None => host_label(source.url)
          },
        )
        let meta : Array[String] = []
        if source.snippet is Some(snippet) {
          meta.push(@agent_tool.brief_line(snippet, limit=300))
        }
        if source.published_at is Some(published) {
          let capped = @agent_tool.brief_line(published, limit=40)
          meta.push("(\{capped})")
        }
        let suffix = if meta.length() > 0 {
          " — \{meta.join(" ")}"
        } else {
          ""
        }
        "- [\{label}](\{source.url})\{suffix}"
      }
    ]
    parts.push("Sources:\n\{lines.join("\n")}")
  } else {
    parts.push("No results found.")
  }
  if outcome.truncated {
    parts.push(
      "(Showing the first \{outcome.sources.length()} sources. Refine the query for more.)",
    )
  }
  parts.push("Cite the relevant URLs above as markdown links in your answer.")
  parts.join("\n\n")
}

///|
/// Display label for a title-less source: the URL's hostname (scheme,
/// userinfo, port, and path stripped), or the raw URL when it does not parse
/// as one — never let a malformed provider URL throw out of pure formatting.
fn host_label(url : String) -> String {
  guard url =~ (re"^[A-Za-z][A-Za-z0-9+.\-]*://", after~) else { return url }
  let mut authority = after
  // Path/query/fragment start at the first delimiter; userinfo ends at the
  // first `@` (a host cannot contain one); the port starts at the first `:`
  // of what remains. Each step narrows the view, so the order matters.
  if authority =~ (re"[/?#]", before~) {
    authority = before
  }
  if authority =~ (re"@", after~) {
    authority = after
  }
  // A bracketed IPv6 literal is the whole host; the port (if any) follows the
  // closing bracket, so the first-`:` port strip below must not see it.
  if authority =~ (re"^\[", after~) {
    guard after =~ (re"\]", before~) else { return url }
    return "[\{before}]"
  }
  if authority =~ (re":", before~) {
    authority = before
  }
  if authority.is_empty() {
    url
  } else {
    authority.to_owned()
  }
}

///|
test "host_label extracts the hostname and falls back to the raw string" {
  assert_eq(host_label("https://example.com/a/b?q=1"), "example.com")
  assert_eq(host_label("https://user:pw@example.org:8443/x"), "example.org")
  assert_eq(host_label("http://localhost:8080"), "localhost")
  assert_eq(host_label("not a url"), "not a url")
  assert_eq(host_label("https:///path"), "https:///path")
}

///|
/// A canned Anthropic-style Messages response with two searched sources, one
/// carrying a citation excerpt, plus a duplicate result item to exercise the
/// URL dedup.
fn sample_response() -> Json {
  {
    "content": [
      {
        "type": "server_tool_use",
        "id": "srvtoolu_1",
        "name": "web_search",
        "input": { "query": "moonbit language" },
      },
      {
        "type": "web_search_tool_result",
        "tool_use_id": "srvtoolu_1",
        "content": [
          {
            "type": "web_search_result",
            "url": "https://example.com/a",
            "title": "Example A",
            "page_age": "January 5, 2026",
          },
          { "type": "web_search_result", "url": "https://example.org/b" },
          {
            "type": "web_search_result",
            "url": "https://example.com/a",
            "title": "Example A duplicate",
          },
        ],
      },
      {
        "type": "text",
        "text": "According to Example A, MoonBit is fast.",
        "citations": [
          {
            "type": "citations_web_search_result_location",
            "url": "https://example.com/a",
            "cited_text": "MoonBit is a fast language.",
          },
        ],
      },
    ],
  }
}

///|
test "parse_search_response joins citations, dedupes, and formats" {
  let outcome = parse_search_response(sample_response(), max_results=8)
  assert_eq(outcome.sources.length(), 2)
  assert_false(outcome.truncated)
  let rendered = format_output(outcome)
  assert_eq(
    rendered,
    (
      #|Sources:
      #|- [Example A](https://example.com/a) — MoonBit is a fast language. (January 5, 2026)
      #|- [example.org](https://example.org/b)
      #|
      #|Cite the relevant URLs above as markdown links in your answer.
    ),
  )
}

///|
test "parse_search_response cuts to max_results and flags the cut" {
  let outcome = parse_search_response(sample_response(), max_results=1)
  assert_eq(outcome.sources.length(), 1)
  assert_true(outcome.truncated)
  let rendered = format_output(outcome)
  assert_true(
    rendered.contains(
      "(Showing the first 1 sources. Refine the query for more.)",
    ),
  )
}

///|
test "parse_search_response treats a missing result block as a provider error" {
  let _ = parse_search_response(
    { "content": [{ "type": "text", "text": "just prose" }] },
    max_results=8,
  ) catch {
    error => {
      assert_true("\{error}".contains("no web_search_tool_result blocks"))
      return
    }
  }
  fail("expected the parse to raise")
}

///|
test "format_output renders the empty outcome as no results" {
  let rendered = format_output({ sources: [], truncated: false, })
  assert_true(rendered.contains("No results found."))
}

///|
test "web_search definition exposes the expected name and schema shape" {
  let definition = definition(api_key="k")
  assert_eq(definition.name, "web_search")
  assert_true(definition.is_concurrent_safe())
  guard definition.schema is JsonSchema({ "required": ["query"], .. }) else {
    fail("expected query to be required")
  }
  guard definition.execute is Async(_) else {
    fail("expected an async executor")
  }
}

///|
test "error_detail extracts the provider message and caps raw bodies" {
  assert_eq(
    error_detail("{\"error\":{\"type\":\"auth\",\"message\":\"invalid key\"}}"),
    "invalid key",
  )
  assert_eq(error_detail("{\"error\":\"flat message\"}"), "flat message")
  let capped = error_detail("<html>" + "x".repeat(400) + "</html>")
  assert_true(capped.length() <= 201)
  assert_true(capped.has_suffix("…"))
}

///|
test "parse_search_response raises on an all-error result block" {
  let _ = parse_search_response(
    {
      "content": [
        {
          "type": "web_search_tool_result",
          "content": {
            "type": "web_search_tool_result_error",
            "error_code": "max_uses_exceeded",
          },
        },
      ],
    },
    max_results=8,
  ) catch {
    error => {
      assert_true("\{error}".contains("failed server-side: max_uses_exceeded"))
      return
    }
  }
  fail("expected the error block to raise")
}

///|
test "parse_search_response keeps sources from a partially errored response" {
  let outcome = parse_search_response(
    {
      "content": [
        {
          "type": "web_search_tool_result",
          "content": {
            "type": "web_search_tool_result_error",
            "error_code": "too_many_requests",
          },
        },
        {
          "type": "web_search_tool_result",
          "content": [
            {
              "type": "web_search_result",
              "url": "https://example.com/a",
              "title": "Example A",
            },
          ],
        },
      ],
    },
    max_results=8,
  )
  assert_eq(outcome.sources.length(), 1)
  assert_false(outcome.truncated)
}

///|
test "host_label keeps bracketed IPv6 hosts whole" {
  assert_eq(host_label("https://[::1]:8080/x"), "[::1]")
  assert_eq(host_label("http://[2001:db8::1]/path"), "[2001:db8::1]")
  assert_eq(host_label("https://[broken"), "https://[broken")
}

///|
test "format_output collapses, caps, and escapes provider text" {
  let outcome : SearchOutcome = {
    sources: [
      {
        url: "https://example.com/a",
        title: Some("Release [v2.0] notes"),
        snippet: Some("line one\nline two"),
        published_at: None,
      },
    ],
    truncated: false,
  }
  let rendered = format_output(outcome)
  assert_true(
    rendered.contains(
      "- [Release \\[v2.0\\] notes](https://example.com/a) — line one line two",
    ),
  )
}

///|
test "format_output caps runaway snippets" {
  let outcome : SearchOutcome = {
    sources: [
      {
        url: "https://example.com/a",
        title: None,
        snippet: Some("s".repeat(1000)),
        published_at: None,
      },
    ],
    truncated: false,
  }
  let rendered = format_output(outcome)
  // The 300-char field cap (plus ellipsis) keeps the whole render bounded.
  assert_true(rendered.length() < 500)
  assert_true(rendered.contains("…"))
}

///|
test "success and failure briefs stay distinguishable for long queries" {
  let long_query = "q".repeat(80)
  let ok = success_brief(long_query, 8)
  let bad = failure_brief(long_query)
  assert_true(ok != bad)
  assert_true(ok.contains("source(s)"))
  assert_true(bad.contains("(failed)"))
}
