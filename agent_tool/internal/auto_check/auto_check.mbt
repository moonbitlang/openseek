///|
/// Append bounded raw `moon check` feedback after successful writes to MoonBit
/// source or manifest files. The check runs from the containing MoonBit module
/// or workspace root. Non-MoonBit paths and paths outside a MoonBit project are
/// returned unchanged.
pub async fn append_summary(path : String, content : String) -> String {
  let summary = auto_check_summary(path) catch { _ => None }
  match summary {
    Some(summary) => "\{content}\n\{summary}"
    None => content
  }
}

///|
async fn auto_check_summary(path : String) -> String? {
  guard moon_check_cwd(path) is Some(cwd) else { return None }
  let result = @async.with_timeout_opt(@moon_check.TimeoutMs, () => {
    collect_process_output(
      "moon",
      ["check", "--diagnostic-limit", "1"],
      cwd~,
      max_output_chars=@moon_check.MaxOutputChars,
    )
  }) catch {
    _ => return Some("moon check: failed to run")
  }
  match result {
    Some(output) =>
      Some(
        @moon_check.format_output(
          output.exit_code,
          output.text,
          output.output_limit_reached,
        ),
      )
    None => Some("moon check: timed out")
  }
}

///|
/// `moon check --json` prints one complete JSON document: the diagnostics,
/// moon's own messages (a build plan it could not make) and a `summary`
/// whose counts are complete whatever `--diagnostic-limit` left out of the
/// list. The guards decide by those counts; the list carries the sites the
/// identity comparisons and the reports use, and a run that overflows it is
/// marked `truncated` so those comparisons are not mistaken for complete.
const MoonCheckDiagnosticLimit : Int = 1000

///|
/// The document is printed once, at the end, so the capture is all or
/// nothing: room for `MoonCheckDiagnosticLimit` diagnostics with their
/// source excerpts. An overflow is no verdict, not a lower bound.
const MoonCheckJsonMaxOutputChars : Int = 2000000

///|
/// How many individual error diagnostics a revert report surfaces; enough to
/// show the shape of an over-match without dumping a broken build.
const RevertErrorDisplayLimit : Int = 10

///|
/// One `level == "error"` diagnostic: where moon check placed it and what it
/// said. `path` is as moon reported it (relative to the checked module, or
/// absolute — moon has emitted both), and `None` when the diagnostic carried
/// no path at all, so a caller never mistakes "unknown file" for a known one;
/// `loc` is the `line:col-line:col` span, or empty for a module-level error;
/// `code` is moon's numeric `error_code` when the diagnostic carried one.
pub(all) struct ErrorSite {
  path : String?
  loc : String
  code : Int?
  message : String
} derive(Debug, Eq)

///|
/// The site's identity for comparing two check runs: `path:loc#code` when
/// moon supplied an error code, so a reworded message (a moon release, or a
/// message that embeds a count) does not turn a still-present error into a
/// "new" one; the rendered line otherwise.
pub fn ErrorSite::identity(self : ErrorSite) -> String {
  match self.code {
    Some(code) => "\{self.path.unwrap_or("")}:\{self.loc}#\{code}"
    None => self.line()
  }
}

///|
/// The site as a JSON object for a tool's machine-readable `data`: `path`,
/// `loc` and `code` are present only when moon supplied them (a module-level
/// diagnostic has no span), so a consumer branches on absence, never on a
/// sentinel.
pub fn ErrorSite::to_json(self : ErrorSite) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.path is Some(path) {
    fields["path"] = path.to_json()
  }
  if self.loc != "" {
    fields["loc"] = self.loc.to_json()
  }
  if self.code is Some(code) {
    fields["code"] = code.to_json()
  }
  fields["message"] = self.message.to_json()
  Json::object(fields)
}

///|
/// Render the site as `path:loc: message`, the same shape the human
/// `moon check` output uses, so a report points the model straight at the
/// offending line.
pub fn ErrorSite::line(self : ErrorSite) -> String {
  let where_ = match (self.path, self.loc) {
    (Some(path), "") => path
    (Some(path), loc) => "\{path}:\{loc}"
    (None, loc) => loc
  }
  if self.message == "" {
    where_
  } else {
    "\{where_}: \{self.message}"
  }
}

///|
/// A tally of `moon check` diagnostics by severity, with every error and
/// warning site kept so a caller can compare two runs by identity and
/// location, not just by count. The counts are moon's own and always
/// complete; `truncated` means moon hid some sites behind its
/// `--diagnostic-limit`, so the lists (and any identity comparison on them)
/// are a window.
///
/// Not representable here: whether the BUILD stopped early. moon skips the
/// dependents of a failing package, so a run's error list covers only the
/// packages moon compiled, and moon does not say which those were. A caller
/// that compares two runs must reason about that from the package graph (see
/// `package_graph`).
pub(all) struct CheckErrors {
  error_count : Int
  warning_count : Int
  errors : Array[ErrorSite]
  warnings : Array[ErrorSite]
  truncated : Bool
} derive(Debug)

///|
/// How many sites of each severity `to_json` carries. A tally keeps every
/// site for identity comparison; a tool result that travels to a script (and
/// is retained in its trace) does not need thousands of them.
const JsonSiteLimit : Int = 200

///|
/// The tally as machine-readable tool `data`: counts, the first
/// `JsonSiteLimit` sites of each severity, and whether either list was cut,
/// by that limit or by the capture budget.
pub fn CheckErrors::to_json(self : CheckErrors) -> Json {
  fn sites(all : Array[ErrorSite]) -> Json {
    let shown = all.length().min(JsonSiteLimit)
    Json::array([ for site in all[:shown] => site.to_json() ])
  }

  {
    "error_count": self.error_count.to_json(),
    "warning_count": self.warning_count.to_json(),
    "truncated": self.truncated.to_json(),
    "errors": sites(self.errors),
    "errors_truncated": (self.truncated || self.errors.length() > JsonSiteLimit).to_json(),
    "warnings": sites(self.warnings),
    "warnings_truncated": (self.truncated ||
    self.warnings.length() > JsonSiteLimit).to_json(),
  }
}

///|
/// The tally reduced to what a per-edit result should carry: the counts and
/// the first `RevertErrorDisplayLimit` error sites, no warning list. A script
/// that applies one edit per diagnostic already holds the warning list it is
/// working from; repeating it in every reply would spend the retained trace
/// on nothing.
pub fn CheckErrors::summary_json(self : CheckErrors) -> Json {
  let shown = self.errors.length().min(RevertErrorDisplayLimit)
  {
    "error_count": self.error_count.to_json(),
    "warning_count": self.warning_count.to_json(),
    "truncated": self.truncated.to_json(),
    "errors": Json::array([ for site in self.errors[:shown] => site.to_json() ]),
  }
}

///|
/// Two projects' tallies as one: counts add, sites concatenate, and an
/// overflow on either side overflows the sum.
pub fn CheckErrors::merged(
  self : CheckErrors,
  other : CheckErrors,
) -> CheckErrors {
  {
    error_count: self.error_count + other.error_count,
    warning_count: self.warning_count + other.warning_count,
    errors: [..self.errors, ..other.errors],
    warnings: [..self.warnings, ..other.warnings],
    truncated: self.truncated || other.truncated,
  }
}

///|
/// What a change introduced, judged by diagnostic identity rather than
/// position: the sites of the later run whose `(path, code, message)` occurs
/// more often than in the earlier one. Ignoring `loc` keeps an edit's own line
/// shifts from turning every diagnostic below it into a "new" one, and still
/// catches a fix that removes one diagnostic and adds another kind. The blind
/// spot is a change that replaces a diagnostic with an identical one
/// elsewhere, which no count can see either.
///
/// `complete` is false when either capture overflowed its budget: the lists
/// are then windows onto the output rather than the whole of it, so a site can
/// enter the window without being new. Callers decide by count in that case.
pub(all) struct Introduced {
  errors : Array[ErrorSite]
  warnings : Array[ErrorSite]
  complete : Bool
}

///|
/// The diagnostics `after` carries that `before` did not, by identity (see
/// `Introduced`).
pub fn introduced(before : CheckErrors, after : CheckErrors) -> Introduced {
  {
    errors: new_sites(before.errors, after.errors),
    warnings: new_sites(before.warnings, after.warnings),
    complete: !before.truncated && !after.truncated,
  }
}

///|
/// The sites of `after` left over once each `before` site of the same
/// identity has been matched off, in `after`'s order.
fn new_sites(
  before : Array[ErrorSite],
  after : Array[ErrorSite],
) -> Array[ErrorSite] {
  let budget : Map[String, Int] = Map([])
  for site in before {
    let key = site.kind()
    budget[key] = budget.get(key).unwrap_or(0) + 1
  }
  let fresh : Array[ErrorSite] = []
  for site in after {
    let key = site.kind()
    match budget.get(key) {
      Some(left) if left > 0 => budget[key] = left - 1
      _ => fresh.push(site)
    }
  }
  fresh
}

///|
/// The position-free identity `introduced` compares by. `\u{0}` separates the
/// parts so a path and a message can never concatenate into another pair.
fn ErrorSite::kind(self : ErrorSite) -> String {
  let code = self.code.map_or("", code => code.to_string())
  "\{self.path.unwrap_or("")}\u{0}\{code}\u{0}\{self.message}"
}

///|
/// The first few error lines for display: enough to show the shape of an
/// over-match without dumping a broken build.
pub fn CheckErrors::first_errors(self : CheckErrors) -> Array[String] {
  let shown = self.errors.length().min(RevertErrorDisplayLimit)
  [
    for site in self.errors[:shown] => site.line()
  ]
}

///|
/// Run `moon check --json` from the MoonBit module containing `path` and
/// tally diagnostics by level. Returns `None` when `path` is not a relevant
/// MoonBit file, is not inside a MoonBit project, or the check could not run
/// (timed out / failed to spawn) — in every `None` case the caller keeps the
/// batch unguarded, matching `append_summary`'s fail-open behavior.
pub async fn count_errors(path : String) -> CheckErrors? {
  match check(path) {
    Checked(tally) | Failed(_, tally, _) => Some(tally)
    NotApplicable | Unavailable(_) => None
  }
}

///|
/// `count_errors` with its `None` cases told apart, for a caller that reports
/// them differently: a non-MoonBit path gets no check line at all, while a
/// check that could not run deserves a sentence.
pub(all) enum CheckOutcome {
  /// `path` is not a MoonBit source or manifest inside a MoonBit project.
  NotApplicable
  /// The check could not run; carries the reason, e.g. `timed out`.
  Unavailable(String)
  /// moon reported an error of its own rather than a diagnostic — a build
  /// plan it could not make (a broken manifest, a missing dependency), so
  /// the tally says nothing about the tree. Carries the exit code, the tally
  /// for callers that never distinguished this case, and moon's message(s)
  /// so a caller can say WHY the plan failed, not only that it did.
  Failed(Int, CheckErrors, String)
  Checked(CheckErrors)
}

///|
/// Run `moon check --json` for the project containing `path` and tally its
/// diagnostics, or say why that was not possible.
pub async fn check(path : String) -> CheckOutcome {
  guard moon_check_cwd(path) is Some(cwd) else { return NotApplicable }
  let result = @async.with_timeout_opt(@moon_check.TimeoutMs, () => {
    collect_process_output(
      "moon",
      ["check", "--json", "--diagnostic-limit", "\{MoonCheckDiagnosticLimit}"],
      cwd~,
      max_output_chars=MoonCheckJsonMaxOutputChars,
    )
  }) catch {
    _ => return Unavailable("failed to run")
  }
  guard result is Some(output) else { return Unavailable("timed out") }
  if output.output_limit_reached {
    return Unavailable("moon check output exceeded the capture budget")
  }
  guard parse_check_document(output.text) is Some(document) else {
    return Unavailable("moon check did not produce a JSON result")
  }
  // A failure that reported no error diagnostic is moon's own: a build plan
  // it could not make, or a pre-build step that failed (which moon does not
  // message at all). Either way the tally says nothing about the tree.
  if document.failed && document.tally.error_count == 0 {
    let detail = if document.moon_errors.is_empty() {
      "moon reported failure without a message (a pre-build step may have failed)"
    } else {
      document.moon_errors.join("; ")
    }
    Failed(output.exit_code.unwrap_or(0), document.tally, detail)
  } else {
    Checked(document.tally)
  }
}

///|
/// One `moon check --json` document, reduced to what a guard needs: whether
/// moon called the run a failure, its own error messages (a build plan it
/// could not make), and the diagnostic tally.
priv struct CheckDocument {
  failed : Bool
  moon_errors : Array[String]
  tally : CheckErrors
}

///|
/// Read a `moon check --json` document. The `summary` counts are complete
/// whatever `--diagnostic-limit` hid from `diagnostics`; the tally is marked
/// `truncated` when the summary says any site was hidden.
fn parse_check_document(text : String) -> CheckDocument? {
  let json = @json.parse(text) catch { _ => return None }
  guard json
    is {
      "status": String(status),
      "diagnostics": Array(diagnostics),
      "messages": Array(messages),
      "summary": {
        "diagnostic_errors": Number(error_count, ..),
        "diagnostic_warnings": Number(warning_count, ..),
        "hidden_diagnostic_errors"? : hidden_errors,
        "hidden_diagnostic_warnings"? : hidden_warnings,
        ..
      },
      ..
    } else {
    return None
  }
  fn hid(count : Json?) -> Bool {
    count is Some(Number(hidden, ..)) && hidden > 0
  }
  let errors : Array[ErrorSite] = []
  let warnings : Array[ErrorSite] = []
  for diagnostic in diagnostics {
    guard diagnostic
      is {
        "level": String(level),
        "path"? : path_json,
        "error_code"? : code_json,
        "loc"? : Some(String(loc))
        | (_ with loc = ""),
        "message"? : Some(String(message))
        | (_ with message = ""),
        ..
      } else {
      continue
    }
    let path = match path_json {
      Some(String(path)) => Some(path)
      _ => None
    }
    let code = match code_json {
      Some(Number(code, ..)) => Some(code.to_int())
      _ => None
    }
    match level {
      "error" => errors.push({ path, loc, code, message, })
      "warning" => warnings.push({ path, loc, code, message, })
      _ => ()
    }
  }
  let moon_errors : Array[String] = []
  for message in messages {
    if message is { "level": "error", "message": String(text), .. } {
      moon_errors.push(text)
    }
  }
  Some({
    failed: status != "success",
    moon_errors,
    tally: {
      error_count: error_count.to_int(),
      warning_count: warning_count.to_int(),
      errors,
      warnings,
      truncated: hid(hidden_errors) || hid(hidden_warnings),
    },
  })
}

///|
async fn moon_check_cwd(path : String) -> String? {
  if !is_relevant_moonbit_path(path) {
    return None
  }
  @moon_check.nearest_project_dir(containing_dir(path))
}

///|
fn is_relevant_moonbit_path(path : String) -> Bool {
  // A path that ends in a separator names a DIRECTORY, never a manifest, and
  // `path_basename` strips that separator before reporting the last component
  // — so "pkg/moon.pkg/" would come back as "moon.pkg". Rule those out first
  // to keep this predicate's domain exactly what it was when the manifest
  // names were matched as whole final components.
  if path.has_suffix("/") || path.has_suffix("\\") {
    return false
  }
  // `path_basename` treats backslashes as separators, so the manifest names
  // match on Windows too; the source suffixes below contain no separator and
  // so are unaffected by them.
  @workspace_path.path_basename(path) is ("moon.mod" | "moon.pkg" | "moon.work") ||
  path.has_suffix(".mbt") ||
  path.has_suffix(".mbt.md")
}

///|
fn containing_dir(path : String) -> String {
  // `parent_dir` already keeps a leading slash as the root rather than
  // collapsing it to "", and normalizes backslashes. Its `None` cases ("",
  // ".", "/", a bare drive) are unreachable here: the only caller has already
  // passed `path` through `is_relevant_moonbit_path`, so it ends in a manifest
  // name or a source suffix.
  @workspace_path.parent_dir(path).unwrap_or(".")
}

///|
test "relevant path detection covers MoonBit source and manifests" {
  // A trailing separator makes it a directory, not a manifest: the predicate
  // must answer the same here as it did before `path_basename` (which strips
  // that separator) was introduced.
  assert_false(is_relevant_moonbit_path("x/moon.pkg/"))
  assert_false(is_relevant_moonbit_path("moon.mod/"))
  assert_false(is_relevant_moonbit_path("x\\moon.work\\"))
  assert_true(is_relevant_moonbit_path("moon.mod"))
  assert_true(is_relevant_moonbit_path("lib/moon.pkg"))
  assert_true(is_relevant_moonbit_path("moon.work"))
  assert_true(is_relevant_moonbit_path("lib/parser.mbt"))
  assert_true(is_relevant_moonbit_path("lib/README.mbt.md"))
  assert_false(is_relevant_moonbit_path("lib/parser.mbti"))
  assert_false(is_relevant_moonbit_path("README.md"))
}

///|
test "containing dir keeps the root and normalizes separators" {
  assert_eq(containing_dir("lib/parser.mbt"), "lib")
  assert_eq(containing_dir("lib\\parser.mbt"), "lib")
  // A leading slash leaves nothing before it, and the answer is the root.
  assert_eq(containing_dir("/parser.mbt"), "/")
  assert_eq(containing_dir("/work/parser.mbt"), "/work")
  assert_eq(containing_dir("moon.mod"), ".")
}

///|
/// A `moon check --json` document over these diagnostic objects (one per
/// line of `text`), with the summary counts moon would report — plus
/// `hidden_errors` the list does not carry, as `--diagnostic-limit` leaves.
fn document(text : String, hidden_errors~ : Int) -> String {
  let lines = [ for line in text.split("\n") if line != "" => line ]
  let errors = lines
    .filter(line => line.contains("\"level\":\"error\""))
    .length()
  let warnings = lines
    .filter(line => line.contains("\"level\":\"warning\""))
    .length()
  let hidden = if hidden_errors > 0 {
    ",\"hidden_diagnostic_errors\":\{hidden_errors}"
  } else {
    ""
  }
  "{\"version\":1,\"status\":\"failure\",\"diagnostics\":[\{lines.join(",")}],\"messages\":[],\"summary\":{\"moon_errors\":0,\"diagnostic_errors\":\{errors + hidden_errors},\"diagnostic_warnings\":\{warnings}\{hidden}}}"
}

///|
fn tally_of(text : String, hidden_errors? : Int = 0) -> CheckErrors {
  match parse_check_document(document(text, hidden_errors~)) {
    Some(parsed) => parsed.tally
    None => abort("the test document did not parse")
  }
}

///|
test "tally counts errors and warnings from a check document" {
  // Real `moon check --json` diagnostic shapes.
  let text =
    #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"argparse/help.mbt","loc":"128:44-128:50","message":"Warning (deprecated): `length` is deprecated, use `len` instead"}
    #|{"$message_type":"diagnostic","level":"error","error_code":1,"path":"argparse/arg.mbt","loc":"3:1-3:9","message":"Type mismatch: expected Int, got String"}
    #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"argparse/help.mbt","loc":"152:42-152:48","message":"Warning (deprecated): `length` is deprecated, use `len` instead"}
  let tally = tally_of(text)
  assert_eq(tally.error_count, 1)
  assert_eq(tally.warning_count, 2)
  assert_eq(tally.warnings.length(), 2)
  assert_eq(tally.warnings[1], {
    path: Some("argparse/help.mbt"),
    loc: "152:42-152:48",
    code: Some(20),
    message: "Warning (deprecated): `length` is deprecated, use `len` instead",
  })
  assert_eq(tally.truncated, false)
  assert_eq(tally.errors, [
    {
      path: Some("argparse/arg.mbt"),
      loc: "3:1-3:9",
      code: Some(1),
      message: "Type mismatch: expected Int, got String",
    },
  ])
  assert_eq(tally.first_errors(), [
    "argparse/arg.mbt:3:1-3:9: Type mismatch: expected Int, got String",
  ])
}

///|
test "a plan failure document carries moon's message and no diagnostics" {
  // Verbatim `moon check --json` output for a package importing a package
  // that does not exist: no diagnostic, one moon-level error.
  let text =
    #|{"version":1,"status":"failure","diagnostics":[],"messages":[{"$message_type":"moon","level":"error","message":"Failed to calculate build plan: Failed to solve package relationship: Cannot find import 'tmp/broken/nonexistent' in tmp/broken/lib@0.0.0"}],"summary":{"tasks_executed":null,"moon_errors":1,"moon_warnings":0,"diagnostic_errors":0,"diagnostic_warnings":0}}
  guard parse_check_document(text) is Some(parsed) else {
    fail("expected a document")
  }
  assert_true(parsed.failed)
  assert_eq(parsed.moon_errors, [
    "Failed to calculate build plan: Failed to solve package relationship: Cannot find import 'tmp/broken/nonexistent' in tmp/broken/lib@0.0.0",
  ])
  assert_eq(parsed.tally.error_count, 0)
  assert_eq(parsed.tally.errors, [])
  // A failed pre-build step: moon calls the run a failure but says nothing
  // at all, so `failed` is the only signal.
  let prebuild =
    #|{"version":1,"status":"failure","diagnostics":[],"messages":[],"summary":{"tasks_executed":null,"moon_errors":0,"moon_warnings":0,"diagnostic_errors":0,"diagnostic_warnings":0}}
  guard parse_check_document(prebuild) is Some(prebuild) else {
    fail("expected a document")
  }
  assert_true(prebuild.failed)
  assert_eq(prebuild.moon_errors, [])
  assert_eq(prebuild.tally.error_count, 0)
  // Hidden warnings alone also make the lists a window.
  let hidden_warnings =
    #|{"version":1,"status":"failure","diagnostics":[],"messages":[],"summary":{"moon_errors":0,"moon_warnings":1,"diagnostic_errors":0,"diagnostic_warnings":12,"hidden_diagnostic_warnings":12}}
  guard parse_check_document(hidden_warnings) is Some(hidden_warnings) else {
    fail("expected a document")
  }
  assert_true(hidden_warnings.tally.truncated)
  // moon's own warning (e.g. "diagnostic output limited") is not an error.
  let limited =
    #|{"version":1,"status":"failure","diagnostics":[],"messages":[{"$message_type":"moon","level":"warning","message":"diagnostic output limited by --diagnostic-limit: 1 errors and 12 warnings were not displayed."}],"summary":{"moon_errors":0,"moon_warnings":1,"diagnostic_errors":1,"diagnostic_warnings":12,"hidden_diagnostic_errors":1,"hidden_diagnostic_warnings":12}}
  guard parse_check_document(limited) is Some(limited) else {
    fail("expected a document")
  }
  assert_eq(limited.moon_errors, [])
  assert_eq(limited.tally.error_count, 1)
  assert_eq(limited.tally.warning_count, 12)
  assert_true(limited.tally.truncated)
  // Anything else (human output, a cut-off document) is not a result.
  assert_true(
    parse_check_document("Error: Failed to calculate build plan") is None,
  )
  assert_true(parse_check_document("{\"version\":1,\"diagnostics\":[") is None)
}

///|
test "tally caps surfaced errors at the display limit but keeps the full count" {
  let lines : Array[String] = []
  for index in 0..<25 {
    lines.push(
      "{\"$message_type\":\"diagnostic\",\"level\":\"error\",\"path\":\"f\{index}.mbt\",\"loc\":\"1:1-1:2\",\"message\":\"e\{index}\"}",
    )
  }
  let tally = tally_of(lines.join("\n"), hidden_errors=1)
  // The count is moon's, including the site its limit hid.
  assert_eq(tally.error_count, 26)
  // Every listed site is kept for identity comparison; only the display is
  // capped.
  assert_eq(tally.errors.length(), 25)
  assert_eq(tally.first_errors().length(), RevertErrorDisplayLimit)
  assert_eq(tally.first_errors()[0], "f0.mbt:1:1-1:2: e0")
  assert_eq(tally.truncated, true)
}

///|
test "tally renders a diagnostic without a location using just the path" {
  let text =
    #|{"$message_type":"diagnostic","level":"error","path":"a.mbt","message":"module-level boom"}
  let tally = tally_of(text)
  assert_eq(tally.first_errors(), ["a.mbt: module-level boom"])
}

///|
test "tally keeps a diagnostic without a path as an unlocated site" {
  let text =
    #|{"$message_type":"diagnostic","level":"error","loc":"2:1-2:2","message":"nowhere"}
  let tally = tally_of(text)
  assert_eq(tally.errors, [
    { path: None, loc: "2:1-2:2", code: None, message: "nowhere", },
  ])
  assert_eq(tally.first_errors(), ["2:1-2:2: nowhere"])
}

///|
#doc(hidden)
#deprecated
pub extend CheckErrors with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ErrorSite with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ErrorSite with Eq::{equal, not_equal}

///|
test "to_json carries both severities, caps each list, and marks the cut" {
  let tally = tally_of(
    (
      #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"a.mbt","loc":"1:1-1:2","message":"old"}
      #|{"$message_type":"diagnostic","level":"error","path":"a.mbt","message":"module-level boom"}
    ),
  )
  json_inspect(tally.to_json(), content={
    "error_count": 1,
    "warning_count": 1,
    "truncated": false,
    "errors": [{ "path": "a.mbt", "message": "module-level boom" }],
    "errors_truncated": false,
    "warnings": [
      { "path": "a.mbt", "loc": "1:1-1:2", "code": 20, "message": "old" },
    ],
    "warnings_truncated": false,
  })
  let many = tally_of(
    [
      for index in 0..<(JsonSiteLimit + 1) => {
        "{\"$message_type\":\"diagnostic\",\"level\":\"warning\",\"path\":\"f\{index}.mbt\",\"loc\":\"1:1-1:2\",\"message\":\"w\"}"
      }
    ].join("\n"),
  )
  guard many.to_json()
    is {
      "warning_count": Number(count, ..),
      "warnings": Array(shown),
      "warnings_truncated": true,
      ..
    } else {
    fail("unexpected shape: \{many.to_json().stringify()}")
  }
  assert_eq(count.to_int(), JsonSiteLimit + 1)
  assert_eq(shown.length(), JsonSiteLimit)
}

///|
test "introduced compares identities, not positions" {
  fn diag(
    level : String,
    path : String,
    loc : String,
    code : Int,
    message : String,
  ) -> String {
    "{\"$message_type\":\"diagnostic\",\"level\":\"\{level}\",\"error_code\":\{code},\"path\":\"\{path}\",\"loc\":\"\{loc}\",\"message\":\"\{message}\"}"
  }

  // Before: two deprecations and an unused value. After a fix that removed the
  // first deprecation, everything below it moved up a line — and the fix left
  // an unused binding behind.
  let before = tally_of(
    [
      diag("warning", "a.mbt", "3:3-3:9", 20, "use `len` instead"),
      diag("warning", "a.mbt", "9:3-9:9", 20, "use `len` instead"),
      diag("warning", "b.mbt", "2:7-2:8", 2, "Unused variable 'x'"),
    ].join("\n"),
  )
  let after = tally_of(
    [
      diag("warning", "a.mbt", "8:3-8:9", 20, "use `len` instead"),
      diag("warning", "b.mbt", "2:7-2:8", 2, "Unused variable 'x'"),
      diag("warning", "a.mbt", "3:7-3:8", 2, "Unused variable 'tmp'"),
      diag("error", "a.mbt", "4:1-4:2", 1, "Type mismatch"),
    ].join("\n"),
  )
  let delta = introduced(before, after)
  assert_true(delta.complete)
  assert_eq([ for site in delta.warnings => site.line() ], [
    "a.mbt:3:7-3:8: Unused variable 'tmp'",
  ])
  assert_eq([ for site in delta.errors => site.line() ], [
    "a.mbt:4:1-4:2: Type mismatch",
  ])
  // Multiplicity counts: one occurrence before, two after is one new site.
  let doubled = tally_of(
    [
      diag("warning", "b.mbt", "2:7-2:8", 2, "Unused variable 'x'"),
      diag("warning", "b.mbt", "9:7-9:8", 2, "Unused variable 'x'"),
    ].join("\n"),
  )
  assert_eq([ for site in introduced(before, doubled).warnings => site.loc ], [
    "9:7-9:8",
  ])
  // The same identity in another file is a different diagnostic.
  let moved = tally_of(
    diag("warning", "c.mbt", "1:1-1:2", 20, "use `len` instead"),
  )
  assert_eq(introduced(before, moved).warnings.length(), 1)
  // Nothing introduced when the runs match, whatever the positions.
  assert_eq(introduced(after, after).warnings.length(), 0)
  assert_eq(introduced(after, after).errors.length(), 0)
  // A truncated capture makes the comparison a window, not a whole.
  let cut = tally_of("", hidden_errors=1)
  assert_false(introduced(before, cut).complete)
}
