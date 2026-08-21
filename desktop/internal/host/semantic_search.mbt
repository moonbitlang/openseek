// Connection-owned workspace semantic search. One actor serializes session
// state while each generation runs its own moongrep scan (via a bundled
// moongrep binary or `moonx moonbit-community/moongrep --`) in a cancellable
// task. The text-search service owns the sibling ripgrep mode; both share the
// Search panel's generation/cancel contract.

///|
const MaxSemanticSearchResults : Int = 20000

///|
const MaxSemanticSearchCancellationFrontiers : Int = 128

///|
const MaxSemanticSearchStderrBytes : Int = 1000000

///|
const MaxSemanticSearchErrorMessageUnits : Int = 1000

///|
priv struct ParsedSemanticContextLine {
  line : Int
  text : String
  is_match : Bool
}

///|
priv struct ParsedSemanticMatch {
  path : String
  rule_id : String
  description : String?
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
  matched_source : String
  source_context : Array[ParsedSemanticContextLine]
}

///|
priv enum SemanticSearchOutcome {
  SemanticSearchFinished(SearchSemanticReply)
  SemanticSearchFailed(String)
}

///|
priv struct RunningSemanticSearch {
  generation : Int
  root : String
  reply : @async.Queue[SearchSemanticReply]
  task : @async.Task[Unit]
}

///|
priv struct SemanticSearchCancellationFrontiers {
  values : Map[String, Int]
  order : Array[String]
}

///|
fn SemanticSearchCancellationFrontiers::new() -> SemanticSearchCancellationFrontiers {
  { values: Map([]), order: [] }
}

///|
fn SemanticSearchCancellationFrontiers::get(
  self : SemanticSearchCancellationFrontiers,
  session_key : String,
) -> Int {
  self.values.get(session_key).unwrap_or(-1)
}

///|
fn SemanticSearchCancellationFrontiers::record(
  self : SemanticSearchCancellationFrontiers,
  session_key : String,
  generation : Int,
) -> Unit {
  self.values[session_key] = self.get(session_key).max(generation)
  self.order.retain(key => key != session_key)
  self.order.push(session_key)
  if self.order.length() > MaxSemanticSearchCancellationFrontiers {
    let oldest = self.order.remove(0)
    self.values.remove(oldest)
  }
}

///|
priv enum SemanticSearchRequest {
  Search(
    command~ : String?,
    root~ : @pathx.Absolute,
    payload~ : SearchSemanticPayload,
    reply~ : @async.Queue[SearchSemanticReply]
  )
  Cancel(session_key~ : String, generation~ : Int, reply~ : @async.Queue[Unit])
  Finished(
    session_key~ : String,
    generation~ : Int,
    outcome~ : SemanticSearchOutcome
  )
}

///|
priv struct SemanticSearchService {
  requests : @async.Queue[SemanticSearchRequest]
}

///|
fn SemanticSearchService::new() -> SemanticSearchService {
  { requests: Queue(kind=Blocking(64)) }
}

///|
fn empty_semantic_search_reply(
  root : String,
  generation : Int,
  cancelled? : Bool = false,
  error? : SemanticSearchError,
) -> SearchSemanticReply {
  {
    root,
    generation,
    matches: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    cancelled,
    error,
  }
}

///|
async fn SemanticSearchService::search(
  self : SemanticSearchService,
  command : String?,
  root : @pathx.Absolute,
  payload : SearchSemanticPayload,
) -> SearchSemanticReply {
  let reply : @async.Queue[SearchSemanticReply] = Queue(kind=Blocking(1))
  self.requests.put(Search(command~, root~, payload~, reply~))
  reply.get()
}

///|
async fn SemanticSearchService::cancel(
  self : SemanticSearchService,
  session_key : String,
  generation : Int,
) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.requests.put(Cancel(session_key~, generation~, reply~))
  reply.get()
}

///|
async fn cancel_running_semantic_search(
  running : RunningSemanticSearch,
  root : String,
) -> Unit {
  running.task.cancel()
  running.reply.put(
    empty_semantic_search_reply(root, running.generation, cancelled=true),
  ) catch {
    _ => ()
  }
}

///|
async fn SemanticSearchService::run(self : SemanticSearchService) -> Unit {
  @async.with_task_group(group => {
    let running : Map[String, RunningSemanticSearch] = Map([])
    let cancelled_through = SemanticSearchCancellationFrontiers::new()
    for ;; {
      match self.requests.get() {
        Search(command~, root~, payload~, reply~) => {
          let session_key = payload.session_key
          let reply_root = root.resource_path()
          if session_key.is_blank() {
            reply.put(
              empty_semantic_search_reply(reply_root, payload.generation, error={
                code: "invalid_request",
                message: "Search session key is empty.",
              }),
            )
            continue
          }
          if cancelled_through.get(session_key) >= payload.generation {
            reply.put(
              empty_semantic_search_reply(
                reply_root,
                payload.generation,
                cancelled=true,
              ),
            )
            continue
          }
          if running.get(session_key) is Some(previous) {
            if payload.generation <= previous.generation {
              reply.put(
                empty_semantic_search_reply(
                  reply_root,
                  payload.generation,
                  cancelled=true,
                ),
              )
              continue
            }
            cancel_running_semantic_search(previous, previous.root)
            running.remove(session_key)
          }
          let generation = payload.generation
          let task = group.spawn(no_wait=true, allow_failure=true, () => {
            let outcome = SemanticSearchFinished(
              run_semantic_search(command, root, payload),
            ) catch {
              _ if @async.is_being_cancelled() => return
              error => SemanticSearchFailed("Semantic search failed: \{error}")
            }
            self.requests.put(Finished(session_key~, generation~, outcome~))
          })
          running[session_key] = { generation, root: reply_root, reply, task }
        }
        Cancel(session_key~, generation~, reply~) => {
          cancelled_through.record(session_key, generation)
          if running.get(session_key) is Some(current) &&
            current.generation <= generation {
            cancel_running_semantic_search(current, current.root)
            running.remove(session_key)
          }
          reply.put(())
        }
        Finished(session_key~, generation~, outcome~) => {
          guard running.get(session_key) is Some(current) &&
            current.generation == generation else {
            continue
          }
          running.remove(session_key)
          let root = current.root
          match outcome {
            SemanticSearchFinished(result) => current.reply.put(result)
            SemanticSearchFailed(message) =>
              current.reply.put(
                empty_semantic_search_reply(root, generation, error={
                  code: "search_failed",
                  message,
                }),
              )
          }
        }
      }
    }
  })
}

///|
/// moongrep consumes the workspace root from the process working directory, so
/// `scan .` emits `./relative/path.mbt` rows that this function rebases into
/// slash-separated workspace-relative paths, matching text-search results.
fn normalize_semantic_path(path : String) -> String {
  let path = if @sysplatform.win32 || @sysplatform.win64 {
    path.replace_all(old="\\", new="/")
  } else {
    path
  }
  if path.has_prefix("./") {
    path[2:].to_owned()
  } else {
    path
  }
}

///|
/// moongrep emits source text verbatim, so Windows CRLF files carry a
/// trailing `\r` on every line. Normalize to `\n` line endings for display.
fn normalize_semantic_source(text : String) -> String {
  if text.contains("\r") {
    text.replace_all(old="\r\n", new="\n")
  } else {
    text
  }
}

///|
fn semantic_search_args(
  command : String,
  payload : SearchSemanticPayload,
) -> Array[String] {
  let args : Array[String] = if command == "moonx" ||
    command.has_suffix("/moonx") ||
    command.has_suffix("\\moonx") {
    ["moonbit-community/moongrep", "--"]
  } else {
    []
  }
  args.push("scan")
  if !payload.query.is_empty() {
    args.append(["--pattern", payload.query])
  }
  if !payload.rules_dir.is_empty() {
    args.append(["--rules", payload.rules_dir])
  }
  if payload.enable_builtin_rules {
    args.push("--enable-builtin-rules")
  }
  args.append(["--output-json"])
  args
}

///|
fn nested_semantic_object(
  fields : Map[String, Json],
  key : String,
) -> Map[String, Json]? {
  match fields.get(key) {
    Some(Object(value)) => Some(value)
    _ => None
  }
}

///|
fn semantic_number(fields : Map[String, Json], key : String) -> Int? {
  match fields.get(key) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn parse_semantic_context_line(line : Json) -> ParsedSemanticContextLine? {
  guard line is Object(fields) &&
    semantic_number(fields, "line") is Some(line_number) &&
    fields.get("text") is Some(String(text)) &&
    fields.get("is_match") is Some(is_match) else {
    return None
  }
  Some({
    line: line_number,
    text: text.trim_end(chars="\r").to_owned(),
    is_match: match is_match {
      True => true
      False => false
      _ => return None
    },
  })
}

///|
fn parse_moongrep_match(line : String) -> ParsedSemanticMatch? {
  let json = @json.parse(line) catch { _ => return None }
  guard json is Object(message) &&
    message.get("file") is Some(String(path)) &&
    message.get("rule_id") is Some(String(rule_id)) &&
    nested_semantic_object(message, "range") is Some(range) &&
    nested_semantic_object(range, "start") is Some(start) &&
    nested_semantic_object(range, "end") is Some(end) &&
    semantic_number(start, "line") is Some(start_line) &&
    semantic_number(start, "column") is Some(start_column) &&
    semantic_number(end, "line") is Some(end_line) &&
    semantic_number(end, "column") is Some(end_column) &&
    message.get("matched_source") is Some(String(matched_source)) else {
    return None
  }
  let description = match message.get("description") {
    Some(String(value)) if !value.is_empty() => Some(value)
    _ => None
  }
  let source_context : Array[ParsedSemanticContextLine] = []
  guard message.get("source_context") is Some(Array(context_lines)) else {
    return None
  }
  for raw_line in context_lines {
    // A malformed context row can be skipped without discarding the hit; the
    // match range and text are the primary result.
    if parse_semantic_context_line(raw_line) is Some(parsed_line) {
      source_context.push(parsed_line)
    }
  }
  Some({
    path: normalize_semantic_path(path),
    rule_id,
    description,
    start_line,
    start_column,
    end_line,
    end_column,
    matched_source,
    source_context,
  })
}

///|
fn project_semantic_match(
  parsed : ParsedSemanticMatch,
) -> SemanticSearchHit {
  {
    path: parsed.path,
    rule_id: parsed.rule_id,
    description: parsed.description,
    start_line: parsed.start_line,
    start_column: parsed.start_column,
    end_line: parsed.end_line,
    end_column: parsed.end_column,
    matched_source: normalize_semantic_source(parsed.matched_source),
    source_context: parsed.source_context.map(line => {
      line: line.line,
      text: line.text,
      is_match: line.is_match,
    }),
  }
}

///|
fn semantic_search_error(stderr : String) -> (String, String) {
  let detail = stderr.trim().to_owned()
  let lower = detail.to_lower()
  let code = if lower.contains("not a valid moonbit expression") ||
    lower.contains("lexical errors") ||
    lower.contains("is not a valid") {
    "invalid_pattern"
  } else if lower.contains("missing required --rules") ||
    lower.contains("missing required rule") {
    "invalid_request"
  } else if lower.contains("permission denied") ||
    lower.contains("access is denied") {
    "permission_denied"
  } else {
    "search_failed"
  }
  let message = first_semantic_diagnostic(detail)
  (code, bounded_semantic_error_message(message))
}

///|
fn first_semantic_diagnostic(detail : String) -> String {
  for raw_line in detail.split("\n") {
    let line = raw_line.trim().to_owned()
    if !line.is_empty() {
      return line
    }
  }
  "moongrep could not complete the search."
}

///|
fn bounded_semantic_error_message(message : String) -> String {
  guard message.length() > MaxSemanticSearchErrorMessageUnits else {
    return message
  }
  message[:MaxSemanticSearchErrorMessageUnits].to_owned() + "…"
}

///|
async fn run_semantic_search(
  command : String?,
  root : @pathx.Absolute,
  payload : SearchSemanticPayload,
) -> SearchSemanticReply {
  let reply_root = root.resource_path()
  let native_root = root.to_string()
  if payload.query.is_empty() &&
    payload.rules_dir.is_empty() &&
    !payload.enable_builtin_rules {
    return empty_semantic_search_reply(reply_root, payload.generation, error={
      code: "invalid_request",
      message: "Provide a structural code pattern, a rules directory, or enable built-in rules.",
    })
  }
  guard command is Some(command) else {
    return empty_semantic_search_reply(reply_root, payload.generation, error={
      code: "moongrep_unavailable",
      message: "This SeekMoon installation does not include a semantic-search provider.",
    })
  }
  let directory = @fs.opendir(native_root) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      return empty_semantic_search_reply(reply_root, payload.generation, error={
        code: if "\{error}".to_lower().contains("permission") {
          "permission_denied"
        } else {
          "search_failed"
        },
        message: "Cannot read workspace: \{error}",
      })
  }
  directory.close()
  let max_results = payload.max_results.max(0).min(MaxSemanticSearchResults)
  let (stdout_reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  // Provide a closed stdin pipe so the Windows spawn does not fall back to
  // GetStdHandle, which returns NULL (not INVALID_HANDLE_VALUE) when the
  // process has no console — the same workaround text search uses.
  let (stdin_reader, stdin_writer) = @process.write_to_process()
  stdin_writer.close()
  @async.with_task_group(group => {
    let process = @process.spawn(
      group,
      command,
      semantic_search_args(command, payload),
      inherit_env=true,
      stdin=stdin_reader,
      stdout=child_stdout,
      stderr=child_stderr,
      cwd=native_root,
      no_console_window=true,
      cancel_handler=@process.hard_cancel(),
      no_wait=true,
    ) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        stdout_reader.close()
        stderr_reader.close()
        return empty_semantic_search_reply(reply_root, payload.generation, error={
          code: "moongrep_unavailable",
          message: "Cannot start semantic search: \{error}",
        })
      }
    }
    let stderr_task = group.spawn(() => {
      defer stderr_reader.close()
      let retained = @buffer.Buffer(size_hint=4096)
      let mut retained_bytes = 0
      for ;; {
        guard stderr_reader.read_some(max_len=4096) is Some(chunk) else {
          break
        }
        if retained_bytes < MaxSemanticSearchStderrBytes {
          let length = chunk
            .length()
            .min(MaxSemanticSearchStderrBytes - retained_bytes)
          retained.write_bytes(chunk[:length].to_owned())
          retained_bytes += length
        }
      }
      @utf8.decode_lossy(retained.contents())
    })
    let hits : Array[SemanticSearchHit] = []
    let files : Map[String, Bool] = Map([])
    let mut match_count = 0
    let mut limit_hit = false
    defer stdout_reader.close()
    for ;; {
      let line = stdout_reader.read_until("\n")
      guard line is Some(line) else { break }
      guard parse_moongrep_match(line) is Some(parsed) else { continue }
      if match_count >= max_results {
        limit_hit = true
        process.cancel()
        break
      }
      let hit = project_semantic_match(parsed)
      hits.push(hit)
      files[hit.path] = true
      match_count += 1
    }
    let exit_code = process.wait() catch {
      error if @async.is_being_cancelled() => raise error
      _ if limit_hit => 0
      _ => 2
    }
    let stderr = stderr_task.wait() catch { _ => "" }
    if exit_code != 0 {
      let (code, message) = semantic_search_error(stderr)
      return empty_semantic_search_reply(reply_root, payload.generation, error={
        code,
        message,
      })
    }
    {
      root: reply_root,
      generation: payload.generation,
      matches: hits,
      match_count,
      file_count: files.length(),
      limit_hit,
      cancelled: false,
      error: None,
    }
  })
}

///|
async fn search_semantic_op(
  state : HostState,
  service : SemanticSearchService,
  payload : SearchSemanticPayload,
) -> SearchSemanticReply {
  let root = WirePath::parse(payload.root).absolute
  let command = moongrep_command(state.executable)
  service.search(command, root, payload)
}

///|
async fn cancel_search_semantic_op(
  service : SemanticSearchService,
  payload : CancelSearchSemanticPayload,
) -> @protocol.EmptyReply {
  service.cancel(payload.session_key, payload.generation)
  Acknowledged
}

///|
test "semantic search builds moonx and bundled moongrep invocations" {
  let pattern : SearchSemanticPayload = {
    root: "/work",
    query: "inspect($(x:arg))",
    rules_dir: "",
    enable_builtin_rules: false,
    session_key: "sem:one",
    generation: 1,
    max_results: 20000,
  }
  assert_eq(semantic_search_args("moonx", pattern), [
    "moonbit-community/moongrep", "--", "scan", "--pattern", "inspect($(x:arg))",
    "--output-json",
  ])
  let rules : SearchSemanticPayload = {
    ..pattern,
    query: "",
    rules_dir: "/work/.moongrep/rules",
    enable_builtin_rules: true,
  }
  assert_eq(semantic_search_args("/opt/bin/moongrep", rules), [
    "scan", "--rules", "/work/.moongrep/rules", "--enable-builtin-rules",
    "--output-json",
  ])
}

///|
test "moongrep JSON rows project into protocol hits" {
  let json =
    #|{"file":"./src/main.mbt","rule_id":"inspect($(x:arg))","description":"Anonymous CLI pattern.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":26}},"matched_source":"inspect(1, content=\"1\")\r\n","source_context":[{"line":2,"text":"fn main() {\r\n","is_match":false},{"line":3,"text":"  inspect(1, content=\"1\")\r\n","is_match":true},{"line":4,"text":"}\r\n","is_match":false}]}}
  guard parse_moongrep_match(json) is Some(parsed) else {
    fail("expected moongrep match")
  }
  let hit = project_semantic_match(parsed)
  assert_eq(hit.path, "src/main.mbt")
  assert_eq(hit.rule_id, "inspect($(x:arg))")
  assert_eq(hit.start_line, 3)
  assert_eq(hit.start_column, 3)
  assert_eq(hit.end_line, 3)
  assert_eq(hit.end_column, 26)
  assert_eq(hit.matched_source, "inspect(1, content=\"1\")\n")
  assert_eq(hit.source_context.length(), 3)
  assert_eq(hit.source_context[1].is_match, true)
  assert_eq(hit.source_context[1].text, "  inspect(1, content=\"1\")")
}

///|
test "moongrep failures classify pattern and permission diagnostics" {
  assert_eq(
    semantic_search_error(
      "foo(: patterns[0].shape is not a valid MoonBit expression",
    ).0,
    "invalid_pattern",
  )
  assert_eq(
    semantic_search_error("dump --expr has lexical errors").0,
    "invalid_pattern",
  )
  assert_eq(
    semantic_search_error("missing required --rules, --rule, or --pattern").0,
    "invalid_request",
  )
  assert_eq(
    semantic_search_error("Permission denied (os error 13)").0,
    "permission_denied",
  )
  assert_eq(semantic_search_error("unexpected failure").0, "search_failed")
}

///|
async test "semantic search argument validation requires a rule source" {
  let root = @pathx.Path(".").resolve()
  let resource_root = root.resource_path()
  let payload : SearchSemanticPayload = {
    root: resource_root,
    query: "",
    rules_dir: "",
    enable_builtin_rules: false,
    session_key: "sem:none",
    generation: 1,
    max_results: 20000,
  }
  // The no-command path returns the same validation refusal before probing the
  // provider, so this does not require a moongrep installation on PATH.
  let reply = run_semantic_search(None, root, payload)
  guard reply.error is Some(error) else { fail("expected validation error") }
  assert_eq(error.code, "invalid_request")
}

///|
async test "cancel-before-semantic-search frontier rejects the stale generation" {
  let service = SemanticSearchService::new()
  @async.with_task_group(group => {
    group.spawn_bg(() => service.run())
    service.cancel("sem:stale", 7)
    let root = @pathx.Path(".").resolve()
    let resource_root = root.resource_path()
    let payload : SearchSemanticPayload = {
      root: resource_root,
      query: "foo()",
      rules_dir: "",
      enable_builtin_rules: false,
      session_key: "sem:stale",
      generation: 7,
      max_results: 20000,
    }
    let reply = service.search(None, root, payload)
    assert_true(reply.cancelled)
    assert_eq(reply.generation, 7)
    assert_eq(reply.root, resource_root)
    group.return_immediately(())
  })
}