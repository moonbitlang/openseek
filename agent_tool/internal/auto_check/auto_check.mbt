///|
/// Append bounded raw `moon check` feedback after successful writes to MoonBit
/// source or manifest files. The check runs from the containing MoonBit module
/// or workspace root. Non-MoonBit paths and paths outside a MoonBit project are
/// returned unchanged.
pub async fn append_summary(path : String, content : String) -> String {
  let summary = auto_check_summary(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
  match summary {
    Some(summary) => "\{content}\n\{summary}"
    None => content
  }
}

///|
async fn auto_check_summary(path : String) -> String? {
  guard moon_check_cwd(path) is Some(cwd) else { return None }
  let result = @async.with_timeout_opt(@moon_check.TimeoutMs, () => {
    @shell.collect_shell_output(
      @moon_check.Command,
      cwd~,
      max_output_chars=@moon_check.MaxOutputChars,
    )
  }) catch {
    error if @async.is_being_cancelled() => raise error
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
/// `moon check --output-json` emits one JSON diagnostic object per line, so the
/// guardrail can count `level == "error"` exactly instead of parsing the
/// warning-heavy human summary.
const MoonCheckJsonCommand : String = "moon check --output-json"

///|
/// A larger capture budget than the human summary: a project with hundreds of
/// warnings emits a JSON line each, and undercounting would weaken the
/// guardrail. If output still overflows this, `CheckErrors::truncated` is set
/// and the count is a lower bound — which only ever makes the guard fire more
/// readily, never less.
const MoonCheckJsonMaxOutputChars : Int = 400000

///|
/// How many individual error diagnostics a revert report surfaces; enough to
/// show the shape of an over-match without dumping a broken build.
const RevertErrorDisplayLimit : Int = 10

///|
/// A tally of `moon check` diagnostics by severity, with a few formatted error
/// lines for display. `truncated` means moon check produced more output than
/// the capture budget, so `error_count` and `warning_count` are lower bounds.
pub(all) struct CheckErrors {
  error_count : Int
  warning_count : Int
  first_errors : Array[String]
  truncated : Bool
} derive(Debug)

///|
/// Run `moon check --output-json` from the MoonBit module containing `path` and
/// tally diagnostics by level. Returns `None` when `path` is not a relevant
/// MoonBit file, is not inside a MoonBit project, or the check could not run
/// (timed out / failed to spawn) — in every `None` case the caller keeps the
/// batch unguarded, matching `append_summary`'s fail-open behavior.
pub async fn count_errors(path : String) -> CheckErrors? {
  guard moon_check_cwd(path) is Some(cwd) else { return None }
  let result = @async.with_timeout_opt(@moon_check.TimeoutMs, () => {
    @shell.collect_shell_output(
      MoonCheckJsonCommand,
      cwd~,
      max_output_chars=MoonCheckJsonMaxOutputChars,
    )
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  result.map(output => {
    tally_diagnostics(output.text, truncated=output.output_limit_reached)
  })
}

///|
/// Tally `moon check --output-json` output (JSON Lines: one diagnostic object
/// per line) by severity. Lines that are not diagnostic objects — a trailing
/// human summary, a blank line — are ignored, so they never disturb the count.
fn tally_diagnostics(text : String, truncated~ : Bool) -> CheckErrors {
  let mut error_count = 0
  let mut warning_count = 0
  let first_errors : Array[String] = []
  for raw in text.split("\n") {
    // Cheap pre-filter: only diagnostic lines carry a `level` field, so a
    // blank line or a human summary never reaches the JSON parser.
    if !raw.contains("\"level\"") {
      continue
    }
    let json = @json.parse(raw.to_owned()) catch { _ => continue }
    match json {
      {
        "level": String("error"),
        "path"? : Some(String(path))
        | (_ with path = ""),
        "loc"? : Some(String(loc))
        | (_ with loc = ""),
        "message"? : Some(String(message))
        | (_ with message = ""),
        ..
      } => {
        error_count += 1
        if first_errors.length() < RevertErrorDisplayLimit {
          first_errors.push(format_diagnostic_line(path, loc, message))
        }
      }
      { "level": String("warning"), .. } => warning_count += 1
      _ => ()
    }
  }
  { error_count, warning_count, first_errors, truncated, }
}

///|
/// Render one diagnostic object as `path:loc: message`, the same shape the
/// human `moon check` output uses, so a reverted batch points the model
/// straight at the offending sites.
fn format_diagnostic_line(
  path : String,
  loc : String,
  message : String,
) -> String {
  let where_ = if loc == "" { path } else { "\{path}:\{loc}" }
  if message == "" {
    where_
  } else {
    "\{where_}: \{message}"
  }
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
  // `path_basename` treats backslashes as separators, so the manifest names
  // match on Windows too; the source suffixes below contain no separator and
  // so are unaffected by them.
  @workspace_path.path_basename(path) is ("moon.mod" | "moon.pkg" | "moon.work") ||
  is_moonbit_source_path(path)
}

///|
fn is_moonbit_source_path(path : String) -> Bool {
  path.has_suffix(".mbt") || path.has_suffix(".mbt.md")
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
test "tally counts errors and warnings from output-json lines" {
  // Real `moon check --output-json` shapes: one diagnostic object per line.
  let text =
    #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"argparse/help.mbt","loc":"128:44-128:50","message":"Warning (deprecated): `length` is deprecated, use `len` instead"}
    #|{"$message_type":"diagnostic","level":"error","error_code":1,"path":"argparse/arg.mbt","loc":"3:1-3:9","message":"Type mismatch: expected Int, got String"}
    #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"argparse/help.mbt","loc":"152:42-152:48","message":"Warning (deprecated): `length` is deprecated, use `len` instead"}
  let tally = tally_diagnostics(text, truncated=false)
  assert_eq(tally.error_count, 1)
  assert_eq(tally.warning_count, 2)
  assert_eq(tally.truncated, false)
  assert_eq(tally.first_errors.length(), 1)
  assert_eq(
    tally.first_errors[0],
    "argparse/arg.mbt:3:1-3:9: Type mismatch: expected Int, got String",
  )
}

///|
test "tally ignores blank lines and non-diagnostic summary lines" {
  let text =
    #|
    #|{"$message_type":"diagnostic","level":"error","error_code":1,"path":"a.mbt","loc":"1:1-1:2","message":"boom"}
    #|Failed with 265 warnings, 1 errors.
    #|{"not-json
  let tally = tally_diagnostics(text, truncated=false)
  assert_eq(tally.error_count, 1)
  assert_eq(tally.warning_count, 0)
  assert_eq(tally.first_errors.length(), 1)
  assert_eq(tally.first_errors[0], "a.mbt:1:1-1:2: boom")
}

///|
test "tally caps surfaced errors at the display limit but keeps the full count" {
  let lines : Array[String] = []
  for index in 0..<25 {
    lines.push(
      "{\"$message_type\":\"diagnostic\",\"level\":\"error\",\"path\":\"f\{index}.mbt\",\"loc\":\"1:1-1:2\",\"message\":\"e\{index}\"}",
    )
  }
  let tally = tally_diagnostics(lines.join("\n"), truncated=true)
  assert_eq(tally.error_count, 25)
  assert_eq(tally.first_errors.length(), RevertErrorDisplayLimit)
  assert_eq(tally.first_errors[0], "f0.mbt:1:1-1:2: e0")
  assert_eq(tally.truncated, true)
}

///|
test "tally renders a diagnostic without a location using just the path" {
  let text =
    #|{"$message_type":"diagnostic","level":"error","path":"a.mbt","message":"module-level boom"}
  let tally = tally_diagnostics(text, truncated=false)
  assert_eq(tally.first_errors.length(), 1)
  assert_eq(tally.first_errors[0], "a.mbt: module-level boom")
}

///|
pub extend CheckErrors with Debug::{to_repr}
