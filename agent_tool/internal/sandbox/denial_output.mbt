///|
/// Guidance for a sandboxed run whose output shows a source-write denial
/// ("Operation not permitted" on a protected source path). Without it the model
/// reads a bare OS error and debugs the filesystem — or worse, tries to escape
/// the sandbox — instead of using `edit`. It lives beside the denial detector
/// because both the foreground runner and the background-job reader need the
/// same explanation for the same recognized condition.
pub let source_write_denial_feedback : String =
  #|run_moonbit sandbox: the "Operation not permitted" failure above is this tool's
  #|sandbox denying a write to a protected MoonBit source file (`*.mbt`, `*.mbti`,
  #|`*.mbt.md`, `moon.mod`/`moon.pkg`/`moon.work`) — not a filesystem or permissions
  #|problem to debug. Snippets run source-write-readonly by design; writing non-source
  #|files (data, logs, reports) stays allowed, and source-writing moon commands
  #|(`moon fmt`, `moon info`, `moon add`, `moon test --update`) are denied here by the
  #|same rule. Do NOT try to work around the block from inside a program (renames,
  #|copies, temp-then-move, or other sandbox escapes) — make source changes with the
  #|line-anchored `edit` tool instead, and keep run_moonbit for commands, compute,
  #|probing, and non-source IO.

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

  // Whether `line` contains `subject` as a complete path component followed
  // by a slash — `repo/` at line start or after a non-path character, but
  // never inside `notrepo/`. Only the character BEFORE the match needs
  // checking; the trailing slash bounds the other side.
  fn names_component_bounded(line : StringView, subject : String) -> Bool {
    let needle = "\{subject}/"
    let mut from = 0
    while true {
      guard line.view(start_offset=from).find(needle) is Some(offset) else {
        break
      }
      let at = from + offset
      if at == 0 {
        return true
      }
      // A preceding separator means the component IS the subject
      // (`./repo/`, `/x/repo/`); any word character means the match sits
      // inside a longer component (`notrepo/`, `not.repo/`).
      let before = line[at - 1]
      if !(before is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-' | '.')) {
        return true
      }
      from = at + needle.length()
    }
    false
  }

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

  // A PROFILE subject that is a protected directory names every path below
  // it: `sh: <subject>/seed.txt: Operation not permitted`. An absolute
  // subject is inherently anchored; a bare basename (`repo`) matches only as
  // a COMPLETE path component after a separator boundary, so
  // `/tmp/notrepo/file` cannot classify. Applied ONLY to the profile's
  // denial subjects — protected source suffixes (`.mbt`, `moon.mod`) name
  // files, and a directory that merely ends like one must not classify.
  fn line_names_denied_dir(line : StringView, subject : String) -> Bool {
    if subject.has_prefix("/") {
      line.contains("\{subject}/")
    } else {
      names_component_bounded(line, subject)
    }
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
        subject != "" &&
        (
          line_names_subject(line, subject) ||
          line_names_denied_dir(line, subject)
        )
      })
    )
  })
}
