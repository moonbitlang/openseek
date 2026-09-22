///|
test "json fixture lists paths in stable order" {
  let files = @filesystem.FileSystem({
    "src/b.txt": "bravo\n",
    "README.md": "readme\n",
    "src/a.txt": "alpha\n",
  })
  assert_eq(files.paths().join("|"), "README.md|src/a.txt|src/b.txt")
  assert_true(files.get("src/a.txt") is Some("alpha\n"))
  assert_true(files.get("missing.txt") is None)
}

///|
test "from_pairs validates fixture paths" {
  let _ = @filesystem.FileSystem::from_pairs([("../secret.txt", "nope")]) catch {
    error => {
      assert_true("\{error}".contains("must not contain `.` or `..`"))
      return
    }
  }
  fail("invalid path accepted")
}

///|
test "from_pairs rejects duplicate paths" {
  let _ = @filesystem.FileSystem::from_pairs([
    ("README.md", "first\n"),
    ("README.md", "second\n"),
  ]) catch {
    error => {
      assert_true("\{error}".contains("duplicate file path: README.md"))
      return
    }
  }
  fail("duplicate path accepted")
}

///|
test "json fixture rejects non-string contents" {
  let files = @filesystem.FileSystem({ "src/count.txt": 1 })
  let _ = files.validate() catch {
    error => {
      assert_true("\{error}".contains("must be a string"))
      return
    }
  }
  fail("non-string content accepted")
}

///|
async test "fixture writes to disk and reports mismatches" {
  @filesystem.with_tmpdir(prefix="openseek-testkit-fs", root => {
    let files = @filesystem.FileSystem({
      "src/note.txt": "alpha\n",
      "docs/summary.txt": "ready\n",
    })
    files.write_to(root)
    assert_eq(files.mismatch_on_disk(root), "")
    @filesystem.write_text(root, "src/note.txt", "changed\n")
    assert_eq(files.mismatch_on_disk(root), "content mismatch in src/note.txt")
  })
}

///|
async test "with_tmpdir hands back a writable dir and removes it afterward" {
  let captured = @filesystem.with_tmpdir(dir => {
    let path = "\{dir}/note.txt"
    @fs.write_file(path, "hello", create_mode=CreateOrTruncate)
    assert_eq(@fs.read_file(path).text(), "hello")
    dir
  })
  // The directory and its contents are gone once the body returns.
  assert_false(@fs.exists(captured))
}

///|
async test "with_tmpdir cleans up even when the body raises" {
  let mut leaked = ""
  @filesystem.with_tmpdir(dir => {
    leaked = dir
    @fs.write_file("\{dir}/x", "x", create_mode=CreateOrTruncate)
    fail("boom")
  }) catch {
    _ => ()
  }
  assert_true(leaked != "")
  assert_false(@fs.exists(leaked))
}
