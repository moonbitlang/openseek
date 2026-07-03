///|
/// Standalone syntax gate for `.mbt` content, built on
/// `moonc compile -stop-after-parsing`: the compiler parses one file with no
/// project context, so candidate content can be validated in a scratch file
/// BEFORE it is written to its destination — a reject leaves no broken file to
/// delete or restore. `-stop-after-parsing` reports only lexer/parser
/// diagnostics (type errors never appear), making this a pure syntax check.
///
/// TODO(.mbt.md): raw moonc lexes markdown files as MoonBit source (the `#`
/// heading and ``` fences themselves become lexing errors), so `.mbt.md`
/// content cannot be gated this way. Gating doc files would need moon's own
/// fenced-block extraction (```moonbit check vs plain fences, nocheck
/// attributes); until then `.mbt.md` writes and edits are not parse-gated.
const MooncParseCommand : String = "moonc compile -no-intermediate-file -stop-after-parsing -error-format json"

///|
/// How many lex/parse errors a reject report surfaces. Each entry carries a
/// source excerpt, and parse errors cascade — a handful shows the shape of the
/// breakage without dumping pages.
pub const ParseErrorDisplayLimit : Int = 5

///|
/// The `error_code` range for lexer and parser diagnostics (e.g. 3001 "Lexing
/// error", 3002 "Parse error"). Codes at 4000 and above are type/resolution
/// errors, which never appear under `-stop-after-parsing` anyway; the range
/// check keeps the gate honest if that ever changes.
const ParseErrorCodeMin : Int = 3000

///|
const ParseErrorCodeMax : Int = 3999

///|
fn is_parse_error_code(fields : Map[String, Json]) -> Bool {
  match fields.get("error_code") {
    Some(Number(code, ..)) => {
      let code = code.to_int()
      code >= ParseErrorCodeMin && code <= ParseErrorCodeMax
    }
    _ => false
  }
}

///|
const MooncParseTimeoutMs : Int = 10000

///|
const MooncParseMaxOutputChars : Int = 200000

///|
/// The scratch file is always named this and the command runs from the scratch
/// directory, so the command line never embeds a host path that would need
/// platform-specific quoting.
const ParseGateFileName : String = "parse_gate.mbt"

///|
/// One lex/parse diagnostic from the gate. `loc` keeps the compiler's
/// `line:col-line:col` shape. `context` is the compiler's own numbered source
/// excerpt — populated when moonc can re-read the file relative to its cwd,
/// which the scratch-dir invocation guarantees; the formatter still falls back
/// to synthesizing an excerpt from the in-memory content when it is empty.
pub(all) struct ParseGateError {
  loc : String
  message : String
  context : String
} derive(Debug)

///|
/// Whether the parse gate applies to `path`: plain `.mbt` only. `.mbt.md` is
/// excluded — see the TODO above.
pub fn is_gateable_path(path : String) -> Bool {
  path.has_suffix(".mbt") && !path.has_suffix(".mbt.md")
}

///|
/// One moonc run over candidate content: the captured lex/parse errors plus
/// whether the output capture was truncated — a truncated capture makes
/// `errors` a LOWER BOUND, not an exact tally, and callers that compare
/// counts must account for that.
pub(all) struct ParseGate {
  errors : Array[ParseGateError]
  truncated : Bool
} derive(Debug)

///|
/// Parse `content` as a single standalone `.mbt` file and return its
/// lex/parse errors (empty `errors` = parses cleanly). Returns `None` when
/// the gate could not run — moonc missing, scratch dir unwritable, timeout —
/// so callers fail open, matching the other auto-check guards.
pub async fn content_parse_errors(content : String) -> ParseGate? {
  let dir = @fs.tmpdir(prefix="openseek-parse-gate-") catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  // Best-effort cleanup on every path; a leaked scratch dir must never turn
  // into a raised error that masks the gate's answer.
  async fn cleanup() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  try {
    @fs.write_file(
      "\{dir}/\{ParseGateFileName}",
      content,
      create_mode=CreateOrTruncate,
    )
    let result = @async.with_timeout_opt(MooncParseTimeoutMs, () => {
      @shell.collect_shell_output(
        "\{MooncParseCommand} \{ParseGateFileName}",
        cwd=dir,
        max_output_chars=MooncParseMaxOutputChars,
      )
    })
    match result {
      Some(output) =>
        decide_parse_gate(
          output.text,
          output.exit_code,
          truncated=output.output_limit_reached,
        )
      None => None
    }
  } catch {
    error if @async.is_being_cancelled() => {
      cleanup()
      raise error
    }
    _ => {
      cleanup()
      None
    }
  } noraise {
    result => {
      cleanup()
      result
    }
  }
}

///|
/// Interpret one moonc run: parse-error diagnostics found → those errors
/// (with `truncated` marking them a lower bound); a clean, untruncated exit
/// with none → an empty tally; anything else (moonc missing → 127, crash,
/// unparseable output, a truncated capture with nothing caught) → `None`, so
/// the caller fails open. The gate must never certify content it did not
/// actually parse to completion.
fn decide_parse_gate(
  text : String,
  exit_code : Int?,
  truncated~ : Bool,
) -> ParseGate? {
  let errors : Array[ParseGateError] = []
  for raw in text.split("\n") {
    if !raw.contains("\"level\"") {
      continue
    }
    let json = @json.parse(raw.to_owned()) catch { _ => continue }
    guard json is Object(fields) else { continue }
    if fields.get("level") is Some(String("error")) &&
      is_parse_error_code(fields) {
      errors.push({
        loc: json_string_field(fields, "loc"),
        message: json_string_field(fields, "message"),
        context: json_string_field(fields, "context"),
      })
    }
  }
  if errors.length() > 0 {
    Some({ errors, truncated })
  } else if truncated {
    // Over the capture limit with no parse errors caught: the run was cut
    // short, so "clean" would be a certification the gate cannot make.
    None
  } else if exit_code is Some(0) {
    Some({ errors: [], truncated: false })
  } else {
    None
  }
}

///|
/// Split `text` on `sep`, returning each piece as an owned `String`.
fn split_owned(text : String, sep : StringView) -> Array[String] {
  text.split(sep).map(s => s.to_owned()).collect()
}

///|
/// Render up to `ParseErrorDisplayLimit` gate errors as
/// `path:loc: message` lines, each followed by a numbered excerpt of the
/// offending lines — the rejected content never lands at its destination, so
/// these excerpts are the model's only view of the broken spot. The compiler's
/// own `context` excerpt is preferred; when it is absent the excerpt is
/// synthesized from the in-memory `content` via the diagnostic's `loc`.
pub fn format_parse_gate_errors(
  display_path : String,
  content : String,
  errors : Array[ParseGateError],
) -> Array[String] {
  let lines = split_owned(content, "\n")
  let shown = if errors.length() < ParseErrorDisplayLimit {
    errors.length()
  } else {
    ParseErrorDisplayLimit
  }
  [
    for error in errors[0:shown] => {
      let header = if error.loc == "" {
        "\{display_path}: \{error.message}"
      } else {
        "\{display_path}:\{error.loc}: \{error.message}"
      }
      let excerpt = if error.context == "" {
        excerpt_for_loc(lines, error.loc)
      } else {
        indent_context(error.context)
      }
      if excerpt == "" {
        header
      } else {
        "\{header}\n\{excerpt}"
      }
    }
  ]
}

///|
/// Indent the compiler's `context` excerpt (numbered source lines, one per
/// `\n`) by two spaces, dropping only the trailing blank line the final `\n`
/// produces — interior blank lines, should moonc ever emit them, are kept so
/// the excerpt stays faithful.
fn indent_context(context : String) -> String {
  let lines = split_owned(context, "\n")
  if !lines.is_empty() && lines[lines.length() - 1] == "" {
    let _ = lines.pop()
  }
  [ for line in lines => "  \{line}" ].join("\n")
}

///|
/// Numbered source excerpt for a `line:col-line:col` location: one line of
/// leading context plus the error span (capped), in the compiler's own
/// `N |text` shape indented by two spaces.
fn excerpt_for_loc(lines : Array[String], loc : String) -> String {
  guard loc_line_span(loc) is Some((start_line, end_line)) else { return "" }
  let first = if start_line <= 1 { 1 } else { start_line - 1 }
  if first > lines.length() {
    return ""
  }
  // Cap the span so a single error covering a huge region cannot flood the
  // report; the error line itself always shows.
  let mut last = if end_line > start_line + 3 {
    start_line + 3
  } else {
    end_line
  }
  if last > lines.length() {
    last = lines.length()
  }
  if last < first {
    last = first
  }
  let width = "\{last}".length()
  let rendered = [
    for number in first..<=last => {
      "  \{pad_line_number(number, width)} |\{lines[number - 1]}"
    }
  ]
  rendered.join("\n")
}

///|
/// The inclusive 1-based `(first, last)` line pair named by a compiler `loc`
/// like `7:1-9:2` (or a bare `7:1`). `None` when the loc is malformed.
fn loc_line_span(loc : String) -> (Int, Int)? {
  let parts = split_owned(loc, "-")
  guard parts.length() >= 1 && parts[0] != "" else { return None }
  guard leading_line_number(parts[0]) is Some(start) else { return None }
  let end = if parts.length() >= 2 {
    match leading_line_number(parts[1]) {
      Some(end) => end
      None => start
    }
  } else {
    start
  }
  Some((start, if end < start { start } else { end }))
}

///|
fn leading_line_number(part : String) -> Int? {
  let digits = match part.find(":") {
    Some(cut) => part[:cut].to_owned()
    None => part
  }
  if digits == "" {
    return None
  }
  let mut value = 0
  for ch in digits {
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
fn pad_line_number(number : Int, width : Int) -> String {
  "\{number}".pad_start(width, ' ')
}

///|
test "decide_parse_gate splits errors, clean, and cannot-run" {
  let broken =
    #|{"$message_type":"diagnostic","level":"error","error_code":3002,"path":"parse_gate.mbt","loc":"5:2-5:2","message":"Parse error, unexpected token `end of file`.","context":"4 |  match x {\n5 |}\n"}
  guard decide_parse_gate(broken, Some(2), truncated=false) is Some(gate) else {
    fail("expected errors")
  }
  assert_eq(gate.errors.length(), 1)
  assert_eq(gate.errors[0].loc, "5:2-5:2")
  assert_eq(gate.errors[0].context, "4 |  match x {\n5 |}\n")
  assert_false(gate.truncated)
  // Clean run: exit 0, no diagnostics.
  guard decide_parse_gate("", Some(0), truncated=false) is Some(clean) else {
    fail("expected clean")
  }
  assert_eq(clean.errors.length(), 0)
  // moonc missing (127) or any failure without parse diagnostics: fail open,
  // never certify unparsed content as clean.
  assert_true(
    decide_parse_gate(
      "sh: moonc: command not found",
      Some(127),
      truncated=false,
    )
    is None,
  )
  assert_true(decide_parse_gate("", None, truncated=false) is None)
  // Warnings alone never count as parse errors.
  let warning =
    #|{"$message_type":"diagnostic","level":"warning","error_code":2,"path":"parse_gate.mbt","loc":"1:1-1:2","message":"unused","context":""}
  assert_true(decide_parse_gate(warning, Some(1), truncated=false) is None)
  // A truncated capture: errors caught are kept as a lower bound; a truncated
  // capture with NOTHING caught cannot certify clean and fails open.
  guard decide_parse_gate(broken, None, truncated=true) is Some(cut) else {
    fail("expected truncated errors")
  }
  assert_true(cut.truncated)
  assert_true(decide_parse_gate("", Some(0), truncated=true) is None)
}

///|
test "format_parse_gate_errors synthesizes numbered excerpts from content" {
  let content =
    #|///|
    #|pub fn f() -> Int {
    #|  let x =
    #|}
  let formatted = format_parse_gate_errors("lib/a.mbt", content, [
    {
      loc: "4:1-4:2",
      message: "Parse error, unexpected token `}`.",
      context: "",
    },
  ])
  assert_eq(formatted.length(), 1)
  assert_eq(
    formatted[0],
    (
      #|lib/a.mbt:4:1-4:2: Parse error, unexpected token `}`.
      #|  3 |  let x =
      #|  4 |}
    ),
  )
}

///|
test "format_parse_gate_errors prefers the compiler's own context excerpt" {
  // The compiler context wins over synthesis; the content lines would say
  // otherwise, proving which source was used.
  let formatted = format_parse_gate_errors("lib/a.mbt", "unrelated\ncontent", [
    {
      loc: "4:1-4:2",
      message: "Parse error, unexpected token `}`.",
      context: "3 |  let x =\n4 |}\n",
    },
  ])
  assert_eq(
    formatted[0],
    (
      #|lib/a.mbt:4:1-4:2: Parse error, unexpected token `}`.
      #|  3 |  let x =
      #|  4 |}
    ),
  )
}

///|
test "format_parse_gate_errors caps at the display limit and handles bad locs" {
  let errors = [
    for index in 0..<9 => {
      (
        {
          loc: "\{index + 1}:1-\{index + 1}:2",
          message: "e\{index}",
          context: "",
        } : ParseGateError)
    }
  ]
  let formatted = format_parse_gate_errors("a.mbt", "one\ntwo\nthree", errors)
  assert_eq(formatted.length(), ParseErrorDisplayLimit)
  // A loc beyond the content and a malformed loc degrade to the bare header.
  let odd = format_parse_gate_errors("a.mbt", "only", [
    { loc: "9:1-9:2", message: "past the end", context: "" },
    { loc: "junk", message: "no loc", context: "" },
    { loc: "", message: "empty loc", context: "" },
  ])
  assert_eq(odd[0], "a.mbt:9:1-9:2: past the end")
  assert_eq(odd[1], "a.mbt:junk: no loc")
  assert_eq(odd[2], "a.mbt: empty loc")
}

///|
test "loc_line_span reads spans, single points, and rejects junk" {
  assert_true(loc_line_span("7:1-9:2") is Some((7, 9)))
  assert_true(loc_line_span("7:1") is Some((7, 7)))
  assert_true(loc_line_span("7") is Some((7, 7)))
  // A reversed span clamps to the start line rather than going negative.
  assert_true(loc_line_span("9:1-7:2") is Some((9, 9)))
  assert_true(loc_line_span("") is None)
  assert_true(loc_line_span("abc:1") is None)
}

///|
/// Real-moonc round trips: unlike `moon check`, the standalone gate can run
/// inside `moon test` safely (no project build lock is involved).
async test "content_parse_errors gates real content through moonc" {
  guard content_parse_errors("///|\npub fn ok() -> Int {\n  42\n}\n")
    is Some(clean) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(clean.errors.length(), 0)
  assert_false(clean.truncated)
  let bad_content = "///|\npub fn bad() -> Int {\n  let x =\n}\n"
  guard content_parse_errors(bad_content) is Some(gate) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(gate.errors.length() > 0)
  assert_true(gate.errors[0].message.contains("Parse error"))
  // Whether the diagnostic carries moonc's own `context` excerpt is
  // toolchain-dependent (nightly emits one, stable omits the field), so
  // assert the gate's actual contract instead: the formatted report always
  // shows a numbered excerpt under the header — the compiler's when present,
  // synthesized from the content via the diagnostic's loc otherwise.
  let formatted = format_parse_gate_errors(
    "candidate.mbt",
    bad_content,
    gate.errors,
  )
  assert_true(formatted.length() > 0)
  assert_true(formatted[0].contains("\n  "))
  // moonc EXITS 0 when its parser recovers from an error (e.g. `&mut` in a
  // parameter type), so the gate must trust captured diagnostics, never the
  // exit code — this content must still be rejected.
  guard content_parse_errors(
      "///|\nfn f(input : String, pos : &mut Int) -> Unit {\n  ignore(input)\n}\n",
    )
    is Some(recovered) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(recovered.errors.length() > 0)
}
