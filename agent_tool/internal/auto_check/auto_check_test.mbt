///|
async test "append_summary runs compact check for MoonBit source" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/moon.pkg",
      "warnings = \"+unnecessary_annotation\"\n",
      create_mode=CreateOrTruncate,
    )
    let path = "\{dir}/main.mbt"
    @fs.write_file(
      path,
      "fn main {\n  let x = missing\n}\n",
      create_mode=CreateOrTruncate,
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
async test "append_summary surfaces raw moon check failure" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-manifest-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check_manifest\"\n",
      create_mode=CreateOrTruncate,
    )
    let path = "\{dir}/moon.pkg"
    @fs.write_file(
      path,
      "warnings = \"+unnecessary_annotation\n",
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
async test "append_summary preserves module dependency graph failure text" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-deps-", dir => {
    let path = "\{dir}/moon.mod"
    @fs.write_file(
      path,
      "name = \"tmp/auto_check_deps\"\nimport { \"moonbitlang/async\" }\n",
      create_mode=CreateOrTruncate,
    )
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
async test "append_summary skips unpackaged MoonBit source" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-unpackaged-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check_unpacked\"\n",
      create_mode=CreateOrTruncate,
    )
    let path = "\{dir}/main.mbt"
    @fs.write_file(
      path,
      "pub fn bad() -> Int { missing }\n",
      create_mode=CreateOrTruncate,
    )
    let result = @auto_check.append_summary(path, "ok: wrote unpackaged source")
    assert_eq(
      result, "ok: wrote unpackaged source\nmoon check: skipped (no moon.pkg in file directory)",
    )
  })
}
