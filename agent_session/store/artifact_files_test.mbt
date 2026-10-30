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
    @fs.write_file(first + "/chart.html", "first")
    @fs.write_file(second + "/chart.html", "second")
    let reopened = @store.SessionStore(one.root())
    assert_eq(reopened.artifact_dir(id), first)
    assert_eq(
      @fs.read_file(reopened.artifact_file(id, "artifact://chart.html")).text(),
      "first",
    )
    assert_eq(
      @fs.read_file(two.artifact_file(id, "artifact://chart.html")).text(),
      "second",
    )
    for
      reference in [
        "artifact://../chart.html", "artifact:///chart.html", "chart.html",
      ] {
      let refused = try {
        ignore(one.artifact_file(id, reference))
        false
      } catch {
        _ => true
      }
      assert_true(refused)
    }
    @fs.rmdir(first, recursive=true)
    assert_eq(reopened.artifact_dir(id), first)
    assert_false(@fs.exists(first))
    assert_eq(
      @fs.read_file(two.artifact_file(id, "artifact://chart.html")).text(),
      "second",
    )
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
    @fs.write_file(
      store.scratch_dir(source) + "/helper.mbtx",
      "source working state",
    )
    @fs.write_file(original + "/charts/view.html", "original")
    let source_bundle = original + "/charts/view.html.source"
    @fs.mkdir(source_bundle + "/data", recursive=true)
    @fs.write_file(source_bundle + "/main.mbt", "editable Rabbita source")
    @fs.write_file(source_bundle + "/moon.mod", "module manifest")
    @fs.write_file(source_bundle + "/data/values.json", "[1, 2, 3]")
    ignore(store.fork(source, fork, system_prompt="fork"))
    let copy = store.artifact_file(fork, "artifact://charts/view.html")
    assert_false(@fs.exists(store.scratch_dir(fork) + "/helper.mbtx"))
    assert_true(copy != original + "/charts/view.html")
    assert_eq(@fs.read_file(copy).text(), "original")
    let fork_sources = store.artifact_dir(fork) + "/charts/view.html.source"
    assert_eq(
      @fs.read_file(fork_sources + "/main.mbt").text(),
      "editable Rabbita source",
    )
    assert_eq(
      @fs.read_file(fork_sources + "/moon.mod").text(),
      "module manifest",
    )
    assert_eq(
      @fs.read_file(fork_sources + "/data/values.json").text(),
      "[1, 2, 3]",
    )
    @fs.write_file(
      fork_sources + "/main.mbt",
      "fork revision",
      create_mode=CreateOrTruncate,
    )
    assert_eq(
      @fs.read_file(source_bundle + "/main.mbt").text(),
      "editable Rabbita source",
    )
    @fs.write_file(copy, "fork changed", create_mode=CreateOrTruncate)
    assert_eq(@fs.read_file(original + "/charts/view.html").text(), "original")
    @fs.rmdir(root + "/store/sessions/fork", recursive=true)
    assert_false(@fs.exists(copy))
    assert_true(@fs.exists(original + "/charts/view.html"))
  })
}

///|
#cfg(not(platform="windows"))
async test "artifact references reject symlinks into another conversation" {
  @vfs.with_tmpdir(root => {
    let store = @store.SessionStore(root + "/store")
    let id : @agent_session.SessionId = SessionId("one")
    let one = store.artifact_dir(id)
    let two = store.artifact_dir(SessionId("two"))
    @fs.mkdir(one, recursive=true)
    @fs.mkdir(two, recursive=true)
    @fs.write_file(two + "/private.html", "other conversation")
    @fs.symlink(target=two, one + "/foreign")
    let refused = try {
      ignore(store.artifact_file(id, "artifact://foreign/private.html"))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
    for location in ["artifact-link", "scratch-link"] {
      let linked_id : @agent_session.SessionId = SessionId(location)
      @fs.mkdir(root + "/store/sessions/" + location, recursive=true)
      let link = if location == "artifact-link" {
        @fs.mkdir(store.scratch_dir(linked_id))
        store.artifact_dir(linked_id)
      } else {
        store.scratch_dir(linked_id)
      }
      let target = if location == "artifact-link" {
        two
      } else {
        store.scratch_dir(SessionId("two"))
      }
      @fs.symlink(target~, link)
      let refused = try {
        ignore(store.artifact_file(linked_id, "artifact://private.html"))
        false
      } catch {
        _ => true
      }
      assert_true(refused, msg=location)
    }
  })
}
