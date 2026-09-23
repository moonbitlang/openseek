///|
test "format_parse_gate_errors synthesizes numbered excerpts from content" {
  let content =
    #|///|
    #|pub fn f() -> Int {
    #|  let x =
    #|}
  let formatted = @auto_check.format_parse_gate_errors("lib/a.mbt", content, [
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
  let formatted = @auto_check.format_parse_gate_errors(
    "lib/a.mbt",
    "unrelated\ncontent",
    [
      {
        loc: "4:1-4:2",
        message: "Parse error, unexpected token `}`.",
        context: (
          #|3 |  let x =
          #|4 |}
          #|
        ),
      },
    ],
  )
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
/// Real-moonc round trips: unlike `moon check`, the standalone gate can run
/// inside `moon test` safely (no project build lock is involved).
async test "content_parse_errors gates real content through moonc" {
  guard @auto_check.content_parse_errors(
      "a.mbt", "///|\npub fn ok() -> Int {\n  42\n}\n",
    )
    is Some(clean) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(clean.errors.length(), 0)
  assert_false(clean.truncated)
  let bad_content = "///|\npub fn bad() -> Int {\n  let x =\n}\n"
  guard @auto_check.content_parse_errors("a.mbt", bad_content) is Some(gate) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(gate.errors.length() > 0)
  assert_true(gate.errors[0].message.contains("Parse error"))
  // Whether the diagnostic carries moonc's own `context` excerpt is
  // toolchain-dependent (nightly emits one, stable omits the field), so
  // assert the gate's actual contract instead: the formatted report always
  // shows a numbered excerpt under the header — the compiler's when present,
  // synthesized from the content via the diagnostic's loc otherwise.
  let formatted = @auto_check.format_parse_gate_errors(
    "candidate.mbt",
    bad_content,
    gate.errors,
  )
  assert_true(formatted.length() > 0)
  assert_true(formatted[0].contains("\n  "))
  // moonc EXITS 0 when its parser recovers from an error (e.g. `&mut` in a
  // parameter type), so the gate must trust captured diagnostics, never the
  // exit code — this content must still be rejected.
  guard @auto_check.content_parse_errors(
      "a.mbt", "///|\nfn f(input : String, pos : &mut Int) -> Unit {\n  ignore(input)\n}\n",
    )
    is Some(recovered) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(recovered.errors.length() > 0)
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
  guard @auto_check.content_parse_errors("README.mbt.md", checked_bad)
    is Some(md) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(md.errors.length() > 0)
  assert_true(md.errors[0].message.contains("Parse error"))
  // The same break behind a plain fence is display-only: syncheck skips it.
  let plain_bad = checked_bad.replace(old="```mbt check", new="```mbt")
  guard @auto_check.content_parse_errors("README.mbt.md", plain_bad)
    is Some(plain) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(plain.errors.length(), 0)
  // Textual moon.mod / moon.pkg: clean parses, then real lex/parse breakage.
  guard @auto_check.content_parse_errors(
      "moon.mod", "name = \"me/proj\"\nversion = \"0.1.0\"\n",
    )
    is Some(mod_ok) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(mod_ok.errors.length(), 0)
  guard @auto_check.content_parse_errors("moon.mod", "name = \"me/proj\n")
    is Some(mod_bad) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(mod_bad.errors.length() > 0)
  guard @auto_check.content_parse_errors(
      "moon.pkg", "import {\n  \"me/proj/lib\",\n}\n",
    )
    is Some(pkg_ok) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_eq(pkg_ok.errors.length(), 0)
  guard @auto_check.content_parse_errors(
      "moon.pkg", "import {\n  \"me/proj/lib\"\n",
    )
    is Some(pkg_bad) else {
    fail("expected the gate to run (is moonc on PATH?)")
  }
  assert_true(pkg_bad.errors.length() > 0)
  // A non-syncheck path never runs the gate — the caller fails open.
  assert_true(
    @auto_check.content_parse_errors("moon.work", "members = [ ]\n") is None,
  )
}
