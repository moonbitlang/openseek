///|
/// Render the read workflow's file sections, preserving surrounding runner
/// diagnostics and non-MoonBit sections verbatim. Numbered source alone goes
/// through the editor tokenizer. File names come from JSON-quoted headings,
/// so a batch needs no tool-specific argument decoding or result metadata.
pub fn read_workflow_output(content : String) -> @rhtml.Html? {
  guard content.length() <= 48_000 else { return None }
  let lines = content.split("\n").map(line => line.to_owned()).collect()
  let children : Array[@rhtml.Html] = []
  let mut highlighted = false
  let mut index = 0
  while index < lines.length() {
    let line = lines[index]
    if file_heading(line) is Some(path) {
      // The numbered body is parsed once, here, and handed to the renderer
      // as gutters and source; the status line that ends the body is what
      // makes the section a complete file result.
      let numbered : Array[(String, String)] = []
      let mut end = index + 1
      while end < lines.length() {
        match numbered_line(lines[end]) {
          Some(pair) => {
            numbered.push(pair)
            end += 1
          }
          None => break
        }
      }
      if end < lines.length() &&
        moonbit_section(path, numbered, lines[end]) is Some(rendered) {
        children.push(@rhtml.span("\{line}\n"))
        children.push(rendered)
        if end + 1 < lines.length() {
          children.push(@rhtml.span("\n"))
        }
        index = end + 1
        highlighted = true
        continue
      }
    }
    children.push(@rhtml.span(line))
    if index + 1 < lines.length() {
      children.push(@rhtml.span("\n"))
    }
    index += 1
  }
  if highlighted {
    Some(@rhtml.span(children))
  } else {
    None
  }
}

///|
fn file_heading(line : String) -> String? {
  guard line.strip_prefix("=== ") is Some(rest) &&
    rest.strip_suffix(" ===") is Some(path) else {
    return None
  }
  let json = @json.parse(path) catch { _ => return None }
  match json {
    String(path) => Some(path)
    _ => None
  }
}

///|
/// Render one file section — its parsed numbered lines and the status line
/// that closes it — when `path` has a MoonBit source extension.
fn moonbit_section(
  path : StringView,
  numbered : Array[(String, String)],
  status : String,
) -> @rhtml.Html? {
  guard is_moonbit_source(path) &&
    !numbered.is_empty() &&
    status.has_prefix("<system>") &&
    status.has_suffix("</system>") else {
    return None
  }
  let highlighted = @syntax_html.moonbit_source_lines(
    numbered.map(pair => pair.1).join("\n"),
  )
  guard highlighted.length() == numbered.length() else { return None }
  let children = [
    for index, pair in numbered => {
      @rhtml.span(class="read-moonbit-line", [
        @rhtml.span(class="read-moonbit-gutter", pair.0),
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
  if number.is_empty() || !number.all(char => char.is_ascii_digit()) {
    return None
  }
  if !left.all(char => char == ' ' || char.is_ascii_digit()) {
    return None
  }
  Some((number.to_owned(), source.to_owned()))
}
