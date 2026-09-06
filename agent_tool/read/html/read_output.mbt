// HTML rendering for the `read` tool's stable numbered-output protocol.
//
// The tool result is not the file verbatim: every source line has a
// right-aligned `<number> |` prefix and the result ends with a `<system>` status
// footer. Tokenizing that whole envelope would color the protocol as MoonBit
// and let the footer perturb the lexer. This decoder keeps only the number as
// plain gutter text while passing the source through the editor's shared,
// stateful MoonBit tokenizer.

///|
/// Maximum recorded argument payload worth parsing to discover a read path.
/// A normal read call is a tiny object; the bound keeps a malformed historical
/// transcript from making every collapsed render parse an unbounded string.
const MAX_READ_ARGUMENT_CHARS = 16_000

///|
/// Render a successful numbered `read` result for a MoonBit source path.
///
/// Returns `None` for another file type, malformed arguments, errors, legacy
/// unnumbered output, and empty/range-past-EOF reads. Callers should preserve
/// their existing plain-text rendering in those cases.
pub fn moonbit_output(arguments : String, content : String) -> @rhtml.Html? {
  if arguments.length() > MAX_READ_ARGUMENT_CHARS {
    return None
  }
  let json = @json.parse(arguments) catch { _ => return None }
  let input = @decode.decode(json) catch { _ => return None }
  moonbit_output_for_path(input.path, content)
}

///|
/// Render a numbered result when `path` has a MoonBit source extension.
fn moonbit_output_for_path(path : StringView, content : String) -> @rhtml.Html? {
  // The read body is capped by its canonical decoder. Leave room for the
  // short status footer; older unbounded records use the host's plain fallback.
  guard is_moonbit_source(path) &&
    content.length() <= @decode.hard_max_output_chars + 512 else {
    return None
  }
  let lines = content.split("\n").map(line => line.to_owned()).collect()
  guard lines.last() is Some(status) &&
    status.has_prefix("<system>") &&
    status.has_suffix("</system>") else {
    return None
  }
  let gutters : Array[String] = []
  let source_lines : Array[String] = []
  for line in lines[0:lines.length() - 1] {
    guard numbered_line(line) is Some((gutter, source)) else { return None }
    gutters.push(gutter)
    source_lines.push(source)
  }
  if source_lines.is_empty() {
    return None
  }
  let highlighted = @syntax_html.moonbit_source_lines(source_lines.join("\n"))
  guard highlighted.length() == source_lines.length() else { return None }
  let children = [
    for index, gutter in gutters => {
      @rhtml.span(class="read-moonbit-line", [
        @rhtml.span(class="read-moonbit-gutter", gutter),
        @rhtml.code(class="language-moonbit read-moonbit-code", [
          highlighted[index],
        ]),
      ])
    }
  ]
  children.push(@rhtml.span(class="read-moonbit-status", status))
  Some(@rhtml.span(class="read-moonbit-output moonbit-source", children))
}

///|
/// Render from the read tool's stable `read <basename> (truncated)` brief.
/// Viz result cards use this because calls and results are separate events.
pub fn moonbit_output_for_brief(
  brief : String,
  content : String,
) -> @rhtml.Html? {
  guard brief.strip_prefix("read ") is Some(path_view) else { return None }
  let path = path_view.strip_suffix(" (truncated)").unwrap_or(path_view)
  moonbit_output_for_path(path, content)
}

///|
/// Source/interface/script extensions tokenized by the MoonBit lexer. Markdown
/// files such as `.mbt.md` deliberately stay plain: their outer grammar is
/// Markdown even though fenced snippets may contain MoonBit.
fn is_moonbit_source(path : StringView) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".mbt") ||
  lower.has_suffix(".mbti") ||
  lower.has_suffix(".mbtx")
}

///|
/// Split one stable read-output line into its display number and verbatim
/// source. The protocol's `|` is redundant once HTML supplies real columns.
/// Validation rejects an arbitrary program line containing a pipe, so an older
/// unnumbered result safely falls back to plain text.
fn numbered_line(line : String) -> (String, String)? {
  guard line.split_once("|") is Some((left, source)) else { return None }
  let number = left.trim()
  if number.is_empty() || !number.iter().all(char => char.is_ascii_digit()) {
    return None
  }
  if !left.iter().all(char => char == ' ' || char.is_ascii_digit()) {
    return None
  }
  Some((number.to_owned(), source.to_owned()))
}
