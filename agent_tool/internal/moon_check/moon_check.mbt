///|
/// Maximum time a follow-up `moon check` may run.
pub const TimeoutMs : Int = 30000

///|
/// Maximum number of characters captured from a follow-up `moon check`.
pub const MaxOutputChars : Int = 12000

///|
/// Render a captured `moon check` result for inclusion in tool output.
pub fn format_output(
  exit_code : Int?,
  output : String,
  output_limit_reached : Bool,
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
    header
  } else {
    "\{header}\n\{output}"
  }
}

///|
/// Find the nearest ancestor containing a `moon.mod` or `moon.work` marker.
pub async fn nearest_project_dir(start : String) -> String? {
  for dir = start {
    if @fs.exists(@workspace_path.join_child(dir, "moon.mod")) ||
      @fs.exists(@workspace_path.join_child(dir, "moon.work")) {
      return Some(dir)
    }
    match @workspace_path.parent_dir(dir) {
      Some(parent) => continue parent
      None => return None
    }
  }
}
