///|
const MoonCheckTimeoutMs : Int = 30000

///|
const MoonCheckMaxOutputChars : Int = 12000

///|
const MoonCheckCommand : String = "moon check --diagnostic-limit 1"

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
    Some(output) => Some(format_moon_check_output(output))
    None => Some("moon check: timed out")
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
fn format_moon_check_output(output : @shell.ShellOutput) -> String {
  format_moon_check_output_parts(
    output.exit_code,
    output.text,
    output.output_limit_reached,
  )
}

///|
fn format_moon_check_output_parts(
  exit_code : Int?,
  output : String,
  output_limit_reached : Bool,
) -> String {
  let header = match exit_code {
    Some(code) => "moon check:\nexit=\{code}"
    None => "moon check:\nexit=cancelled"
  }
  let header = if output_limit_reached {
    "\{header}\noutput_limit_reached=true"
  } else {
    header
  }
  if output == "" {
    header
  } else {
    "\{header}\n\{output}"
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
test "formats truncated moon check output with metadata" {
  assert_eq(
    format_moon_check_output_parts(None, "long output", true),
    (
      #|moon check:
      #|exit=cancelled
      #|output_limit_reached=true
      #|long output
    ),
  )
}
