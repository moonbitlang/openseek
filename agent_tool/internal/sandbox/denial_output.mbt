///|
/// Protected MoonBit source and manifest names, as they appear at the end of a
/// path in a denial line. Matched with `line_names_subject`, so `.mbt` does not
/// also cover `.mbt.md` — both are listed.
let protected_source_subjects : ReadOnlyArray[String] = [
  ".mbt.md", ".mbt", ".mbti", "moon.mod.json", "moon.pkg.json", "moon.mod", "moon.pkg",
  "moon.work",
]

///|
/// Return whether child-process output contains a likely protected-source
/// write denial. This is the private engine behind
/// `SandboxedCommand::output_reports_denial`; `denial_output_wbtest.mbt` holds
/// the exhaustive line-level pins.
///
/// Matching is line-oriented. A line must contain a recognized
/// "Operation not permitted" or "Permission denied" form and name either a
/// protected source suffix or one of `denial_subjects` (the directories the
/// profile denies literally — a denied directory carries no protected
/// suffix, so only its subject can recognize it). Unrelated permission
/// errors and mentions of source files without a denial are ignored.
fn source_write_denied_in_text(
  output_text : String,
  denial_subjects : Array[String],
) -> Bool {

  // Whether `line` names `subject` as the object of an error rather than merely
  // containing it as a substring: the tool's own punctuation or quoting follows
  // it, or the line ends with it after a denial's colon.
  //
  // Shared by the protected-suffix scan and the profile's denial subjects, which
  // need the identical notion of "names".
  fn line_names_subject(line : StringView, subject : String) -> Bool {
    line.contains("\{subject}:") ||
    line.contains("\{subject}'") ||
    line.contains("\{subject}\"") ||
    // MoonBit's own OSError Show output escapes the quotes around the path
    // (`@fs.open(): \"keep.mbt\": Operation not permitted`), so the subject is
    // followed by `\"`, not a bare quote — run_moonbit's denial shape.
    line.contains("\{subject}\\\"") ||
    line.contains("\{subject}`") ||
    (
      (
        line.contains("Operation not permitted:") ||
        line.contains("operation not permitted:") ||
        line.contains("Permission denied:")
      ) &&
      line.has_suffix(subject)
    )
  }

  output_text
  .split("\n")
  .any(line => {
    // Both halves must hold on the SAME line. Checking them across the whole
    // output would match any log that mentions a source file and, separately,
    // hits an unrelated permission error.
    let mentions_denial = line.contains("Operation not permitted") ||
      line.contains("operation not permitted") ||
      line.contains(": Permission denied") ||
      line.contains("Permission denied:")
    mentions_denial &&
    (
      protected_source_subjects.any(suffix => line_names_subject(line, suffix)) ||
      denial_subjects.any(subject => {
        subject != "" && line_names_subject(line, subject)
      })
    )
  })
}
