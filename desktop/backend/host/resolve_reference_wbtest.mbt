///|
async test "working-host reference resolution preserves literal names and remote positions" {
  let dir = @fs.tmpdir(prefix="ssh-reference-")
  defer @fs.rmdir(dir, recursive=true)
  let root = reference_uri_path(dir)
  let source = "\{dir}/中文.txt"
  @fs.write_file(source, "first\nsecond\n", create_mode=CreateOrTruncate)
  let positioned = resolve_reference_op({
    session: "demo",
    cwd: Some(root),
    path: "中文.txt:2:3",
  })
  assert_true(positioned is ReferenceText(path=_, line=Some(2), column=Some(3)))
  @fs.write_file("\{source}:2:3", "literal", create_mode=CreateOrTruncate)
  let literal = resolve_reference_op({
    session: "demo",
    cwd: Some(root),
    path: "中文.txt:2:3",
  })
  assert_true(literal is ReferenceText(path=_, line=None, column=None))
  if literal is ReferenceText(path~, ..) {
    assert_eq(path, reference_uri_path("\{source}:2:3"))
  }
  assert_true(
    resolve_reference_op({
      session: "demo",
      cwd: Some(root),
      path: "missing.txt",
    })
    is ReferenceRefused(..),
  )
  @fs.write_file(
    "\{dir}/image.png",
    b"\x89PNG\r\n\x1a\n",
    create_mode=CreateOrTruncate,
  )
  assert_true(
    resolve_reference_op({
      session: "demo",
      cwd: Some(root),
      path: "image.png",
    })
    is ReferenceBinary(..),
  )
}

///|
async test "remote directory navigation stays in the checkout and IO errors remain errors" {
  let dir = @fs.tmpdir(prefix="ssh-reference-tree-")
  defer @fs.rmdir(dir, recursive=true)
  let root = reference_uri_path(dir)
  @fs.mkdir("\{dir}/src")
  let reply = resolve_reference_op({
    session: "demo",
    cwd: Some(root),
    path: "src",
  })
  assert_true(reply is ReferenceDirectory(path="src"))
  let outside = @fs.tmpdir(prefix="ssh-reference-outside-")
  defer @fs.rmdir(outside, recursive=true)
  @fs.symlink("\{dir}/outside", target=outside)
  assert_true(
    resolve_reference_op({ session: "demo", cwd: Some(root), path: "outside", })
    is ReferenceRefused(..),
  )
  @fs.write_file("\{dir}/file", "content", create_mode=CreateOrTruncate)
  let error = try {
    ignore(
      resolve_reference_op({
        session: "demo",
        cwd: Some(root),
        path: "file/child",
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(error)
}
