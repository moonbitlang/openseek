///|
const MoonCheckTimeoutMs : Int = 30000

///|
const MoonCheckMaxOutputChars : Int = 12000

///|
const MoonCheckCommand : String = "moon check --diagnostic-limit 1"

///|
const MoonCheckAnalysisCommand : String = "moon check --output-json"

///|
const MoonCheckAnalysisMaxOutputChars : Int = 30000

///|
const DiagnosticLimitWarning : String = "diagnostic output limited by --diagnostic-limit"

///|
const RepeatedUnboundThreshold : Int = 3

///|
const RepeatedUnboundLimit : Int = 5

///|
const UnboundValuePrefix : String = "The value identifier "

///|
const UnboundValueSuffix : String = " is unbound."

///|
/// Append bounded raw `moon check` feedback after successful writes to MoonBit
/// source or manifest files. The check runs from the containing MoonBit module
/// root. Non-MoonBit paths and paths outside a MoonBit module are returned
/// unchanged.
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
  let cwd = match moon_check_cwd(path) {
    Some(cwd) => cwd
    None => return None
  }
  let result = @async.with_timeout_opt(MoonCheckTimeoutMs, () => {
    @shell.collect_shell_output(
      MoonCheckCommand,
      cwd~,
      max_output_chars=MoonCheckMaxOutputChars,
    )
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return Some("moon check: failed to run")
  }
  match result {
    Some(output) => {
      let analysis = moon_check_analysis(cwd, output)
      Some(format_moon_check_output(output, analysis))
    }
    None => Some("moon check: timed out")
  }
}

///|
async fn moon_check_analysis(
  cwd : String,
  compact_output : @shell.ShellOutput,
) -> String? {
  if compact_output.exit_code is Some(0) {
    return None
  }
  if !compact_output.text.contains(DiagnosticLimitWarning) {
    return None
  }
  let result = @async.with_timeout_opt(MoonCheckTimeoutMs, () => {
    @shell.collect_shell_output(
      MoonCheckAnalysisCommand,
      cwd~,
      max_output_chars=MoonCheckAnalysisMaxOutputChars,
    )
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  match result {
    Some(output) => diagnostic_analysis_summary(output.text)
    None => None
  }
}

///|
async fn moon_check_cwd(path : String) -> String? {
  if !is_relevant_moonbit_path(path) {
    return None
  }
  nearest_moon_module_dir(containing_dir(path))
}

///|
fn format_moon_check_output(
  output : @shell.ShellOutput,
  analysis : String?,
) -> String {
  format_moon_check_output_parts(
    output.exit_code,
    output.text,
    output.output_limit_reached,
    analysis,
  )
}

///|
fn format_moon_check_output_parts(
  exit_code : Int?,
  output : String,
  output_limit_reached : Bool,
  analysis : String?,
) -> String {
  let header = match exit_code {
    Some(0) => "moon check:"
    Some(code) => "moon check:\nexit=\{code}"
    None => "moon check:\nexit=cancelled"
  }
  let header = if output_limit_reached {
    "\{header}\noutput_limit_reached=true"
  } else {
    header
  }
  if output == "" {
    append_analysis(header, analysis)
  } else {
    append_analysis("\{header}\n\{output}", analysis)
  }
}

///|
fn append_analysis(output : String, analysis : String?) -> String {
  match analysis {
    Some(analysis) if analysis != "" => "\{output}\n\{analysis}"
    _ => output
  }
}

///|
priv struct RepeatedDiagnostic {
  name : String
  count : Int
}

///|
fn diagnostic_analysis_summary(output : String) -> String? {
  let unbound_values : Map[String, Int] = Map([], capacity=16)
  for line in output.split("\n") {
    let json = @json.parse(line.trim()) catch { _ => continue }
    match json {
      { "level": String("error"), "message": String(message), .. } =>
        match unbound_value_name(message) {
          Some(name) => increment_count(unbound_values, name)
          None => ()
        }
      _ => ()
    }
  }
  let repeated : Array[RepeatedDiagnostic] = []
  for name, count in unbound_values {
    if count >= RepeatedUnboundThreshold {
      repeated.push({ name, count })
    }
  }
  if repeated.is_empty() {
    return None
  }
  repeated.sort_by(fn(left, right) {
    if left.count == right.count {
      left.name.compare(right.name)
    } else {
      right.count.compare(left.count)
    }
  })
  let lines : Array[String] = [
    "analysis:", "- repeated unbound value identifiers:",
  ]
  let limit = if repeated.length() < RepeatedUnboundLimit {
    repeated.length()
  } else {
    RepeatedUnboundLimit
  }
  for i in 0..<limit {
    let item = repeated[i]
    lines.push("  - \{item.name}: \{item.count} diagnostics")
  }
  lines.push(
    "- If these are local helpers you intend to implement, infer their typed signatures from the call sites, declare real stubs with `...`, rerun `moon check`, then remove the stubs before final validation.",
  )
  Some(lines.join("\n"))
}

///|
fn increment_count(counts : Map[String, Int], name : String) -> Unit {
  match counts.get(name) {
    Some(count) => counts.set(name, count + 1)
    None => counts.set(name, 1)
  }
}

///|
fn unbound_value_name(message : String) -> String? {
  if message.has_prefix(UnboundValuePrefix) &&
    message.has_suffix(UnboundValueSuffix) {
    let start = UnboundValuePrefix.length()
    let end = message.length() - UnboundValueSuffix.length()
    if end > start {
      Some(message[start:end].to_owned())
    } else {
      None
    }
  } else {
    None
  }
}

///|
fn is_relevant_moonbit_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path == "moon.mod" ||
  path.has_suffix("/moon.mod") ||
  path == "moon.pkg" ||
  path.has_suffix("/moon.pkg") ||
  is_moonbit_source_path(path)
}

///|
fn is_moonbit_source_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path.has_suffix(".mbt") || path.has_suffix(".mbt.md")
}

///|
fn containing_dir(path : String) -> String {
  let path = path.replace_all(old="\\", new="/")
  match path.rev_find("/") {
    Some(0) => "/"
    Some(cut) => path[:cut].to_owned()
    None => "."
  }
}

///|
async fn nearest_moon_module_dir(start : String) -> String? {
  for dir = start {
    if @fs.exists(join_path(dir, "moon.mod")) {
      return Some(dir)
    }
    match parent_dir(dir) {
      Some(parent) => continue parent
      None => return None
    }
  }
}

///|
fn parent_dir(dir : String) -> String? {
  let normalized = strip_trailing_slash(dir.replace_all(old="\\", new="/"))
  if normalized == "" ||
    normalized == "." ||
    normalized == "/" ||
    is_windows_drive_root(normalized) {
    return None
  }
  match normalized.rev_find("/") {
    Some(0) => Some("/")
    Some(cut) => Some(normalized[:cut].to_owned())
    None => Some(".")
  }
}

///|
fn is_windows_drive_root(path : String) -> Bool {
  path.length() == 2 && path[1] == ':'
}

///|
fn strip_trailing_slash(path : String) -> String {
  if path.length() > 1 && path.has_suffix("/") {
    strip_trailing_slash(path[:path.length() - 1].to_owned())
  } else {
    path
  }
}

///|
fn join_path(dir : String, base : String) -> String {
  if dir == "" || dir == "." {
    base
  } else if dir.has_suffix("/") {
    "\{dir}\{base}"
  } else {
    "\{dir}/\{base}"
  }
}

///|
test "relevant path detection covers MoonBit source and manifests" {
  assert_true(is_relevant_moonbit_path("moon.mod"))
  assert_true(is_relevant_moonbit_path("lib/moon.pkg"))
  assert_true(is_relevant_moonbit_path("lib/parser.mbt"))
  assert_true(is_relevant_moonbit_path("lib/README.mbt.md"))
  assert_false(is_relevant_moonbit_path("lib/parser.mbti"))
  assert_false(is_relevant_moonbit_path("README.md"))
}

///|
test "parent dir stops at filesystem roots" {
  assert_true(parent_dir("/") is None)
  assert_true(parent_dir("C:") is None)
  assert_true(parent_dir("C:/") is None)
  assert_true(parent_dir("C:/work") is Some("C:"))
  assert_true(parent_dir("C:/work/lib") is Some("C:/work"))
}

///|
test "formats raw moon check output with exit code" {
  assert_eq(
    format_moon_check_output_parts(
      Some(255),
      (
        #|Error: Failed to calculate build plan
        #|
        #|Caused by:
        #|    0: Failed to resolve the module dependency graph
      ),
      false,
      None,
    ),
    (
      #|moon check:
      #|exit=255
      #|Error: Failed to calculate build plan
      #|
      #|Caused by:
      #|    0: Failed to resolve the module dependency graph
    ),
  )
}

///|
test "formats successful moon check output without exit code" {
  assert_eq(
    format_moon_check_output_parts(
      Some(0),
      "Finished. moon: ran 2 tasks, now up to date",
      false,
      None,
    ),
    (
      #|moon check:
      #|Finished. moon: ran 2 tasks, now up to date
    ),
  )
}

///|
test "formats truncated moon check output with metadata" {
  assert_eq(
    format_moon_check_output_parts(None, "long output", true, None),
    (
      #|moon check:
      #|exit=cancelled
      #|output_limit_reached=true
      #|long output
    ),
  )
}

///|
test "formats moon check output with analyzer summary" {
  assert_eq(
    format_moon_check_output_parts(
      Some(2),
      "Error: first compact diagnostic",
      false,
      Some(
        (
          #|analysis:
          #|- repeated unbound value identifiers:
          #|  - parse_value: 4 diagnostics
        ),
      ),
    ),
    (
      #|moon check:
      #|exit=2
      #|Error: first compact diagnostic
      #|analysis:
      #|- repeated unbound value identifiers:
      #|  - parse_value: 4 diagnostics
    ),
  )
}

///|
test "diagnostic analyzer summarizes repeated unbound value identifiers" {
  let summary = diagnostic_analysis_summary(
    (
      #|{"level":"error","message":"The value identifier parse_value is unbound."}
      #|{"level":"error","message":"The value identifier parse_key is unbound."}
      #|{"level":"error","message":"The value identifier parse_value is unbound."}
      #|not json
      #|{"level":"warning","message":"The value identifier ignored is unbound."}
      #|{"level":"error","message":"The value identifier parse_value is unbound."}
      #|{"level":"error","message":"The type constructor Missing is unbound."}
    ),
  )
  guard summary is Some(summary) else {
    fail("expected repeated unbound identifier summary")
  }
  assert_true(summary.contains("analysis:"))
  assert_true(summary.contains("parse_value: 3 diagnostics"))
  assert_false(summary.contains("parse_key:"))
  assert_false(summary.contains("ignored:"))
  assert_true(summary.contains("declare real stubs with `...`"))
}

///|
test "diagnostic analyzer ignores identifiers below threshold" {
  assert_true(
    diagnostic_analysis_summary(
      (
        #|{"level":"error","message":"The value identifier parse_key is unbound."}
        #|{"level":"error","message":"The value identifier parse_key is unbound."}
      ),
    )
    is None,
  )
}
