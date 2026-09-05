///|
/// Standalone syntax gate built on `moonc syncheck`, moonc's dedicated
/// parse-only front end: it lexes and parses one file with no project context
/// and reports lexer/parser diagnostics as JSON (type and resolution errors do
/// not gate — see `is_parse_error_code`), so candidate content can be validated
/// in a scratch file BEFORE it lands at its destination — a reject leaves no
/// broken file to delete or restore.
///
/// `syncheck` recognizes its input kind by name (see `gate_scratch_name`):
/// `.mbt` source; `.mbt.md` doc files, where it parses only the ` ```mbt check `
/// and ` ```moonbit check ` fenced blocks and skips plain and `nocheck` fences,
/// matching moon's own extraction; and the textual `moon.mod` / `moon.pkg`
/// config files. `moon.work` and the legacy `*.json` config files are not
/// `syncheck` inputs, so they are not gated.
const MooncSyncheckCommand : String = "moonc syncheck -error-format json"

///|
/// How many lex/parse errors a reject report surfaces. Each entry carries a
/// source excerpt, and parse errors cascade — a handful shows the shape of the
/// breakage without dumping pages.
const ParseErrorDisplayLimit : Int = 5

///|
/// The `error_code` range for lexer and parser diagnostics (e.g. 3001 "Lexing
/// error", 3002 "Parse error"). Codes at 4000 and above are type/resolution
/// errors — including the `moon.pkg` / `moon.mod` config-validation diagnostics
/// (e.g. 4192 "Invalid configuration") that syncheck emits alongside genuine
/// parse errors. Those are semantic, not syntactic, and may be a legitimate
/// transient state mid-edit, so the range check keeps the gate to pure syntax,
/// matching how `.mbt` type errors never gate.
const ParseErrorCodeMin : Int = 3000

///|
const ParseErrorCodeMax : Int = 3999

///|
fn is_parse_error_code(code : Double) -> Bool {
  let code = code.to_int()
  code >= ParseErrorCodeMin && code <= ParseErrorCodeMax
}

///|
const MooncParseTimeoutMs : Int = 10000

///|
const MooncParseMaxOutputChars : Int = 200000

///|
/// The scratch-file basename `moonc syncheck` needs for `path`'s input kind, or
/// `None` when `path` is not a syncheck input (so the gate does not apply).
/// syncheck keys off the name: `.mbt` / `.mbt.md` match by suffix, while
/// `moon.mod` / `moon.pkg` must be that EXACT basename (a `foo.moon.pkg` or a
/// `moon.pkg.json` is not recognized). The manifest classifiers are shared with
/// the write/edit tools, so they normalize Windows separators the same way. The
/// command always runs from the scratch directory against this bare name, so the
/// command line never embeds a host path that would need platform-specific
/// quoting.
fn gate_scratch_name(path : String) -> String? {
  if path.has_suffix(".mbt.md") {
    Some("parse_gate.mbt.md")
  } else if path.has_suffix(".mbt") {
    Some("parse_gate.mbt")
  } else if @manifest_path.is_moon_mod_path(path) {
    Some("moon.mod")
  } else if @manifest_path.is_moon_pkg_path(path) {
    Some("moon.pkg")
  } else {
    None
  }
}

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
/// Whether the parse gate applies to `path` — i.e. `moonc syncheck` accepts its
/// input kind: `.mbt`, `.mbt.md`, or an exact `moon.mod` / `moon.pkg`.
fn is_gateable_path(path : String) -> Bool {
  gate_scratch_name(path) is Some(_)
}

///|
/// The distinct syncheck input KINDS named by `path` and its resolved symlink
/// `target`, as representative paths to hand to `content_parse_errors`. Usually
/// one entry: a regular file (where `target` is the same file), or a symlink
/// whose link and target share a kind, or where only one side is a syncheck
/// input. Two entries when a symlink CROSSES kinds, e.g. `link.mbt ->
/// doc.mbt.md`: moon's classification of such a link is ambiguous — it may key
/// off the directory entry it globs OR the file it resolves to — so the gate
/// checks BOTH kinds and a caller rejects if either flags the candidate. `path`
/// is listed first so a reject prefers the caller's own spelling. Pass the same
/// value for `path` and `target` when there is no symlink to resolve.
pub fn gate_paths(path : String, target : String) -> Array[String] {
  let paths : Array[String] = []
  let names : Array[String] = []
  for candidate in [path, target] {
    guard gate_scratch_name(candidate) is Some(name) else { continue }
    if names.contains(name) {
      continue
    }
    names.push(name)
    paths.push(candidate)
  }
  paths
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
/// Parse `content` as the standalone `moonc syncheck` input named by `path`'s
/// kind and return its lex/parse errors (empty `errors` = parses cleanly).
/// `path` only selects the scratch-file name (its input kind) — it is never
/// read from disk. Returns `None` when the gate could not run — `path` is not a
/// syncheck input, moonc missing, scratch dir unwritable, timeout — so callers
/// fail open, matching the other auto-check guards.
pub async fn content_parse_errors(
  path : String,
  content : String,
) -> ParseGate? {
  guard gate_scratch_name(path) is Some(scratch_name) else { return None }
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
      "\{dir}/\{scratch_name}",
      content,
      create_mode=CreateOrTruncate,
    )
    let result = @async.with_timeout_opt(MooncParseTimeoutMs, () => {
      @shell.collect_shell_output(
        "\{MooncSyncheckCommand} \{scratch_name}",
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
    match json {
      {
        "level": String("error"),
        "error_code": Number(code, ..),
        "loc"? : Some(String(loc))
        | (_ with loc = ""),
        "message"? : Some(String(message))
        | (_ with message = ""),
        "context"? : Some(String(context))
        | (_ with context = ""),
        ..
      } if is_parse_error_code(code) => errors.push({ loc, message, context, })
      _ => ()
    }
  }
  if errors.length() > 0 {
    Some({ errors, truncated, })
  } else if truncated {
    // Over the capture limit with no parse errors caught: the run was cut
    // short, so "clean" would be a certification the gate cannot make.
    None
  } else if exit_code is Some(0) {
    Some({ errors: [], truncated: false, })
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
  let shown = errors.length().min(ParseErrorDisplayLimit)
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
  if lines is [.., ""] {
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
  // report; the error line itself always shows. The early return above
  // guarantees `first <= lines.length()`, so the clamp bounds are ordered.
  let last = end_line.min(start_line + 3).clamp(min=first, max=lines.length())
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
  // Two anchored shapes: `start[:col]-end[:col]` and a bare `start[:col]`.
  // An end that does not open with digits (or is missing) falls back to the
  // start line, matching the compiler's lenient loc forms; parse failures on
  // validated digit runs can only be overflow, which is malformed too.
  lexmatch loc {
    (re"^[0-9]+" as start) +
    re"(:[^\-]*)?-" +
    (re"[0-9]+" as end_) +
    re"(:.*)?$" => {
      let start = @string.parse_int(start) catch { _ => return None }
      let end_ = @string.parse_int(end_) catch { _ => return None }
      Some((start, if end_ < start { start } else { end_ }))
    }
    (re"^[0-9]+" as start) + re"(:.*|-.*)?$" => {
      let start = @string.parse_int(start) catch { _ => return None }
      Some((start, start))
    }
    _ => None
  }
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
      context: (
        #|3 |  let x =
        #|4 |}
        #|
      ),
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
    { loc: "9:1-9:2", message: "past the end", context: "", },
    { loc: "junk", message: "no loc", context: "", },
    { loc: "", message: "empty loc", context: "", },
  ])
  assert_eq(odd[0], "a.mbt:9:1-9:2: past the end")
  assert_eq(odd[1], "a.mbt:junk: no loc")
  assert_eq(odd[2], "a.mbt: empty loc")
}

///|
/// Real-moonc round trips: unlike `moon check`, the standalone gate can run
/// inside `moon test` safely (no project build lock is involved).
async test "content_parse_errors gates real content through moonc" {
  guard content_parse_errors("a.mbt", "///|\npub fn ok() -> Int {\n  42\n}\n")
    is Some(clean) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(clean.errors.length(), 0)
  assert_false(clean.truncated)
  let bad_content = "///|\npub fn bad() -> Int {\n  let x =\n}\n"
  guard content_parse_errors("a.mbt", bad_content) is Some(gate) else {
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
      "a.mbt", "///|\nfn f(input : String, pos : &mut Int) -> Unit {\n  ignore(input)\n}\n",
    )
    is Some(recovered) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(recovered.errors.length() > 0)
}

///|
/// `is_gateable_path` matches exactly the input kinds `moonc syncheck` accepts:
/// `.mbt`, `.mbt.md`, and an exact `moon.mod` / `moon.pkg` basename. Nested
/// config files count; prefixed names (`x.moon.pkg`) and the legacy JSON /
/// `moon.work` files do not.
test "is_gateable_path covers syncheck input kinds only" {
  assert_true(is_gateable_path("lib/a.mbt"))
  assert_true(is_gateable_path("README.mbt.md"))
  assert_true(is_gateable_path("moon.mod"))
  assert_true(is_gateable_path("sub/pkg/moon.pkg"))
  // Windows separators classify like their POSIX form (shared manifest helpers).
  assert_true(is_gateable_path("C:\\ws\\pkg\\moon.pkg"))
  assert_true(is_gateable_path("C:\\ws\\moon.mod"))
  // Not syncheck inputs.
  assert_false(is_gateable_path("notes.md"))
  assert_false(is_gateable_path("moon.work"))
  assert_false(is_gateable_path("moon.mod.json"))
  assert_false(is_gateable_path("moon.pkg.json"))
  assert_false(is_gateable_path("x.moon.pkg"))
  assert_false(is_gateable_path("config.json"))
}

///|
/// Real-syncheck round trips for the non-`.mbt` kinds. `.mbt.md` gates only the
/// checked fenced blocks: a broken ` ```mbt check ` block is rejected, while the
/// same break behind a plain (unchecked) fence is not, matching moon's own
/// extraction. `moon.mod` / `moon.pkg` gate the textual config grammar.
async test "content_parse_errors gates .mbt.md, moon.mod and moon.pkg" {
  let checked_bad =
    #|# Title
    #|
    #|```mbt check
    #|///|
    #|pub fn bad() -> Int {
    #|  let x =
    #|}
    #|```
  guard content_parse_errors("README.mbt.md", checked_bad) is Some(md) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(md.errors.length() > 0)
  assert_true(md.errors[0].message.contains("Parse error"))
  // The same break behind a plain fence is display-only: syncheck skips it.
  let plain_bad = checked_bad.replace(old="```mbt check", new="```mbt")
  guard content_parse_errors("README.mbt.md", plain_bad) is Some(plain) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(plain.errors.length(), 0)
  // Textual moon.mod / moon.pkg: clean parses, then real lex/parse breakage.
  guard content_parse_errors(
      "moon.mod", "name = \"me/proj\"\nversion = \"0.1.0\"\n",
    )
    is Some(mod_ok) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(mod_ok.errors.length(), 0)
  guard content_parse_errors("moon.mod", "name = \"me/proj\n") is Some(mod_bad) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(mod_bad.errors.length() > 0)
  guard content_parse_errors("moon.pkg", "import {\n  \"me/proj/lib\",\n}\n")
    is Some(pkg_ok) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(pkg_ok.errors.length(), 0)
  guard content_parse_errors("moon.pkg", "import {\n  \"me/proj/lib\"\n")
    is Some(pkg_bad) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(pkg_bad.errors.length() > 0)
  // A non-syncheck path never runs the gate — the caller fails open.
  assert_true(content_parse_errors("moon.work", "members = [ ]\n") is None)
}

///|
/// Fidelity table for the compiler's lenient loc forms: bare starts, missing
/// or malformed ends (which fall back to the start line), and reversed spans
/// (clamped to the start).
test "loc_line_span accepts every lenient loc form" {
  debug_inspect(loc_line_span("7:1-9:2"), content="Some((7, 9))")
  debug_inspect(loc_line_span("7:1"), content="Some((7, 7))")
  debug_inspect(loc_line_span("7"), content="Some((7, 7))")
  debug_inspect(loc_line_span("7-9"), content="Some((7, 9))")
  debug_inspect(loc_line_span("7-x"), content="Some((7, 7))")
  debug_inspect(loc_line_span("7-"), content="Some((7, 7))")
  debug_inspect(loc_line_span("7:1-x"), content="Some((7, 7))")
  debug_inspect(loc_line_span("7:1-"), content="Some((7, 7))")
  debug_inspect(loc_line_span("9:2-7:1"), content="Some((9, 9))")
  debug_inspect(loc_line_span("9:1-7:2"), content="Some((9, 9))")
  debug_inspect(loc_line_span("x"), content="None")
  debug_inspect(loc_line_span("abc:1"), content="None")
  debug_inspect(loc_line_span(""), content="None")
  debug_inspect(loc_line_span(":1"), content="None")
}

///|
pub extend ParseGate with Debug::{to_repr}

///|
pub extend ParseGateError with Debug::{to_repr}
