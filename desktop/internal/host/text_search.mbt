// Connection-owned workspace text search. One actor serializes session state
// while each generation runs its own ripgrep process in a cancellable task.

///|
const MaxTextSearchResults : Int = 20000

///|
const MaxTextSearchFileSizeBytes : String = "17179869184"

///|
const MaxTextSearchCancellationFrontiers : Int = 128

///|
/// VS Code drains all stderr but retains at most one million characters for
/// diagnostics. Bound by bytes here so invalid UTF-8 cannot evade the cap.
const MaxTextSearchStderrBytes : Int = 1000000

///|
const MaxTextSearchErrorMessageUnits : Int = 1000

///|
const MaxTextSearchPreviewUnits : Int = 400

///|
const TextSearchContextBeforeUnits : Int = 120

///|
/// VS Code's default `files.exclude` plus `search.exclude`. `getRgArgs` emits
/// folder exclusions after every include, so an exclusion always wins.
let default_text_search_excludes : Array[String] = [
  "**/.git", "**/.svn", "**/.hg", "**/.DS_Store", "**/Thumbs.db", "**/node_modules",
  "**/bower_components", "**/*.code-search",
]

///|
priv struct ParsedTextMatch {
  path : String
  line : String
  line_number : Int
  byte_ranges : Array[(Int, Int)]
}

///|
priv enum TextSearchOutcome {
  TextSearchFinished(SearchTextReply)
  TextSearchFailed(String)
}

///|
priv struct RunningTextSearch {
  generation : Int
  root : String
  reply : @async.Queue[SearchTextReply]
  task : @async.Task[Unit]
}

///|
/// Cancellation requests can overtake their matching search request at the
/// transport boundary. Retain a bounded LRU of per-session generation
/// frontiers so that race stays safe without growing for the whole connection
/// lifetime.
priv struct TextSearchCancellationFrontiers {
  values : Map[String, Int]
  order : Array[String]
}

///|
fn TextSearchCancellationFrontiers::TextSearchCancellationFrontiers() -> TextSearchCancellationFrontiers {
  { values: Map([]), order: [], }
}

///|
fn TextSearchCancellationFrontiers::get(
  self : TextSearchCancellationFrontiers,
  session_key : String,
) -> Int {
  self.values.get(session_key).unwrap_or(-1)
}

///|
fn TextSearchCancellationFrontiers::record(
  self : TextSearchCancellationFrontiers,
  session_key : String,
  generation : Int,
) -> Unit {
  self.values[session_key] = self.get(session_key).max(generation)
  self.order.retain(key => key != session_key)
  self.order.push(session_key)
  if self.order.length() > MaxTextSearchCancellationFrontiers {
    let oldest = self.order.remove(0)
    self.values.remove(oldest)
  }
}

///|
priv enum TextSearchRequest {
  Search(
    command~ : String?,
    root~ : @pathx.Absolute,
    payload~ : SearchTextPayload,
    reply~ : @async.Queue[SearchTextReply]
  )
  Cancel(session_key~ : String, generation~ : Int, reply~ : @async.Queue[Unit])
  Finished(
    session_key~ : String,
    generation~ : Int,
    outcome~ : TextSearchOutcome
  )
}

///|
priv struct TextSearchService {
  requests : @async.Queue[TextSearchRequest]
}

///|
fn TextSearchService::TextSearchService() -> TextSearchService {
  { requests: Queue(kind=Blocking(64)), }
}

///|
fn empty_text_search_reply(
  root : String,
  generation : Int,
  cancelled? : Bool = false,
  error? : @protocol.TextSearchError,
) -> SearchTextReply {
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
async fn TextSearchService::search(
  self : TextSearchService,
  command : String?,
  root : @pathx.Absolute,
  payload : SearchTextPayload,
) -> SearchTextReply {
  let reply : @async.Queue[SearchTextReply] = Queue(kind=Blocking(1))
  self.requests.put(Search(command~, root~, payload~, reply~))
  reply.get()
}

///|
async fn TextSearchService::cancel(
  self : TextSearchService,
  session_key : String,
  generation : Int,
) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.requests.put(Cancel(session_key~, generation~, reply~))
  reply.get()
}

///|
async fn cancel_running_text_search(
  running : RunningTextSearch,
  root : String,
) -> Unit {
  running.task.cancel()
  running.reply.put(
    empty_text_search_reply(root, running.generation, cancelled=true),
  ) catch {
    _ => ()
  }
}

///|
async fn TextSearchService::run(self : TextSearchService) -> Unit {
  @async.with_task_group(group => {
    let running : Map[String, RunningTextSearch] = Map([])
    let cancelled_through = TextSearchCancellationFrontiers::TextSearchCancellationFrontiers()
    for ;; {
      match self.requests.get() {
        Search(command~, root~, payload~, reply~) => {
          let session_key = payload.session_key
          let reply_root = root.resource_path()
          if session_key.is_blank() {
            reply.put(
              empty_text_search_reply(reply_root, payload.generation, error={
                code: "invalid_request",
                message: "Search session key is empty.",
              }),
            )
            continue
          }
          if cancelled_through.get(session_key) >= payload.generation {
            reply.put(
              empty_text_search_reply(
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
                empty_text_search_reply(
                  reply_root,
                  payload.generation,
                  cancelled=true,
                ),
              )
              continue
            }
            cancel_running_text_search(previous, previous.root)
            running.remove(session_key)
          }
          let generation = payload.generation
          let task = group.spawn(no_wait=true, allow_failure=true, () => {
            let outcome = TextSearchFinished(
              run_text_search(command, root, payload),
            ) catch {
              _ if @async.is_being_cancelled() => return
              error => TextSearchFailed("Workspace search failed: \{error}")
            }
            self.requests.put(Finished(session_key~, generation~, outcome~))
          })
          running[session_key] = { generation, root: reply_root, reply, task, }
        }
        Cancel(session_key~, generation~, reply~) => {
          cancelled_through.record(session_key, generation)
          if running.get(session_key) is Some(current) &&
            current.generation <= generation {
            cancel_running_text_search(current, current.root)
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
            TextSearchFinished(result) => current.reply.put(result)
            TextSearchFailed(message) =>
              current.reply.put(
                empty_text_search_reply(root, generation, error={
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
/// VS Code's Search view uses `splitGlobAware` rather than a glob parser: only
/// commas outside brace alternatives and character classes split the input.
fn split_text_search_globs(value : String) -> Array[String] {
  let globs : Array[String] = []
  for part in split_text_search_glob_aware(value, ',') {
    let glob = part.trim().to_owned()
    if !glob.is_empty() {
      globs.push(glob)
    }
  }
  globs
}

///|
fn push_unique_text_search_glob(
  globs : Array[String],
  seen : Map[String, Bool],
  glob : String,
) -> Unit {
  if !seen.contains(glob) {
    seen[glob] = true
    globs.push(glob)
  }
}

///|
/// Port of QueryBuilder's `expandGlobalGlob`. Keep the single replacement pass
/// used by JavaScript's global regexp; do not recursively normalize `**/**`.
fn expand_text_search_global_glob(pattern : String) -> Array[String] {
  [
    ("**/" + pattern + "/**").replace_all(old="**/**", new="**"),
    ("**/" + pattern).replace_all(old="**/**", new="**"),
  ]
}

///|
/// Adapt Search-view entries into the folder include/exclude patterns consumed
/// by `getRgArgs`. Ordinary entries are global. In this single-root host, the
/// VS Code search-path spelling `./foo` is represented by root-relative globs.
fn expand_text_search_view_globs(value : String) -> Array[String] {
  let expanded : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for entry in split_text_search_globs(value) {
    if entry == "./" || entry == ".\\" {
      continue
    }
    if entry == "." {
      push_unique_text_search_glob(expanded, seen, ".")
      push_unique_text_search_glob(expanded, seen, "./**")
      continue
    }
    if entry.has_prefix("./") || entry.has_prefix(".\\") {
      let rooted = entry.replace_all(old="\\", new="/")[2:]
        .trim_end(chars="/")
        .to_owned()
      if rooted.is_empty() {
        continue
      }
      push_unique_text_search_glob(expanded, seen, rooted)
      if !rooted.has_suffix("**") {
        push_unique_text_search_glob(expanded, seen, rooted + "/**")
      }
      continue
    }
    let without_forward_slash = entry.trim_end(chars="/").to_owned()
    let pattern = without_forward_slash.trim_end(chars="\\").to_owned()
    if pattern.is_empty() {
      continue
    }
    let pattern = if pattern.has_prefix(".") { "*" + pattern } else { pattern }
    for glob in expand_text_search_global_glob(pattern) {
      push_unique_text_search_glob(expanded, seen, glob)
    }
  }
  expanded
}

///|
/// VS Code can turn `../`, `~/`, and absolute Search-view entries into extra
/// folder queries. This protocol deliberately searches one selected root, so
/// those location-changing entries must not be miscompiled as ordinary globs.
fn external_text_search_path(value : String) -> String? {
  for entry in split_text_search_globs(value) {
    let chars = entry.to_array()
    let windows_absolute = chars.length() >= 3 &&
      chars[0].is_ascii_alphabetic() &&
      chars[1] == ':' &&
      (chars[2] == '/' || chars[2] == '\\')
    if entry == ".." ||
      entry.has_prefix("../") ||
      entry.has_prefix("..\\") ||
      entry == "~" ||
      entry.has_prefix("~/") ||
      entry.has_prefix("~\\") ||
      entry.has_prefix("/") ||
      entry.has_prefix("\\\\") ||
      windows_absolute {
      return Some(entry)
    }
  }
  None
}

///|
fn anchor_text_search_glob(glob : String) -> String {
  if glob.has_prefix("**") || glob.has_prefix("/") {
    glob
  } else {
    "/" + glob
  }
}

///|
/// VS Code's `splitGlobAware`: split outside brace and bracket groups. Escape
/// normalization is deliberately handled by brace expansion before this step.
fn split_text_search_glob_aware(
  value : String,
  separator : Char,
) -> Array[String] {
  guard !value.is_empty() else { return [] }
  let components : Array[String] = []
  let mut part = StringBuilder()
  let mut in_braces = false
  let mut in_brackets = false
  for char in value {
    if char == separator && !in_braces && !in_brackets {
      components.push(part.to_string())
      part = StringBuilder()
      continue
    }
    match char {
      '{' => in_braces = true
      '}' => in_braces = false
      '[' => in_brackets = true
      ']' => in_brackets = false
      _ => ()
    }
    part.write_char(char)
  }
  let tail = part.to_string()
  if !tail.is_empty() {
    components.push(tail)
  }
  components
}

///|
/// Port of VS Code's escape-aware first-brace split. The middle string is the
/// normalized original when no valid pair exists; otherwise the outer Options
/// contain the text before and after the first expandable pair.
fn split_text_search_braces(pattern : String) -> (String?, String, String?) {
  let fixed_start = StringBuilder()
  let str_in_braces = StringBuilder()
  let mut in_braces = false
  let mut escaped = false
  let mut offset = 0
  for char in pattern {
    offset += char.utf16_len()
    match char {
      '\\' =>
        if escaped {
          if in_braces {
            str_in_braces.write_char('\\')
            str_in_braces.write_char('\\')
          } else {
            fixed_start.write_char('\\')
            fixed_start.write_char('\\')
          }
          escaped = false
        } else {
          escaped = true
        }
      '{' =>
        if escaped {
          if in_braces {
            str_in_braces.write_char(char)
          } else {
            fixed_start.write_char(char)
          }
          escaped = false
        } else if in_braces {
          return (
            None,
            fixed_start.to_string() +
            "{" +
            str_in_braces.to_string() +
            "{" +
            pattern[offset:].to_owned(),
            None,
          )
        } else {
          in_braces = true
        }
      '}' =>
        if escaped {
          if in_braces {
            str_in_braces.write_char(char)
          } else {
            fixed_start.write_char(char)
          }
          escaped = false
        } else if in_braces {
          return (
            Some(fixed_start.to_string()),
            str_in_braces.to_string(),
            Some(pattern[offset:].to_owned()),
          )
        } else {
          fixed_start.write_char(char)
        }
      _ => {
        if in_braces {
          if escaped {
            str_in_braces.write_char('\\')
          }
          str_in_braces.write_char(char)
        } else {
          if escaped {
            fixed_start.write_char('\\')
          }
          fixed_start.write_char(char)
        }
        escaped = false
      }
    }
  }
  (
    None,
    fixed_start.to_string() +
    (if in_braces { "{" + str_in_braces.to_string() } else { "" }),
    None,
  )
}

///|
fn expand_text_search_braces(pattern : String) -> Array[String] {
  let (fixed_start, str_in_braces, fixed_end) = split_text_search_braces(
    pattern,
  )
  guard fixed_start is Some(fixed_start) && fixed_end is Some(fixed_end) else {
    return [str_in_braces]
  }
  let alternatives = match split_text_search_glob_aware(str_in_braces, ',') {
    [] => [""]
    alternatives => alternatives
  }
  let expanded_end = expand_text_search_braces(fixed_end)
  let expanded : Array[String] = []
  for alternative in alternatives {
    for end in expanded_end {
      expanded.push(fixed_start + alternative + end)
    }
  }
  expanded
}

///|
/// VS Code keeps every path prefix visible to ripgrep after adding `-g !*`.
/// For example `foo/*bar/file/**` becomes `/foo`, `/foo/*bar`,
/// `/foo/*bar/file`, and `/foo/*bar/file/**`.
fn spread_text_search_glob_components(glob : String) -> Array[String] {
  let spread : Array[String] = []
  for expanded in expand_text_search_braces(glob) {
    let components = split_text_search_glob_aware(expanded, '/')
    let mut current = ""
    for component in components {
      current = if current.is_empty() {
        component
      } else {
        current + "/" + component
      }
      spread.push(anchor_text_search_glob(current))
    }
  }
  spread
}

///|
/// Port of the include portion of VS Code's `getRgArgs`. Ripgrep needs `!*`
/// before a root-relative include, followed by each ancestor that permits it
/// to traverse to the requested path. Global `**` patterns can pass through.
fn text_search_include_args(includes : Array[String]) -> Array[String] {
  let args : Array[String] = []
  let other_includes : Array[String] = []
  let double_star_includes : Array[String] = []
  let seen_others : Map[String, Bool] = Map([])
  for glob in includes {
    if glob.has_prefix("**") {
      double_star_includes.push(glob)
    } else if !seen_others.contains(glob) {
      seen_others[glob] = true
      other_includes.push(glob)
    }
  }
  if !other_includes.is_empty() {
    args.append(["-g", "!*"])
  }
  for glob in other_includes {
    for include_glob in spread_text_search_glob_components(glob) {
      args.append(["-g", include_glob])
    }
  }
  for glob in double_star_includes {
    args.append(["-g", glob])
  }
  args
}

///|
fn text_search_regex_escape(value : String) -> String {
  let escaped = "\\{}*+?|^$.[]()"
  let result = StringBuilder()
  for char in value {
    if escaped.contains(char.to_string()) {
      result.write_char('\\')
    }
    result.write_char(char)
  }
  result.to_string()
}

///|
fn text_search_word_char(char : Char) -> Bool {
  char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '_'
}

///|
/// JavaScript search patterns spell Unicode escapes as `\\u1234`; PCRE2 uses
/// `\\x{1234}`. This mirrors VS Code's four-hex-digit conversion while
/// preserving escaped backslashes and longer braced escapes.
fn text_search_unicode_escapes_to_pcre2(pattern : String) -> String {
  let chars = pattern.to_array()
  let output = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if chars[index] != '\\' {
      output.write_char(chars[index])
      index += 1
      continue
    }
    let mut after_slashes = index
    while after_slashes < chars.length() && chars[after_slashes] == '\\' {
      output.write_char('\\')
      after_slashes += 1
    }
    let slash_count = after_slashes - index
    guard slash_count % 2 == 1 &&
      after_slashes < chars.length() &&
      chars[after_slashes] == 'u' else {
      index = after_slashes
      continue
    }
    let mut converted = false
    if after_slashes + 4 < chars.length() {
      let digits = chars[after_slashes + 1:after_slashes + 5]
      if digits.iter().all(char => char.is_ascii_hexdigit()) {
        output.write_string("x{")
        for digit in digits {
          output.write_char(digit)
        }
        output.write_char('}')
        index = after_slashes + 5
        converted = true
      }
    }
    if !converted &&
      after_slashes + 6 < chars.length() &&
      chars[after_slashes + 1] == '{' &&
      chars[after_slashes + 6] == '}' {
      let digits = chars[after_slashes + 2:after_slashes + 6]
      if digits.iter().all(char => char.is_ascii_hexdigit()) {
        output.write_string("x{")
        for digit in digits {
          output.write_char(digit)
        }
        output.write_char('}')
        index = after_slashes + 7
        converted = true
      }
    }
    if !converted {
      output.write_char('u')
      index = after_slashes + 1
    }
  }
  output.to_string()
}

///|
fn text_search_word_pattern(payload : SearchTextPayload) -> String {
  let pattern = if payload.regex {
    text_search_unicode_escapes_to_pcre2(payload.query)
  } else {
    text_search_regex_escape(payload.query)
  }
  let chars = pattern.to_array()
  guard !chars.is_empty() else { return pattern }
  let prefix = if text_search_word_char(chars[0]) { "\\b" } else { "" }
  let suffix = if text_search_word_char(chars[chars.length() - 1]) {
    "\\b"
  } else {
    ""
  }
  prefix + pattern + suffix
}

///|
fn text_search_args(payload : SearchTextPayload) -> Array[String] {
  let args : Array[String] = ["--hidden", "--no-require-git"]
  args.push(
    if payload.case_sensitive {
      "--case-sensitive"
    } else {
      "--ignore-case"
    },
  )
  // VS Code treats globs and ignore-file entries case-insensitively on macOS
  // and Windows, while Linux retains filesystem case.
  if !@sysplatform.linux {
    args.append(["--glob-case-insensitive", "--ignore-file-case-insensitive"])
  }
  args.append(
    text_search_include_args(
      expand_text_search_view_globs(payload.include_glob),
    ),
  )
  // `getRgArgs` emits all exclusions after includes. This ordering matters to
  // ripgrep because the last matching glob decides whether a path is searched.
  for glob in default_text_search_excludes {
    args.append(["-g", "!" + anchor_text_search_glob(glob)])
  }
  for glob in expand_text_search_view_globs(payload.exclude_glob) {
    args.append(["-g", "!" + anchor_text_search_glob(glob)])
  }
  args.append([
    "--max-filesize",
    MaxTextSearchFileSizeBytes,
    "--no-ignore-parent",
    "--follow",
    "--crlf",
  ])
  let forced_regex = payload.query == "--"
  if payload.regex || forced_regex {
    args.append(["--engine", "auto"])
  }
  if payload.whole_word {
    args.append(["--regexp", text_search_word_pattern(payload)])
  } else if payload.regex {
    args.append([
      "--regexp",
      text_search_unicode_escapes_to_pcre2(payload.query),
    ])
  } else if forced_regex {
    args.append(["--regexp", "\\-\\-"])
  } else {
    args.push("--fixed-strings")
  }
  args.append(["--no-config", "--no-ignore-global", "--json", "--"])
  if !payload.regex && !payload.whole_word && !forced_regex {
    args.push(payload.query)
  }
  args.push(".")
  args
}

///|
fn nested_json_text(fields : Map[String, Json], key : String) -> String? {
  guard fields.get(key) is Some(Object(value)) else { return None }
  match value {
    { "text": String(text), .. } => Some(text)
    { "bytes": String(encoded), .. } => {
      let bytes = @base64.decode(encoded) catch { _ => return None }
      Some(@utf8.decode_lossy(bytes))
    }
    _ => None
  }
}

///|
fn normalize_text_search_path(path : String) -> String {
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
fn parse_ripgrep_match(line : String) -> ParsedTextMatch? {
  let json = @json.parse(line) catch { _ => return None }
  guard json is Object(message) &&
    message.get("type") is Some(String("match")) &&
    message.get("data") is Some(Object(data)) &&
    nested_json_text(data, "path") is Some(path) &&
    nested_json_text(data, "lines") is Some(source_line) &&
    data.get("line_number") is Some(Number(line_number, ..)) &&
    data.get("submatches") is Some(Array(submatches)) else {
    return None
  }
  let source_line = source_line.trim_end(chars="\r\n").to_owned()
  let ranges : Array[(Int, Int)] = []
  for submatch in submatches {
    if submatch is Object(fields) &&
      fields.get("start") is Some(Number(start, ..)) &&
      fields.get("end") is Some(Number(end, ..)) {
      ranges.push((start.to_int(), end.to_int()))
    }
  }
  if ranges.is_empty() {
    let first_char_bytes = match source_line.to_array() {
      [] => 0
      [first, ..] => @utf8.encode(first.to_string()).length()
    }
    ranges.push((0, first_char_bytes))
  }
  Some({
    path: normalize_text_search_path(path),
    line: source_line,
    line_number: line_number.to_int(),
    byte_ranges: ranges,
  })
}

///|
fn utf16_offset_for_byte(line : String, byte_offset : Int) -> Int? {
  let bytes = @utf8.encode(line)
  guard byte_offset >= 0 && byte_offset <= bytes.length() else { return None }
  let prefix = @utf8.decode(bytes[:byte_offset]) catch { _ => return None }
  Some(prefix.length())
}

///|
fn safe_utf16_start(text : String, offset : Int) -> Int {
  let offset = offset.max(0).min(text.length())
  if offset > 0 &&
    offset < text.length() &&
    text[offset - 1].to_int().is_leading_surrogate() &&
    text[offset].to_int().is_trailing_surrogate() {
    offset - 1
  } else {
    offset
  }
}

///|
fn safe_utf16_end(text : String, offset : Int) -> Int {
  let offset = offset.max(0).min(text.length())
  if offset > 0 &&
    offset < text.length() &&
    text[offset - 1].to_int().is_leading_surrogate() &&
    text[offset].to_int().is_trailing_surrogate() {
    offset + 1
  } else {
    offset
  }
}

///|
fn project_text_match(
  parsed : ParsedTextMatch,
  remaining : Int,
) -> (TextSearchMatch?, Int, Bool) {
  let ranges : Array[@protocol.TextSearchRange] = []
  let mut overflow = false
  for byte_range in parsed.byte_ranges {
    let (start_byte, end_byte) = byte_range
    guard utf16_offset_for_byte(parsed.line, start_byte) is Some(start) &&
      utf16_offset_for_byte(parsed.line, end_byte) is Some(end) &&
      end >= start else {
      continue
    }
    if ranges.length() >= remaining {
      overflow = true
      continue
    }
    ranges.push({ start_column: start + 1, end_column: end + 1, })
  }
  guard !ranges.is_empty() else { return (None, 0, overflow) }
  let first = ranges[0]
  let mut preview_start = 0
  let mut preview_end = parsed.line.length()
  if preview_end > MaxTextSearchPreviewUnits {
    preview_start = safe_utf16_start(
      parsed.line,
      (first.start_column - 1 - TextSearchContextBeforeUnits).max(0),
    )
    preview_end = safe_utf16_end(
      parsed.line,
      (preview_start + MaxTextSearchPreviewUnits).min(parsed.line.length()),
    )
    if first.end_column - 1 > preview_end {
      preview_end = safe_utf16_end(parsed.line, first.end_column - 1)
      preview_start = safe_utf16_start(
        parsed.line,
        (preview_end - MaxTextSearchPreviewUnits).max(0),
      )
    }
  }
  (
    Some({
      path: parsed.path,
      line_number: parsed.line_number,
      preview: parsed.line[preview_start:preview_end].to_owned(),
      preview_start_column: preview_start + 1,
      ranges,
    }),
    ranges.length(),
    overflow,
  )
}

///|
fn text_search_diagnostic_line(detail : String, needle : String) -> String? {
  for raw_line in detail.split("\n") {
    let line = raw_line.trim().to_owned()
    if line.to_lower().contains(needle) {
      return Some(line)
    }
  }
  None
}

///|
fn text_search_first_diagnostic_line(detail : String) -> String? {
  for raw_line in detail.split("\n") {
    let line = raw_line.trim().to_owned()
    if !line.is_empty() {
      return Some(line)
    }
  }
  None
}

///|
fn text_search_display_line(line : String) -> String {
  line.strip_prefix("rg: ").map(rest => rest.to_owned()).unwrap_or(line)
}

///|
fn text_search_regex_error_message(detail : String) -> String {
  let diagnostic = match
    text_search_diagnostic_line(detail, "pcre2: error compiling pattern") {
    Some(line) => Some(line)
    None =>
      match text_search_diagnostic_line(detail, "regex parse error") {
        Some(line) => Some(line)
        None => text_search_diagnostic_line(detail, "error parsing regex")
      }
  }
  guard diagnostic is Some(diagnostic) else { return "Regex parse error" }
  match [..diagnostic.split(":")] {
    [.., reason] if !reason.trim().is_empty() =>
      "Regex parse error: \{reason.trim()}"
    _ => "Regex parse error"
  }
}

///|
fn bounded_text_search_error_message(message : String) -> String {
  guard message.length() > MaxTextSearchErrorMessageUnits else {
    return message
  }
  let end = safe_utf16_start(message, MaxTextSearchErrorMessageUnits)
  message[:end].to_owned() + "…"
}

///|
fn text_search_error(stderr : String) -> (String, String) {
  let detail = stderr.trim().to_owned()
  let lower = detail.to_lower()
  let code = if lower.contains("regex parse error") ||
    lower.contains("error parsing regex") ||
    lower.contains("pcre2: error compiling pattern") {
    "invalid_regex"
  } else if lower.contains("error parsing glob") {
    "invalid_glob"
  } else if lower.contains("the literal") {
    "invalid_request"
  } else if lower.contains("permission denied") ||
    lower.contains("access is denied") {
    "permission_denied"
  } else {
    "search_failed"
  }
  let message = match code {
    "invalid_regex" => text_search_regex_error_message(detail)
    "invalid_glob" =>
      text_search_diagnostic_line(detail, "error parsing glob")
      .map(text_search_display_line)
      .unwrap_or("Invalid glob pattern.")
    "invalid_request" =>
      text_search_diagnostic_line(detail, "the literal")
      .map(text_search_display_line)
      .unwrap_or("Invalid search pattern.")
    "permission_denied" =>
      match text_search_diagnostic_line(detail, "permission denied") {
        Some(line) => text_search_display_line(line)
        None =>
          text_search_diagnostic_line(detail, "access is denied")
          .map(text_search_display_line)
          .unwrap_or("Permission denied while searching the workspace.")
      }
    _ =>
      text_search_first_diagnostic_line(detail)
      .map(text_search_display_line)
      .unwrap_or("ripgrep could not complete the search.")
  }
  (code, bounded_text_search_error_message(message))
}

///|
fn text_search_exit_is_fatal(
  exit_code : Int,
  limit_hit : Bool,
  got_output : Bool,
) -> Bool {
  exit_code != 0 && exit_code != 1 && !limit_hit && !got_output
}

///|
async fn run_text_search(
  command : String?,
  root : @pathx.Absolute,
  payload : SearchTextPayload,
) -> SearchTextReply {
  let reply_root = root.resource_path()
  let native_root = root.to_string()
  if payload.query.is_empty() {
    return empty_text_search_reply(reply_root, payload.generation)
  }
  if external_text_search_path(payload.include_glob) is Some(_) ||
    external_text_search_path(payload.exclude_glob) is Some(_) {
    return empty_text_search_reply(reply_root, payload.generation, error={
      code: "invalid_request",
      message: "Search paths outside the selected workspace are not supported; use ./ for a root-relative pattern.",
    })
  }
  guard command is Some(command) else {
    return empty_text_search_reply(reply_root, payload.generation, error={
      code: "rg_unavailable",
      message: "This SeekMoon installation does not include ripgrep.",
    })
  }
  let directory = @fs.opendir(native_root) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      return empty_text_search_reply(reply_root, payload.generation, error={
        code: if "\{error}".to_lower().contains("permission") {
          "permission_denied"
        } else {
          "search_failed"
        },
        message: "Cannot read workspace: \{error}",
      })
  }
  directory.close()
  let max_results = payload.max_results.max(0).min(MaxTextSearchResults)
  let (stdout_reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  // Provide a closed stdin pipe so the Windows spawn does not fall back to
  // GetStdHandle, which returns NULL (not INVALID_HANDLE_VALUE) when the
  // process has no console — causing SetHandleInformation(NULL, …) to fail
  // with "The handle is invalid".
  let (stdin_reader, stdin_writer) = @process.write_to_process()
  stdin_writer.close()
  @async.with_task_group(group => {
    let process = @process.spawn(
      group,
      command,
      text_search_args(payload),
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
        return empty_text_search_reply(reply_root, payload.generation, error={
          code: "rg_unavailable",
          message: "Cannot start ripgrep: \{error}",
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
        if retained_bytes < MaxTextSearchStderrBytes {
          let length = chunk
            .length()
            .min(MaxTextSearchStderrBytes - retained_bytes)
          retained.write_bytes(chunk[:length].to_owned())
          retained_bytes += length
        }
      }
      @utf8.decode_lossy(retained.contents())
    })
    let matches : Array[@protocol.TextSearchMatch] = []
    let files : Map[String, Bool] = Map([])
    let mut match_count = 0
    let mut limit_hit = false
    let mut got_output = false
    defer stdout_reader.close()
    for ;; {
      let line = stdout_reader.read_until("\n")
      guard line is Some(line) else { break }
      got_output = true
      guard parse_ripgrep_match(line) is Some(parsed) else { continue }
      let remaining = max_results - match_count
      if remaining <= 0 {
        limit_hit = true
        process.cancel()
        break
      }
      let (projected, count, overflow) = project_text_match(parsed, remaining)
      if projected is Some(projected) {
        matches.push(projected)
        files[projected.path] = true
        match_count += count
      }
      if overflow || match_count >= max_results {
        limit_hit = true
        process.cancel()
        break
      }
    }
    let exit_code = process.wait() catch {
      error if @async.is_being_cancelled() => raise error
      _ if limit_hit => 0
      _ => 2
    }
    let stderr = stderr_task.wait() catch { _ => "" }
    // Like VS Code, keep partial results when ripgrep could search some paths
    // but reports a recoverable error for another one.
    if text_search_exit_is_fatal(exit_code, limit_hit, got_output) {
      let (code, message) = text_search_error(stderr)
      return empty_text_search_reply(reply_root, payload.generation, error={
        code,
        message,
      })
    }
    {
      root: reply_root,
      generation: payload.generation,
      matches,
      match_count,
      file_count: files.length(),
      limit_hit,
      cancelled: false,
      error: None,
    }
  })
}

///|
async fn search_text_op(
  service : TextSearchService,
  payload : SearchTextPayload,
) -> SearchTextReply {
  let root = WirePath::parse(payload.root).absolute
  let command = ripgrep_command()
  service.search(command, root, payload)
}

///|
async fn cancel_search_text_op(
  service : TextSearchService,
  payload : CancelSearchTextPayload,
) -> @protocol.EmptyReply {
  service.cancel(payload.session_key, payload.generation)
  Acknowledged
}

///|
test "text search arguments mirror VS Code regex, ignore, and glob defaults" {
  let payload : SearchTextPayload = {
    root: "/work",
    query: "moon.*bit",
    regex: true,
    case_sensitive: false,
    whole_word: true,
    include_glob: "src/**,tests/*.{mbt,md}",
    exclude_glob: "**/*.snap,generated/**",
    session_key: "search:one",
    generation: 1,
    max_results: 20000,
  }
  let args = text_search_args(payload)
  let expected : Array[String] = [
    "--hidden", "--no-require-git", "--ignore-case",
  ]
  if !@sysplatform.linux {
    expected.append([
      "--glob-case-insensitive", "--ignore-file-case-insensitive",
    ])
  }
  expected.append([
    "-g", "**/src/**", "-g", "**/tests/*.{mbt,md}/**", "-g", "**/tests/*.{mbt,md}",
    "-g", "!**/.git", "-g", "!**/.svn", "-g", "!**/.hg", "-g", "!**/.DS_Store", "-g",
    "!**/Thumbs.db", "-g", "!**/node_modules", "-g", "!**/bower_components", "-g",
    "!**/*.code-search", "-g", "!**/*.snap/**", "-g", "!**/*.snap", "-g", "!**/generated/**",
    "--max-filesize", "17179869184", "--no-ignore-parent", "--follow", "--crlf",
    "--engine", "auto", "--regexp", "\\bmoon.*bit\\b", "--no-config", "--no-ignore-global",
    "--json", "--", ".",
  ])
  assert_eq(args, expected)
}

///|
test "Search-view globs expand like VS Code QueryBuilder" {
  assert_eq(expand_text_search_view_globs("a"), ["**/a/**", "**/a"])
  assert_eq(expand_text_search_view_globs("a/b"), ["**/a/b/**", "**/a/b"])
  assert_eq(expand_text_search_view_globs(".txt"), ["**/*.txt/**", "**/*.txt"])
  assert_eq(expand_text_search_view_globs("src/**, src/**, ,"), ["**/src/**"])
  assert_eq(expand_text_search_view_globs("**"), ["**/**", "**"])
  assert_eq(expand_text_search_view_globs("./bar"), ["bar", "bar/**"])
  assert_eq(expand_text_search_view_globs(".\\bar"), ["bar", "bar/**"])
  assert_eq(expand_text_search_view_globs("./bar/*.mbt"), [
    "bar/*.mbt", "bar/*.mbt/**",
  ])
  assert_eq(expand_text_search_view_globs("./bar/**"), ["bar/**"])
  assert_eq(expand_text_search_view_globs("."), [".", "./**"])
  assert_eq(expand_text_search_view_globs("./"), [])
}

///|
test "Search-view comma splitting preserves brace and bracket groups" {
  assert_eq(split_text_search_globs("a/{b,c}, [d,e],, f"), [
    "a/{b,c}", "[d,e]", "f",
  ])
}

///|
test "single-root search rejects VS Code entries that change location" {
  assert_eq(external_text_search_path("../sibling"), Some("../sibling"))
  assert_eq(external_text_search_path("~/src"), Some("~/src"))
  assert_eq(external_text_search_path("/tmp/src"), Some("/tmp/src"))
  assert_eq(external_text_search_path("C:\\src"), Some("C:\\src"))
  assert_eq(external_text_search_path("src/**,./tests/**"), None)
}

///|
test "brace expansion preserves alternatives used by VS Code include globs" {
  assert_eq(expand_text_search_braces("eep/{a,b}/test"), [
    "eep/a/test", "eep/b/test",
  ])
  assert_eq(expand_text_search_braces("eep/{a,b}/{c,d,e}"), [
    "eep/a/c", "eep/a/d", "eep/a/e", "eep/b/c", "eep/b/d", "eep/b/e",
  ])
  assert_eq(expand_text_search_braces("eep/{a,b}/\\{c,d,e}"), [
    "eep/a/{c,d,e}", "eep/b/{c,d,e}",
  ])
  assert_eq(expand_text_search_braces("eep/{a,b\\}/test"), ["eep/{a,b}/test"])
  assert_eq(expand_text_search_braces("eep/{a,b\\\\}/test"), [
    "eep/a/test", "eep/b\\\\/test",
  ])
  assert_eq(expand_text_search_braces("eep/{a,b\\\\\\}/test"), [
    "eep/{a,b\\\\}/test",
  ])
  assert_eq(expand_text_search_braces("e\\{ep/{a,b}/test"), [
    "e{ep/a/test", "e{ep/b/test",
  ])
  assert_eq(expand_text_search_braces("eep/{a,\\b}/test"), [
    "eep/a/test", "eep/\\b/test",
  ])
  assert_eq(expand_text_search_braces("{a/*.*,b/*.*}"), ["a/*.*", "b/*.*"])
  assert_eq(expand_text_search_braces("{}foo"), ["foo"])
  assert_eq(expand_text_search_braces("bar{ }foo"), ["bar foo"])
  assert_eq(expand_text_search_braces("{{}"), ["{{}"])
  assert_eq(expand_text_search_braces("aa{{}"), ["aa{{}"])
  assert_eq(expand_text_search_braces("{b{}"), ["{b{}"])
  assert_eq(expand_text_search_braces("{{}c"), ["{{}c"])
  assert_eq(expand_text_search_braces("{{}}"), ["{{}}"])
  assert_eq(expand_text_search_braces("\\{{}}"), ["{}"])
  assert_eq(expand_text_search_braces("{}"), [""])
}

///|
test "include adaptation mirrors VS Code getRgArgs vectors" {
  assert_eq(text_search_include_args(["a/*", "b/*"]), [
    "-g", "!*", "-g", "/a", "-g", "/a/*", "-g", "/b", "-g", "/b/*",
  ])
  assert_eq(text_search_include_args(["**/a/*", "b/*"]), [
    "-g", "!*", "-g", "/b", "-g", "/b/*", "-g", "**/a/*",
  ])
  assert_eq(text_search_include_args(["**/a/*", "**/b/*"]), [
    "-g", "**/a/*", "-g", "**/b/*",
  ])
  assert_eq(text_search_include_args(["foo/*bar/something/**"]), [
    "-g", "!*", "-g", "/foo", "-g", "/foo/*bar", "-g", "/foo/*bar/something", "-g",
    "/foo/*bar/something/**",
  ])
  assert_eq(text_search_include_args(["b/*", "b/*"]), [
    "-g", "!*", "-g", "/b", "-g", "/b/*",
  ])
}

///|
test "ripgrep byte ranges become one-based UTF-16 emoji columns" {
  let json =
    #|{"type":"match","data":{"path":{"text":"src/main.mbt"},"lines":{"text":"a🌙moon\r\n"},"line_number":3,"absolute_offset":0,"submatches":[{"match":{"text":"moon"},"start":5,"end":9}]}}
  guard parse_ripgrep_match(json) is Some(parsed) else {
    fail("expected ripgrep match")
  }
  let (projected, count, overflow) = project_text_match(parsed, 2000)
  guard projected is Some(projected) else { fail("expected projected match") }
  assert_eq(projected.line_number, 3)
  assert_eq(projected.preview, "a🌙moon")
  assert_eq(projected.ranges[0], { start_column: 4, end_column: 8, })
  assert_eq(count, 1)
  assert_false(overflow)
}

///|
test "literal case-sensitive arguments are deterministic and follow symlinks" {
  let payload : SearchTextPayload = {
    root: "/work",
    query: "Moon",
    regex: false,
    case_sensitive: true,
    whole_word: false,
    include_glob: "",
    exclude_glob: "",
    session_key: "search:literal",
    generation: 2,
    max_results: 20000,
  }
  let args = text_search_args(payload)
  assert_true(args.contains("--fixed-strings"))
  assert_true(args.contains("--case-sensitive"))
  assert_false(args.contains("--ignore-case"))
  assert_false(args.contains("--word-regexp"))
  assert_true(args.contains("!**/.git"))
  assert_true(args.contains("!**/node_modules"))
  assert_false(args.contains("!**/target"))
  assert_true(args.contains("--max-filesize"))
  assert_true(args.contains("17179869184"))
  assert_true(args.contains("--no-config"))
  assert_true(args.contains("--no-require-git"))
  assert_true(args.contains("--no-ignore-parent"))
  assert_true(args.contains("--no-ignore-global"))
  assert_true(args.contains("--crlf"))
  assert_eq(args.contains("--glob-case-insensitive"), !@sysplatform.linux)
  assert_eq(
    args.contains("--ignore-file-case-insensitive"),
    !@sysplatform.linux,
  )
  assert_false(args.contains("--no-ignore"))
  assert_false(args.contains("--no-ignore-vcs"))
  assert_true(args.contains("--follow"))
  assert_false(args.contains("--text"))
  assert_eq(args[args.length() - 3:], ["--", "Moon", "."])
  let override_args = text_search_args({ ..payload, include_glob: "**/*", })
  let default_exclude = override_args
    .search_by(arg => arg == "!**/.git")
    .unwrap()
  let explicit_include = override_args.search_by(arg => arg == "**/*").unwrap()
  assert_true(explicit_include < default_exclude)
}

///|
test "JavaScript Unicode escapes and double-dash queries use regex arguments" {
  assert_eq(
    text_search_unicode_escapes_to_pcre2("foo\\u1234[\\u{00A0}-\\u00FF]"),
    "foo\\x{1234}[\\x{00A0}-\\x{00FF}]",
  )
  assert_eq(
    text_search_unicode_escapes_to_pcre2("foo\\\\u1234"),
    "foo\\\\u1234",
  )
  let payload : SearchTextPayload = {
    root: "/work",
    query: "--",
    regex: false,
    case_sensitive: true,
    whole_word: false,
    include_glob: "",
    exclude_glob: "",
    session_key: "search:double-dash",
    generation: 3,
    max_results: 20000,
  }
  let args = text_search_args(payload)
  assert_true(args.contains("auto"))
  assert_true(args.contains("\\-\\-"))
  assert_eq(args[args.length() - 2:], ["--", "."])
}

///|
test "ripgrep fatal errors match VS Code classifications and partial results" {
  assert_eq(
    text_search_error("regex parse error:\n  ("),
    ("invalid_regex", "Regex parse error"),
  )
  assert_eq(
    text_search_error("PCRE2: error compiling pattern at offset 1"),
    ("invalid_regex", "Regex parse error: error compiling pattern at offset 1"),
  )
  assert_eq(
    text_search_error("rg: error parsing glob '**/{': unclosed alternate group"),
    ("invalid_glob", "error parsing glob '**/{': unclosed alternate group"),
  )
  assert_eq(
    text_search_error("rg: the literal '\\n' is not allowed"),
    ("invalid_request", "the literal '\\n' is not allowed"),
  )
  assert_eq(
    text_search_error(
      "rg: regex could not be compiled\nregex parse error:\nerror: unclosed group\nPCRE2: error compiling pattern at offset 5: missing closing parenthesis",
    ),
    ("invalid_regex", "Regex parse error: missing closing parenthesis"),
  )
  assert_true(text_search_exit_is_fatal(2, false, false))
  assert_false(text_search_exit_is_fatal(2, false, true))
  assert_false(text_search_exit_is_fatal(2, true, false))
  assert_false(text_search_exit_is_fatal(1, false, false))
}

///|
test "one CRLF ripgrep line preserves multiple occurrence ranges" {
  let json =
    #|{"type":"match","data":{"path":{"text":"src\\main.mbt"},"lines":{"text":"moon moon\r\n"},"line_number":7,"submatches":[{"match":{"text":"moon"},"start":0,"end":4},{"match":{"text":"moon"},"start":5,"end":9}]}}
  guard parse_ripgrep_match(json) is Some(parsed) else {
    fail("expected ripgrep match")
  }
  assert_eq(
    parsed.path,
    if @sysplatform.win32 || @sysplatform.win64 {
      "src/main.mbt"
    } else {
      "src\\main.mbt"
    },
  )
  assert_eq(parsed.line, "moon moon")
  let (projected, count, overflow) = project_text_match(parsed, 2000)
  guard projected is Some(projected) else { fail("expected projected match") }
  assert_eq(projected.ranges, [
    { start_column: 1, end_column: 5, },
    { start_column: 6, end_column: 10, },
  ])
  assert_eq(count, 2)
  assert_false(overflow)
}

///|
test "ripgrep byte records and empty submatches remain visible" {
  let bytes_json =
    #|{"type":"match","data":{"path":{"bytes":"c3JjL21haW4ubWJ0"},"lines":{"bytes":"bW9vbgo="},"line_number":4,"submatches":[]}}
  guard parse_ripgrep_match(bytes_json) is Some(parsed) else {
    fail("expected byte-backed ripgrep match")
  }
  assert_eq(parsed.path, "src/main.mbt")
  assert_eq(parsed.line, "moon")
  assert_eq(parsed.byte_ranges, [(0, 1)])
  let (projected, count, overflow) = project_text_match(parsed, 20000)
  guard projected is Some(projected) else { fail("expected projected match") }
  assert_eq(projected.ranges, [{ start_column: 1, end_column: 2, }])
  assert_eq(count, 1)
  assert_false(overflow)
}

///|
test "long-line previews remain bounded around the first match" {
  let prefix = "x".repeat(600)
  let line = prefix + "moon" + prefix
  let parsed : ParsedTextMatch = {
    path: "long.mbt",
    line,
    line_number: 1,
    byte_ranges: [(600, 604)],
  }
  let (projected, _, _) = project_text_match(parsed, 2000)
  guard projected is Some(projected) else { fail("expected projected match") }
  assert_true(projected.preview.length() <= MaxTextSearchPreviewUnits)
  assert_true(projected.preview_start_column > 1)
  assert_true(projected.preview.contains("moon"))
}

///|
test "occurrence capacity truncates ranges within one matching line" {
  let parsed : ParsedTextMatch = {
    path: "many.mbt",
    line: "moon moon",
    line_number: 1,
    byte_ranges: [(0, 4), (5, 9)],
  }
  let (projected, count, overflow) = project_text_match(parsed, 1)
  guard projected is Some(projected) else { fail("expected projected match") }
  assert_eq(projected.ranges.length(), 1)
  assert_eq(count, 1)
  assert_true(overflow)
}

///|
test "ripgrep failures classify regex and permission diagnostics" {
  assert_eq(
    text_search_error("regex parse error: unclosed group").0,
    "invalid_regex",
  )
  assert_eq(
    text_search_error("Permission denied (os error 13)").0,
    "permission_denied",
  )
  assert_eq(text_search_error("unexpected failure").0, "search_failed")
}

///|
async test "text search replies echo resource-form workspace roots" {
  let root = @pathx.Path(".").resolve()
  let resource_root = root.resource_path()
  let payload : SearchTextPayload = {
    root: resource_root,
    query: "",
    regex: false,
    case_sensitive: false,
    whole_word: false,
    include_glob: "",
    exclude_glob: "",
    session_key: "search:resource-root",
    generation: 3,
    max_results: 20000,
  }
  let reply = run_text_search(None, root, payload)
  assert_eq(reply.root, resource_root)
}

///|
async test "cancel-before-search frontier rejects the stale generation" {
  let service = TextSearchService::TextSearchService()
  @async.with_task_group(group => {
    group.spawn_bg(() => service.run())
    service.cancel("search:stale", 7)
    let root = @pathx.Path(".").resolve()
    let resource_root = root.resource_path()
    let payload : SearchTextPayload = {
      root: resource_root,
      query: "moon",
      regex: false,
      case_sensitive: false,
      whole_word: false,
      include_glob: "",
      exclude_glob: "",
      session_key: "search:stale",
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

///|
test "cancellation frontiers stay bounded across long-lived connections" {
  let frontiers = TextSearchCancellationFrontiers::TextSearchCancellationFrontiers()
  for index in 0..<(MaxTextSearchCancellationFrontiers + 5) {
    frontiers.record("session:\{index}", index)
  }
  assert_eq(frontiers.values.length(), MaxTextSearchCancellationFrontiers)
  assert_eq(frontiers.order.length(), MaxTextSearchCancellationFrontiers)
  assert_eq(frontiers.get("session:0"), -1)
  assert_eq(
    frontiers.get("session:\{MaxTextSearchCancellationFrontiers + 4}"),
    MaxTextSearchCancellationFrontiers + 4,
  )
}
