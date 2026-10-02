// The `<user_shell_command>` envelope: the text protocol that carries a `!`
// shell command and its captured result as the content of a `kind=command`
// steer. `encode` builds the envelope a client hands the engine, which stores
// it as a durable user message; `parse` recovers it when a transcript renders
// that message (live or resumed). The two are a matched pair shared by every
// client that offers `!` commands (the terminal UI and the desktop app), so the
// format lives in one place and neither end can drift from the other.
// Rendering (titles, markers, truncation notes) stays with the caller — this
// package only owns the wire form.
//
// The payloads are interpolated raw, NOT escaped or length-prefixed, and that
// is intentional. This envelope mirrors Codex's `ContextualUserFragment`: it is
// read by the *model* as natural tagged context, so readability of the inner
// text is the priority — JSON-encoding or escaping it would trade that away. We
// accept the consequence that a command or output line that is itself exactly a
// delimiter (`</command>`, `</result>`, `</user_shell_command>`, a leading
// `exit=`/`error running shell:`) can confuse `parse`. The blast radius is
// contained: the engine only stores this text (it never parses it), and the
// model tolerates the occasional stray tag. The sole failure mode is a
// pathological command rendering as a plain user message or a slightly off
// card — cosmetic and rare, not corruption. If stricter recovery is ever
// wanted, harden `parse` (e.g. match closing tags from the end inward) rather
// than reaching for an unreadable encoding.

///|
/// The result of running a shell command line: the `exit_code` (`None` if the
/// command was cut off at the output cap before it exited), the merged
/// stdout+stderr `text` (truncated to the client's character budget), and
/// whether that truncation happened.
pub(all) struct ShellOutput {
  exit_code : Int?
  text : String
  output_limit_reached : Bool
}

///|
/// A `<user_shell_command>` envelope parsed back into its parts.
///
/// `exit` is kept as the raw protocol token rather than an interpreted status:
/// `"0"` for success, a numeric string for a non-zero code, `"cancelled"` for a
/// truncated/cancelled run, or `"failed"` when the command could not be run.
/// The caller decides how each renders. `output` is the captured lines with the
/// metadata preamble already stripped; `output_limit_reached` flags that the
/// shell collector hit its character cap.
pub struct ShellCommand {
  command : String
  exit : String
  output : Array[String]
  output_limit_reached : Bool
}

///|
/// Encode a `!` command and its result into the `<user_shell_command>`
/// envelope stored as durable user context. A successful run carries its exit
/// code and captured output (with truncation metadata when the cap was hit); a
/// command that could not be run carries the `error running shell:` diagnostic.
pub fn encode(command : String, result : Result[ShellOutput, Error]) -> String {
  let result_text = match result {
    Ok(result) => shell_result_text(result)
    Err(error) => "error running shell: \{error}"
  }
  (
    $|<user_shell_command>
    $|<command>
    $|\{command}
    $|</command>
    $|<result>
    $|\{result_text}
    $|</result>
    $|</user_shell_command>
  )
}

///|
/// Parse a `<user_shell_command>` envelope back into its parts, or `None` if
/// `content` is not a well-formed envelope (an ordinary user message). The
/// structure is validated strictly — both tags present, in order, with the
/// expected blank-line tail — so a prompt that merely mentions the tags is not
/// misread as command context.
pub fn parse(content : String) -> ShellCommand? {
  let lines = [
    for raw in content.split("\n") => raw.trim_end(chars="\r").to_owned()
  ]
  // <user_shell_command>/<command> open the envelope; the command body runs to
  // </command>, immediately followed by <result>; the result body runs to
  // </result>, closed by </user_shell_command> and an optional trailing blank.
  // The two bodies are variable-length, so each end is found rather than matched
  // (one array pattern can bind only a single `..`).
  guard lines is ["<user_shell_command>", "<command>", .. body] else {
    return None
  }
  guard body.search("</command>") is Some(command_end) else { return None }
  guard body[command_end + 1:] is ["<result>", .. result] else { return None }
  guard result.search("</result>") is Some(result_end) else { return None }
  guard result[result_end + 1:]
    is (["</user_shell_command>"] | ["</user_shell_command>", ""]) else {
    return None
  }
  parse_shell_result(body[:command_end].join("\n"), result[:result_end])
}

///|
fn exit_header(exit_code : Int?) -> String {
  if exit_code is Some(code) {
    "exit=\{code}"
  } else {
    "exit=cancelled"
  }
}

///|
fn shell_result_text(result : ShellOutput) -> String {
  if result.output_limit_reached {
    let shown_chars = result.text.char_length()
    (
      $|\{exit_header(result.exit_code)}
      $|truncated=true
      $|output_limit_reached=true
      $|shown_chars=\{shown_chars}
      $|max_output_chars=\{shown_chars}
      $|\{result.text}
    )
  } else {
    let code = result.exit_code.unwrap_or(0)
    (
      $|exit=\{code}
      $|\{result.text}
    )
  }
}

///|
/// Parse the lines between `<result>` and `</result>` and combine them with the
/// already-parsed `command` into a `ShellCommand`. Returns `None` only when the
/// result body is malformed (a non-`exit=` first line that is not an
/// `error running shell:` diagnostic); an empty body is a failed run.
fn parse_shell_result(
  command : String,
  lines : ArrayView[String],
) -> ShellCommand? {
  guard lines is [first, .. rest] else {
    return Some({
      command,
      exit: "failed",
      output: [],
      output_limit_reached: false,
    })
  }
  if first.has_prefix("error running shell:") {
    return Some({
      command,
      exit: "failed",
      output: lines.to_owned(),
      output_limit_reached: false,
    })
  }
  guard first is [.. "exit=", .. exit] else { return None }
  // `encode` emits the truncation preamble as one fixed four-line block — and
  // only for a truncated run — so recognize that exact block as a unit rather
  // than greedily stripping any leading `key=value` line. Otherwise a
  // non-truncated command whose real output merely begins with a line like
  // `truncated=true` would have it dropped (and the card falsely marked
  // truncated). Anything that is not the full preamble is real output.
  let output_limit_reached = is_truncation_preamble(rest)
  let output = if output_limit_reached { rest[4:] } else { rest }
  Some({
    command,
    exit: exit.to_owned(),
    output: output.to_owned(),
    output_limit_reached,
  })
}

///|
/// Whether `lines` opens with the exact four-line preamble `encode` writes for a
/// truncated run: the `truncated`, `output_limit_reached`, `shown_chars`,
/// `max_output_chars` keys, in that order (any real output may follow).
fn is_truncation_preamble(lines : ArrayView[String]) -> Bool {
  lines
  is [
    [.. "truncated=", ..],
    [.. "output_limit_reached=", ..],
    [.. "shown_chars=", ..],
    [.. "max_output_chars=", ..],
    ..,
  ]
}
