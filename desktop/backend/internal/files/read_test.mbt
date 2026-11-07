///|
async test "ordinary rooted file reads keep session files separate and follow archived storage" {
  let dir = @fs.tmpdir(prefix="openseek-session-file-read-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(@fs.realpath(dir)).resolve().resource_path()
  let first = ".openseek/sessions/one/scratch/artifact/page.html"
  let second = ".openseek/sessions/two/scratch/artifact/page.html"
  for (path, content) in [(first, "first"), (second, "second")] {
    let file = @pathx.Path(dir).join(path)
    @fs.mkdir(file.dirname().to_string(), recursive=true)
    @fs.write_file(file.to_string(), content)
    assert_true(
      @files.read_file({ max_bytes: None, root: Some(root), path, })
      is Content(content=read, ..) &&
      read == content,
    )
  }
  @fs.mkdir(dir + "/.openseek/archived/sessions", recursive=true)
  @fs.rename(
    dir + "/.openseek/sessions/one",
    dir + "/.openseek/archived/sessions/one",
  )
  assert_true(
    @files.read_file({
      max_bytes: None,
      root: Some(root),
      path: ".openseek/archived/sessions/one/scratch/artifact/page.html",
    })
    is Content(content="first", ..),
  )
  assert_true(
    @files.read_file({ max_bytes: None, root: Some(root), path: second, })
    is Content(content="second", ..),
  )
}

///|
async test "interactive reads can exceed the editor default with an explicit byte limit" {
  let dir = @fs.tmpdir(prefix="openseek-read-limit-")
  defer @fs.rmdir(dir, recursive=true)
  let path = @pathx.Path(@fs.realpath(dir))
    .join("page.html")
    .resolve()
    .resource_path()
  let content = "x".repeat(@files.MaxEditorFileBytes + 1)
  @fs.write_file(
    @pathx.Absolute::parse_resource_path(path).to_string(),
    content,
  )
  assert_eq(@files.read_file({ path, root: None, max_bytes: None, }), Oversized)
  assert_true(
    @files.read_file({ path, root: None, max_bytes: Some(8 * 1024 * 1024), })
    is Content(content=actual, ..) &&
    actual == content,
  )
  assert_eq(
    @files.read_file({ path, root: None, max_bytes: Some(100), }),
    Oversized,
  )
  for limit in [0, -1] {
    let refused = try {
      ignore(@files.read_file({ path, root: None, max_bytes: Some(limit), }))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}
