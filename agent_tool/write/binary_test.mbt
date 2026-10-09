///|
async test "base64 source overwrites are rejected without requesting approval" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/code.mbt"
    @fs.write_text(path, "original")
    let mut asked = false
    let tool = @write.definition(
      approval=ApprovalChannel(_ => {
        asked = true
        AllowedOnce
      }),
    )
    guard run_write(tool, {
        "path": path,
        "content": @base64.encode(b"///|\nfn replacement() -> Unit {}\n"),
        "encoding": "base64",
        "revert_on_parse_errors": false,
      })
      is Respond(output) else {
      fail("expected Respond")
    }
    assert_true(output.is_error)
    assert_true(
      output.content.contains("cannot overwrite an existing source file"),
    )
    assert_false(asked)
    assert_eq(@fs.read_text(path), "original")
  })
}

///|
async test "base64 decoded size limit accepts exactly 16 MiB and rejects one more byte" {
  @vfs.with_tmpdir(dir => {
    let tool = @write.definition(workspace_root=dir)
    let prefix = "AAAA".repeat(5592405)
    guard run_write(tool, {
        "path": "limit.bin",
        "content": prefix + "AA==",
        "encoding": "base64",
      })
      is Respond(allowed) else {
      fail("expected Respond")
    }
    assert_false(allowed.is_error, msg=allowed.content)
    assert_eq(@fs.read_binary("\{dir}/limit.bin").length(), 16777216)
    guard run_write(tool, {
        "path": "limit.bin",
        "content": prefix + "AAA=",
        "encoding": "base64",
      })
      is Respond(denied) else {
      fail("expected Respond")
    }
    assert_true(denied.is_error)
    assert_true(denied.content.contains("16 MiB"))
    assert_eq(@fs.read_binary("\{dir}/limit.bin").length(), 16777216)
  })
}

///|
async test "base64 writes exact bytes, overwrites and tracks the decoded digest" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap()
    let tool = @write.definition(workspace_root=dir, file_state=state)
    let path = "\{dir}/assets/file.bin"
    let bytes : Bytes = b"\x00\xff\x80\r\n"
    guard run_write(tool, {
        "path": "assets/file.bin",
        "content": @base64.encode(bytes),
        "encoding": "base64",
      })
      is Respond(output) else {
      fail("expected Respond")
    }
    assert_false(output.is_error, msg=output.content)
    assert_eq(@fs.read_binary(path), bytes)
    let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    assert_true(state.created_and_unchanged(path, digest))
    assert_eq(output.data, Some({ "bytes": 5, "sha256": digest }))
    guard run_write(tool, { "path": path, "content": "", "encoding": "base64" })
      is Respond(empty) else {
      fail("expected Respond")
    }
    assert_false(empty.is_error)
    assert_true(empty.content.contains("overwrote existing file"))
    assert_eq(@fs.read_binary(path), b"")
  })
}

///|
async test "invalid or oversized base64 has no filesystem side effects" {
  @vfs.with_tmpdir(dir => {
    let tool = @write.definition(workspace_root=dir)
    for
      content in [
        "A",
        "AA",
        "AA=",
        "AA===",
        "AA==trailing",
        "AB==",
        "AAB=",
        "AA==\n",
        "____",
        "%%%%",
        "AAAA".repeat(5592407),
      ] {
      guard run_write(tool, {
          "path": "new/file.bin",
          "content": content,
          "encoding": "base64",
        })
        is Respond(output) else {
        fail("expected Respond")
      }
      assert_true(output.is_error)
      assert_false(@fs.exists("\{dir}/new"))
    }
    @fs.write_binary("\{dir}/keep.bin", b"original")
    guard run_write(tool, {
        "path": "keep.bin",
        "content": "AB==",
        "encoding": "base64",
      })
      is Respond(output) else {
      fail("expected Respond")
    }
    assert_true(output.is_error)
    assert_eq(@fs.read_binary("\{dir}/keep.bin"), b"original")
  })
}

///|
async test "base64 preserves UTF-8, manifest, source overwrite and scope checks" {
  @vfs.with_tmpdir(dir => {
    let tool = @write.definition(workspace_root=dir)
    for
      path in ["a.mbt", "a.mbt.md", "a.mbtx", "a.mbti", "moon.mod", "moon.pkg"] {
      guard run_write(tool, {
          "path": path,
          "content": "/w==",
          "encoding": "base64",
          "revert_on_parse_errors": false,
        })
        is Respond(output) else {
        fail("expected Respond")
      }
      assert_true(output.is_error)
      assert_true(output.content.contains("valid UTF-8"))
      assert_false(@fs.exists("\{dir}/\{path}"))
    }
    for
      (path, content) in [
        ("moon.mod", "{}"),
        ("moon.pkg", "# invalid"),
        ("new.generated.mbti", ""),
        ("moon.mod.json", "{}"),
      ] {
      guard run_write(tool, {
          "path": path,
          "content": @base64.encode(@utf8.encode(content)),
          "encoding": "base64",
          "revert_on_parse_errors": false,
        })
        is Respond(output) else {
        fail("expected Respond")
      }
      assert_true(output.is_error)
      assert_false(@fs.exists("\{dir}/\{path}"))
    }
    @fs.write_text("\{dir}/old.mbt", "///|\nfn old() -> Unit {}\n")
    @fs.symlink(target="old.mbt", "\{dir}/alias.bin")
    for path in ["old.mbt", "alias.bin"] {
      guard run_write(tool, {
          "path": path,
          "content": @base64.encode(b"///|\nfn replacement() -> Unit {}\n"),
          "encoding": "base64",
          "revert_on_parse_errors": false,
        })
        is Respond(output) else {
        fail("expected Respond")
      }
      assert_true(output.is_error)
    }
    assert_eq(@fs.read_text("\{dir}/old.mbt"), "///|\nfn old() -> Unit {}\n")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    guard run_write(@write.definition(workspace_root=dir, write_scope=scope), {
        "path": "outside/file.bin",
        "content": "/w==",
        "encoding": "base64",
      })
      is Respond(denied) else {
      fail("expected Respond")
    }
    assert_true(denied.is_error)
    assert_false(@fs.exists("\{dir}/outside"))
  })
}

///|
async test "base64 source is syntax checked using decoded content" {
  @vfs.with_tmpdir(dir => {
    let tool = @write.definition(workspace_root=dir)
    for path in ["new/broken.mbt", "new/broken.mbtx"] {
      guard run_write(tool, {
          "path": path,
          "content": @base64.encode(b"fn broken( {"),
          "encoding": "base64",
        })
        is Respond(output) else {
        fail("expected Respond")
      }
      assert_true(output.is_error, msg=output.content)
      assert_true(output.content.contains("rejected:"))
      assert_true(output.content.contains("fn broken("))
      assert_false(@fs.exists("\{dir}/new"))
    }
    guard run_write(tool, {
        "path": "good.mbt",
        "content": @base64.encode(b"///|\nfn good() -> Unit {}\n"),
        "encoding": "base64",
      })
      is Respond(good) else {
      fail("expected Respond")
    }
    assert_false(good.is_error, msg=good.content)
    assert_eq(@fs.read_text("\{dir}/good.mbt"), "///|\nfn good() -> Unit {}\n")
  })
}
