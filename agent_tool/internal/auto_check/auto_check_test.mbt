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
#cfg(not(platform="windows"))
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
#cfg(not(platform="windows"))
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
