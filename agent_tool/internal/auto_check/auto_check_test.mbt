///|
/// Writes the `moon.mod` + `moon.pkg` fixture pair a checkable module needs;
/// tests whose manifest is itself under test keep explicit writes.
async fn write_module(dir : String, name : String) -> Unit {
  @fs.write_file(
    "\{dir}/moon.mod",
    "name = \"\{name}\"\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{dir}/moon.pkg",
    "warnings = \"+unnecessary_annotation\"\n",
    create_mode=CreateOrTruncate,
  )
}

///|
async test "append_summary runs compact check for MoonBit source" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-", dir => {
    write_module(dir, "tmp/auto_check")
    let path = "\{dir}/main.mbt"
    @vfs.FileSystem({ "main.mbt": "fn main {\n  let x = missing\n}\n" }).write_to(
      dir,
    )
    let result = @auto_check.append_summary(
      path,
      "ok: wrote 28 chars to \{path}",
    )
    assert_true(
      result.has_prefix("ok: wrote 28 chars to \{path}\nmoon check:\nexit="),
    )
    assert_true(result.contains("Error:"))
    assert_false(result.contains("first error:"))
    assert_false(result.contains("moon check: 0 errors, 0 warnings"))
  })
}

///|
async test "append_summary checks from module root for nested source" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-root-", dir => {
    write_module(dir, "tmp/auto_check_root")
    @fs.write_file(
      "\{dir}/root_bad.mbt",
      "pub fn root_bad() -> Int { missing_from_root }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{dir}/scratch")
    let path = "\{dir}/scratch/note.mbt"
    @vfs.FileSystem({ "scratch/note.mbt": "pub fn draft() -> Int { 1 }\n" }).write_to(
      dir,
    )
    let result = @auto_check.append_summary(path, "ok: wrote nested source")
    assert_true(
      result.has_prefix("ok: wrote nested source\nmoon check:\nexit="),
    )
    assert_true(result.contains("root_bad.mbt"))
    assert_true(result.contains("missing_from_root"))
  })
}

///|
async test "append_summary runs compact check for MoonBit markdown source" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-md-", dir => {
    write_module(dir, "tmp/auto_check_md")
    let path = "\{dir}/README.mbt.md"
    @fs.write_file(
      path,
      (
        #|```mbt check
        #|test { let x = missing }
        #|```
        #|
      ),
      create_mode=CreateOrTruncate,
    )
    let result = @auto_check.append_summary(path, "ok: edited markdown source")
    assert_true(
      result.has_prefix("ok: edited markdown source\nmoon check:\nexit="),
    )
    assert_true(result.contains("Error:"))
    assert_false(result.contains("first error:"))
  })
}

///|
async test "append_summary surfaces raw moon check failure" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-manifest-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check_manifest\"\n",
      create_mode=CreateOrTruncate,
    )
    let path = "\{dir}/moon.pkg"
    @vfs.FileSystem({ "moon.pkg": "warnings = \"+unnecessary_annotation\n" }).write_to(
      dir,
    )
    let result = @auto_check.append_summary(path, "ok: wrote manifest")
    assert_true(result.has_prefix("ok: wrote manifest\nmoon check:\nexit="))
    assert_true(result.contains("Error:"))
    assert_false(result.contains("first error:"))
    assert_false(result.contains("moon check: 0 errors, 0 warnings"))
  })
}

///|
async test "append_summary preserves module dependency graph failure text" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-deps-", dir => {
    let path = "\{dir}/moon.mod"
    @vfs.FileSystem({
      "moon.mod": (
        #|name = "tmp/auto_check_deps"
        #|import { "moonbitlang/async" }
        #|
      ),
    }).write_to(dir)
    let result = @auto_check.append_summary(path, "ok: wrote manifest")
    assert_true(result.has_prefix("ok: wrote manifest\nmoon check:\nexit=255"))
    assert_true(result.contains("Error: Failed to calculate build plan"))
    assert_true(
      result.contains("Failed to resolve the module dependency graph"),
    )
    assert_true(
      result.contains(
        "moon.mod only supports versioned registry dependencies in `import`",
      ),
    )
    assert_false(result.contains("failed to run check for target Wasm"))
    assert_false(result.contains("first error:"))
  })
}

///|
async test "append_summary checks from moon.work workspace root" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-workspace-", dir => {
    let path = "\{dir}/moon.work"
    @vfs.FileSystem({ "moon.work": "members = [\"pkg\"\n" }).write_to(dir)
    let result = @auto_check.append_summary(path, "ok: wrote workspace")
    assert_true(result.has_prefix("ok: wrote workspace\nmoon check:\nexit=255"))
    assert_true(result.contains("failed to parse workspace file"))
  })
}

///|
async test "append_summary surfaces failed pre-build despite zero diagnostics" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-prebuild-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check_prebuild\"\n",
      create_mode=CreateOrTruncate,
    )
    let path = "\{dir}/moon.pkg"
    @fs.write_file(
      path,
      (
        #|options(
        #|  "pre-build": [
        #|    {
        #|      "command": "false",
        #|      "input": [ "in.txt" ],
        #|      "output": "generated.mbt",
        #|    },
        #|  ],
        #|)
      ),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file("\{dir}/in.txt", "", create_mode=CreateOrTruncate)
    @fs.write_file(
      "\{dir}/main.mbt",
      "pub fn hi() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
    let result = @auto_check.append_summary(path, "ok: wrote manifest")
    assert_true(result.has_prefix("ok: wrote manifest\nmoon check:\nexit="))
    assert_true(result.contains("Error:"))
    assert_false(result.contains("first error:"))
    assert_false(result.contains("moon check: 0 errors, 0 warnings"))
  })
}

///|
/// The same failed pre-build under `check`: moon's JSON result calls the run
/// a failure with no diagnostic and no message, which must read as `Failed`,
/// never as a clean tree.
async test "check names a failed pre-build that moon does not message" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-prebuild-json-", dir => {
    @vfs.FileSystem({
      "moon.mod": "name = \"tmp/auto_check_prebuild_json\"\n",
      "moon.pkg": (
        #|options(
        #|  "pre-build": [
        #|    {
        #|      "command": "false",
        #|      "input": [ "in.txt" ],
        #|      "output": "generated.mbt",
        #|    },
        #|  ],
        #|)
      ),
      "in.txt": "",
      "main.mbt": "pub fn hi() -> Int { 1 }\n",
    }).write_to(dir)
    guard @auto_check.check("\{dir}/main.mbt") is Failed(code, tally, detail) else {
      fail("expected Failed")
    }
    assert_true(code != 0)
    assert_eq(tally.error_count, 0)
    assert_true(detail.contains("pre-build"), msg=detail)
  })
}

///|
async test "append_summary runs for MoonBit source without local package" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-unpackaged-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check_unpacked\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{dir}/scratch")
    let path = "\{dir}/scratch/main.mbt"
    @vfs.FileSystem({ "scratch/main.mbt": "pub fn bad() -> Int { missing }\n" }).write_to(
      dir,
    )
    let result = @auto_check.append_summary(path, "ok: wrote unpackaged source")
    assert_true(result.has_prefix("ok: wrote unpackaged source\nmoon check:"))
    assert_false(result.contains("exit=0"))
    assert_false(result.contains("skipped"))
  })
}

///|
/// A manifest moon cannot load makes `moon check` exit non-zero without a
/// single diagnostic object. That is `Failed` for a caller that asks, and —
/// for `count_errors`, whose callers never told the case apart — still the
/// zero-error tally it always returned.
async test "check names a failed run; count_errors keeps its tally" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-failed-", dir => {
    @vfs.FileSystem({
      "moon.mod": "name = \n",
      "moon.pkg": "",
      "main.mbt": "///|\npub fn f() -> Int {\n  1\n}\n",
    }).write_to(dir)
    let path = "\{dir}/main.mbt"
    guard @auto_check.check(path) is Failed(code, tally, detail) else {
      fail("expected Failed")
    }
    assert_true(code != 0)
    assert_eq(tally.error_count, 0)
    // moon's own explanation rides along, so a refusal can name the cause.
    assert_true(detail.contains("Failed"), msg=detail)
    guard @auto_check.count_errors(path) is Some(counted) else {
      fail("expected the tally")
    }
    assert_eq(counted.error_count, 0)
    // A clean module is `Checked`.
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/checked\"\n",
      create_mode=CreateOrTruncate,
    )
    assert_true(@auto_check.check(path) is Checked({ error_count: 0, .. }))
    assert_true(@auto_check.check("\{dir}/notes.txt") is NotApplicable)
  })
}

///|
test "identity prefers path:loc#code and falls back to the rendered line" {
  let coded : @auto_check.ErrorSite = {
    path: Some("a.mbt"),
    loc: "1:1-1:2",
    code: Some(4014),
    message: "Expr Type Mismatch",
  }
  assert_eq(coded.identity(), "a.mbt:1:1-1:2#4014")
  // A reworded message keeps the identity.
  assert_eq(
    { ..coded, message: "Type mismatch (new wording)", }.identity(),
    coded.identity(),
  )
  let uncoded : @auto_check.ErrorSite = { ..coded, code: None, }
  assert_eq(uncoded.identity(), "a.mbt:1:1-1:2: Expr Type Mismatch")
}
