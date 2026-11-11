///|
async test "artifact directories isolate sessions and equal IDs in separate workspaces and survive reopen" {
  @vfs.with_tmpdir(root => {
    let one = @store.SessionStore(root + "/project-one/.openseek")
    let two = @store.SessionStore(root + "/project-two/.openseek")
    let id : @agent_session.SessionId = SessionId("same-id")
    let first = one.artifact_dir(id)
    let second = two.artifact_dir(id)
    let third = one.artifact_dir(SessionId("another"))
    assert_eq(first, one.scratch_dir(id) + "/artifact")
    assert_false(@fs.exists(first))
    assert_true(first != second && first != third && second != third)
    for directory in [first, second, third] {
      @fs.mkdir(directory, recursive=true)
    }
    @fs.write_text(first + "/chart.html", "first")
    @fs.write_text(second + "/chart.html", "second")
    let reopened = @store.SessionStore(one.root())
    assert_eq(reopened.artifact_dir(id), first)
    assert_eq(@fs.read_text(reopened.artifact_dir(id) + "/chart.html"), "first")
    assert_eq(@fs.read_text(two.artifact_dir(id) + "/chart.html"), "second")
    @fs.rmdir(first, recursive=true)
    assert_eq(reopened.artifact_dir(id), first)
    assert_false(@fs.exists(first))
    assert_eq(@fs.read_text(two.artifact_dir(id) + "/chart.html"), "second")
  })
}

///|
async test "fork copies file artifacts into an independently writable directory" {
  @vfs.with_tmpdir(root => {
    let store = @store.SessionStore(root + "/store")
    let source : @agent_session.SessionId = SessionId("source")
    let fork : @agent_session.SessionId = SessionId("fork")
    store.create(
      @agent_session.Session(source, system_prompt="system")
      .append(User(UserMessage(Content([Text("chart")]))))
      .append(Terminal(Finished("result"))),
    )
    let original = store.artifact_dir(source)
    @fs.mkdir(original + "/charts", recursive=true)
    @fs.write_text(
      store.scratch_dir(source) + "/helper.mbtx",
      "source working state",
    )
    @fs.write_text(original + "/charts/view.html", "original")
    let source_bundle = original + "/charts/view.html.source"
    @fs.mkdir(source_bundle + "/data", recursive=true)
    @fs.write_text(source_bundle + "/main.mbt", "editable Rabbita source")
    @fs.write_text(source_bundle + "/moon.mod", "module manifest")
    @fs.write_text(source_bundle + "/data/values.json", "[1, 2, 3]")
    ignore(store.fork(source, fork, system_prompt="fork"))
    let copy = store.artifact_dir(fork) + "/charts/view.html"
    assert_false(@fs.exists(store.scratch_dir(fork) + "/helper.mbtx"))
    assert_true(copy != original + "/charts/view.html")
    assert_eq(@fs.read_text(copy), "original")
    let fork_sources = store.artifact_dir(fork) + "/charts/view.html.source"
    assert_eq(
      @fs.read_text(fork_sources + "/main.mbt"),
      "editable Rabbita source",
    )
    assert_eq(@fs.read_text(fork_sources + "/moon.mod"), "module manifest")
    assert_eq(@fs.read_text(fork_sources + "/data/values.json"), "[1, 2, 3]")
    @fs.write_text(
      fork_sources + "/main.mbt",
      "fork revision",
      create_mode=CreateOrTruncate,
    )
    assert_eq(
      @fs.read_text(source_bundle + "/main.mbt"),
      "editable Rabbita source",
    )
    @fs.write_text(copy, "fork changed", create_mode=CreateOrTruncate)
    assert_eq(@fs.read_text(original + "/charts/view.html"), "original")
    @fs.rmdir(root + "/store/sessions/fork", recursive=true)
    assert_false(@fs.exists(copy))
    assert_true(@fs.exists(original + "/charts/view.html"))
  })
}
