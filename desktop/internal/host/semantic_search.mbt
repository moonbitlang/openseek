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
/// Emit a progress notification on the first hit and then every
/// `SemanticSearchProgressBatch` accumulated hits, so a long scan paints
/// results before the final reply arrives. The reply stays authoritative;
/// progress is best-effort.
const SemanticSearchProgressBatch : Int = 50

///|
/// The mooncakes coordinate pinned for the interim `moonx` provider. moongrep
/// publishes no upstream release binaries, so a trial bundle resolves the
/// provider through `moonx <coordinate> --`; pinning the version keeps the
/// search deterministic instead of silently running whatever the local
/// registry index knows as "latest".
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
fn SemanticSearchCancellationFrontiers::SemanticSearchCancellationFrontiers() -> SemanticSearchCancellationFrontiers {
  { values: Map([]), order: [], }
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
fn SemanticSearchService::SemanticSearchService() -> SemanticSearchService {
  { requests: Queue(kind=Blocking(64)), }
}

///|
fn empty_semantic_search_reply(
  root : String,
  generation : Int,
  cancelled? : Bool = false,
  partial? : Bool = false,
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
    partial,
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
async fn SemanticSearchService::run(
  self : SemanticSearchService,
  emit : async (@protocol.Notification) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let running : Map[String, RunningSemanticSearch] = Map([])
    let cancelled_through = SemanticSearchCancellationFrontiers::SemanticSearchCancellationFrontiers()
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
              run_semantic_search(command, root, payload, emit),
            ) catch {
              _ if @async.is_being_cancelled() => return
              error => SemanticSearchFailed("Semantic search failed: \{error}")
            }
            self.requests.put(Finished(session_key~, generation~, outcome~))
          })
          running[session_key] = { generation, root: reply_root, reply, task, }
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
    [MoongrepPackageCoordinate, "--"]
  } else {
    []
  }
  args.push("scan")
  for pattern in payload.patterns {
    if !pattern.is_empty() {
      args.append(["--pattern", pattern])
    }
  }
  args.append(["--output-json"])
  args
}

///|
fn semantic_glob_matches(pattern : String, path : String) -> Bool {
  let pattern = pattern.to_array()
  let path = path.to_array()
  fn matches(
    pattern : Array[Char],
    path : Array[Char],
    pi : Int,
    si : Int,
  ) -> Bool {
    if pi == pattern.length() {
      return si == path.length()
    }
    if pattern[pi] == '*' {
      let double = pi + 1 < pattern.length() && pattern[pi + 1] == '*'
      if double && matches(pattern, path, pi + 2, si) {
        return true
      }
      if matches(pattern, path, pi + 1, si) {
        return true
      }
      return si < path.length() &&
        (double || path[si] != '/') &&
        matches(pattern, path, pi, si + 1)
    }
    if si == path.length() {
      return false
    }
    (pattern[pi] == '?' || pattern[pi] == path[si]) &&
    matches(pattern, path, pi + 1, si + 1)
  }
  matches(pattern, path, 0, 0)
}

///|
fn semantic_path_matches_globs(path : String, value : String) -> Bool {
  for glob in expand_text_search_view_globs(value) {
    for expanded in expand_text_search_braces(glob) {
      if semantic_glob_matches(expanded, path) ||
        (
          expanded.has_prefix("**/") &&
          semantic_glob_matches(expanded[3:].to_owned(), path)
        ) {
        return true
      }
    }
  }
  false
}

///|
fn semantic_path_is_included(
  path : String,
  payload : SearchSemanticPayload,
) -> Bool {
  (
    payload.include_glob.is_empty() ||
    semantic_path_matches_globs(path, payload.include_glob)
  ) &&
  !semantic_path_matches_globs(path, payload.exclude_glob)
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
    message.get("type") is Some(String("finding")) &&
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
fn parse_moongrep_error(line : String) -> (String, String)? {
  let json = @json.parse(line) catch { _ => return None }
  guard json is Object(fields) && fields.get("type") is Some(String("error")) else {
    return None
  }
  let message = match fields.get("message") {
    Some(String(value)) => value
    _ => "moongrep reported an error."
  }
  let reason = match fields.get("reason") {
    Some(String(value)) if !value.is_empty() => " \{value}"
    _ => ""
  }
  Some((message, reason))
}

///|
fn project_semantic_match(parsed : ParsedSemanticMatch) -> SemanticSearchHit {
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
/// A nonzero exit is fatal only when moongrep produced no results at all:
/// pattern/rules validation and immediate crashes happen before any hit row.
/// Once hits were streamed, the exit is treated as a recoverable tail crash
/// and the accumulated rows are kept, mirroring ripgrep's partial results.
fn semantic_search_exit_is_fatal(exit_code : Int, got_results : Bool) -> Bool {
  exit_code != 0 && !got_results
}

///|
fn semantic_search_error(stderr : String) -> (String, String) {
  let detail = stderr.trim().to_owned()
  let lower = detail.to_lower()
  let code = if lower.contains("not a valid moonbit expression") ||
    lower.contains("lexical errors") ||
    lower.contains("is not a valid") ||
    lower.contains("invalid metavar syntax") {
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
  // moongrep emits skip warnings before the real error line. Scan from the
  // end: skip indented continuation lines (stack frames) and return the
  // first non-indented, non-empty line as the actual error.
  let lines = detail.split("\n").to_array()
  let mut i = lines.length() - 1
  while i >= 0 {
    let line = lines[i].trim().to_owned()
    if !line.is_empty() && !line.has_prefix("  ") && !line.has_prefix("\t") {
      return line
    }
    i -= 1
  }
  // Fallback: last non-empty line.
  i = lines.length() - 1
  while i >= 0 {
    let line = lines[i].trim().to_owned()
    if !line.is_empty() {
      return line
    }
    i -= 1
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
/// Push one best-effort batch of the hits accumulated so far. The final
/// reply is authoritative, so a dropped or failed notification must never
/// fail the search: progress stops silently and the client still receives
/// everything in `SearchSemanticReply`.
async fn publish_semantic_progress(
  emit : async (@protocol.Notification) -> Unit,
  root : String,
  session_key : String,
  generation : Int,
  matches : Array[SemanticSearchHit],
  match_count : Int,
  file_count : Int,
) -> Unit {
  emit(
    SemanticSearchProgress({
      root,
      session_key,
      generation,
      matches,
      match_count,
      file_count,
    }),
  ) catch {
    // Cancellation must keep propagating — the search loop needs to stop
    // when its task group is torn down. Any other delivery failure
    // (wedged outbound queue, closed connection) only costs the partial
    // frames; the authoritative reply still travels the request path.
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
async fn run_semantic_search(
  command : String?,
  root : @pathx.Absolute,
  payload : SearchSemanticPayload,
  emit : async (@protocol.Notification) -> Unit,
) -> SearchSemanticReply {
  let reply_root = root.resource_path()
  let native_root = root.to_string()
  if payload.patterns.is_empty() {
    return empty_semantic_search_reply(reply_root, payload.generation, error={
      code: "invalid_request",
      message: "Provide a structural code pattern, a rule file, or select built-in rules.",
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
    let mut published_hits = 0
    defer stdout_reader.close()
    for ;; {
      let line = stdout_reader.read_until("\n")
      guard line is Some(line) else { break }
      if parse_moongrep_match(line) is Some(parsed) {
        guard semantic_path_is_included(parsed.path, payload) else { continue }
        if match_count >= max_results {
          limit_hit = true
          process.cancel()
          break
        }
        let hit = project_semantic_match(parsed)
        hits.push(hit)
        files[hit.path] = true
        match_count += 1
        if match_count == 1 || match_count % SemanticSearchProgressBatch == 0 {
          let batch = hits[published_hits:].to_owned()
          publish_semantic_progress(
            emit,
            reply_root,
            payload.session_key,
            payload.generation,
            batch,
            match_count,
            files.length(),
          )
          published_hits = hits.length()
        }
      }
    }
    if published_hits < hits.length() {
      publish_semantic_progress(
        emit,
        reply_root,
        payload.session_key,
        payload.generation,
        hits[published_hits:].to_owned(),
        match_count,
        files.length(),
      )
    }
    let exit_code = process.wait() catch {
      error if @async.is_being_cancelled() => raise error
      _ if limit_hit => 0
      _ => 2
    }
    let stderr = stderr_task.wait() catch { _ => "" }
    let mut json_error : (String, String)? = None
    for line in stderr.split("\n") {
      if parse_moongrep_error(line.to_owned()) is Some(parsed_error) {
        json_error = Some(parsed_error)
      }
    }
    let lower = stderr.to_lower()
    let partial = lower.contains("warning:") ||
      lower.contains("skipping") ||
      lower.contains("parse failed")
    // moongrep streams hits before it aborts, and its current wasm build can
    // crash on MoonBit syntax it does not parse yet. A nonzero exit alone is
    // therefore not fatal once some hits were already emitted: keep them, like
    // ripgrep's partial-results behavior, so the panel can use what it got.
    let (code, message) = match json_error {
      Some(pair) => pair
      None => semantic_search_error(stderr)
    }
    if semantic_search_exit_is_fatal(exit_code, !hits.is_empty()) {
      return empty_semantic_search_reply(reply_root, payload.generation, error={
        code,
        message,
      })
    }
    let error : SemanticSearchError? = if exit_code != 0 {
      Some({ code, message, })
    } else {
      None
    }
    {
      root: reply_root,
      generation: payload.generation,
      matches: hits,
      match_count,
      file_count: files.length(),
      limit_hit,
      cancelled: false,
      partial,
      error,
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
    patterns: ["inspect($(x:arg))"],
    include_glob: "",
    exclude_glob: "",
    session_key: "sem:one",
    generation: 1,
    max_results: 20000,
  }
  assert_eq(semantic_search_args("moonx", pattern), [
    MoongrepPackageCoordinate,
    "--",
    "scan",
    "--pattern",
    "inspect($(x:arg))",
    "--output-json",
  ])
  let second_pattern : SearchSemanticPayload = {
    ..pattern,
    patterns: ["match($x)"],
  }
  assert_eq(semantic_search_args("/opt/bin/moongrep", second_pattern), [
    "scan", "--pattern", "match($x)", "--output-json",
  ])
}

///|
test "semantic path globs filter include and exclude results" {
  let payload : SearchSemanticPayload = {
    root: "/work",
    patterns: ["foo()"],
    include_glob: "src/**",
    exclude_glob: "src/generated/**",
    session_key: "sem:glob",
    generation: 1,
    max_results: 20000,
  }
  assert_true(semantic_path_is_included("src/main.mbt", payload))
  assert_false(semantic_path_is_included("tests/main.mbt", payload))
  assert_false(semantic_path_is_included("src/generated/main.mbt", payload))
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
test "tail crashes keep previously streamed semantic results" {
  assert_true(semantic_search_exit_is_fatal(1, false))
  assert_true(semantic_search_exit_is_fatal(2, false))
  assert_false(semantic_search_exit_is_fatal(0, false))
  assert_false(semantic_search_exit_is_fatal(0, true))
  assert_false(semantic_search_exit_is_fatal(1, true))
  assert_false(semantic_search_exit_is_fatal(134, true))
}

///|
async test "semantic search argument validation requires a rule source" {
  let root = @pathx.Path(".").resolve()
  let resource_root = root.resource_path()
  let payload : SearchSemanticPayload = {
    root: resource_root,
    patterns: [],
    include_glob: "",
    exclude_glob: "",
    session_key: "sem:none",
    generation: 1,
    max_results: 20000,
  }
  // The no-command path returns the same validation refusal before probing the
  // provider, so this does not require a moongrep installation on PATH.
  let reply = run_semantic_search(None, root, payload, _ => ())
  guard reply.error is Some(error) else { fail("expected validation error") }
  assert_eq(error.code, "invalid_request")
}

///|
async test "cancel-before-semantic-search frontier rejects the stale generation" {
  let service = SemanticSearchService::SemanticSearchService()
  @async.with_task_group(group => {
    group.spawn_bg(() => service.run(_ => ()))
    service.cancel("sem:stale", 7)
    let root = @pathx.Path(".").resolve()
    let resource_root = root.resource_path()
    let payload : SearchSemanticPayload = {
      root: resource_root,
      patterns: ["foo()"],
      include_glob: "",
      exclude_glob: "",
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
