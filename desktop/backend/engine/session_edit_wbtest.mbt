///|
#cfg(not(platform="windows"))
async test "edit cleanup requires its durable receipt and an unchanged source" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-edit-cleanup-"))
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir)
  @sys.set_env_var("HOME", root.join("global").to_string())
  let workspace = attach_run_workspace(root)
  let selected = @session_store.ArchivedStore::for_workspace(workspace)
  let store = @store.SessionStore(selected.root.to_string())
  let source = @agent_session.Session(SessionId("source"), system_prompt="test")
    .append(User(UserMessage(Content([Text("original")]))))
    .append(Terminal(Finished("answer")))
  store.create(source)
  let replacement = @agent_session.Session(
    SessionId("replacement"),
    system_prompt="test",
  ).append(User(UserMessage(Content([Text("edited")]), submission_id="edit-1")))
  store.create(replacement)
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  let payload : EditReplacement = {
    session: "source",
    workspace,
    replacement: "replacement",
    submission_id: "edit-1",
    source_sequence: 2,
  }
  let notifications : Array[String] = []
  for
    invalid in [
      { ..payload, submission_id: "wrong", },
      { ..payload, source_sequence: 1, },
    ] {
    let result : Result[SessionDeleteReply, String] = Ok(
      commit_session_edit(manager, invalid, (id, _) => notifications.push(id), on_worktree_changed=(
        _,
        _,
      ) => ()),
    ) catch {
      error => Err("\{error}")
    }
    assert_true(result is Err(_))
    assert_true(store.exists(SessionId("source")))
    assert_true(notifications.is_empty())
  }
  assert_true(
    commit_session_edit(manager, payload, (id, _) => notifications.push(id), on_worktree_changed=(
      _,
      _,
    ) => ())
    is Deleted,
  )
  assert_false(store.exists(SessionId("source")))
  assert_true(store.exists(SessionId("replacement")))
  assert_eq(notifications, ["source"])
  assert_true(manager.record_guards.is_empty())
}

///|
#cfg(not(platform="windows"))
async test "first-message replacement keeps its source's dirty checkout" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let root = worktree_test_root("openseek-first-edit-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  @fsx.ensure_dir(root.join("global").to_path())
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  let created = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    @worktree.WorktreeOwner::openseek("original"),
    _ => (),
  )
  let store = @store.SessionStore(@workspaces.store_root(repo).to_string())
  store.create(
    @agent_session.Session(SessionId("original"), system_prompt="test").append(
      User(UserMessage(Content([Text("original")]))),
    ),
  )
  let dirty = repo.join(".worktrees").join(created.name).join("unsaved.txt")
  @fs.write_file(dirty.to_string(), b"keep me", create_mode=CreateOrTruncate)
  let prepared = prepare_session_edit(
    manager,
    {
      session: "original",
      workspace: repo.resource_path(),
      through: None,
      model: "deepseek-flash",
      source_title: "Original",
    },
    on_created=_ => (),
    on_worktree_changed=(_, _) => (),
  )
  assert_true(store.exists(SessionId(prepared.session)))
  assert_false(@fs.exists(store.session_file(SessionId(prepared.session))))
  // A lost prepare reply is recoverable through the durable listing and can
  // be deleted without stranding an invisible worktree registry member.
  let listings = store.listings()
  guard listings.search_by(row => row.id().value() == prepared.session)
    is Some(index) else {
    fail("unsent conversation was not discoverable")
  }
  assert_eq(listings[index].title(), Some("Original"))
  let empty = load_session(manager, {
    session: prepared.session,
    workspace: Some(repo.resource_path()),
  })
  assert_true(empty.session.events.unwrap_or([]).is_empty())
  let lost = prepare_session_edit(
    manager,
    {
      session: "original",
      workspace: repo.resource_path(),
      through: None,
      model: "deepseek-flash",
      source_title: "Lost reply",
    },
    on_created=_ => (),
    on_worktree_changed=(_, _) => (),
  )
  assert_true(
    delete_session(manager, lost.session, repo.resource_path(), (_, _) => ())
    is Deleted,
  )
  assert_false(store.exists(SessionId(lost.session)))
  guard @worktree.list(repo.to_string()).worktrees is [before_send] else {
    fail("checkout")
  }
  assert_false(before_send.sessions.contains(lost.session))
  // The ordinary first prompt creates the record inside the inherited tree.
  store.create(
    @agent_session.Session(SessionId(prepared.session), system_prompt="test").append(
      User(UserMessage(Content([Text("edited")]), submission_id="first-edit")),
    ),
  )
  assert_true(
    commit_session_edit(
      manager,
      {
        session: "original",
        workspace: repo.resource_path(),
        replacement: prepared.session,
        submission_id: "first-edit",
        source_sequence: 1,
      },
      (_, _) => (),
      on_worktree_changed=(_, _) => (),
    )
    is Deleted,
  )
  assert_true(@fsx.exists(dirty.to_path()))
  guard @worktree.list(repo.to_string()).worktrees is [kept] else {
    fail("checkout")
  }
  assert_true(kept.present)
  assert_false(store.exists(SessionId("original")))
  assert_true(store.exists(SessionId(prepared.session)))
}

///|
#cfg(not(platform="windows"))
async test "single edit waits for the submitted message before deleting its source" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-single-edit-"))
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir)
  @sys.set_env_var("HOME", root.join("global").to_string())
  let workspace = attach_run_workspace(root)
  let selected = @session_store.ArchivedStore::for_workspace(workspace)
  let store = @store.SessionStore(selected.root.to_string())
  let source = @agent_session.Session(SessionId("source"), system_prompt="test")
    .append(User(UserMessage(Content([Text("original")]))))
    .append(Terminal(Finished("answer")))
  store.create(source)
  let custom_prompt = "  Custom instructions\n中文\n"
  @fsx.write_text_atomic(
    @pathx.Path(store.session_file(SessionId("source")))
    .dirname()
    .join("system-prompt.md"),
    custom_prompt,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let payload : @protocol.SessionEditPayload = {
    session: "source",
    workspace,
    through: None,
    model: "deepseek-flash",
    source_title: "Original",
    source_sequence: 2,
    task: "edited",
    images: [],
    attachment_paths: [],
    thinking: None,
    approval: None,
    max_steps: None,
  }
  let created : Array[String] = []
  let removed : Array[String] = []
  // A failed submission surfaces its original error and leaves both identities.
  try
    edit_session(
      manager,
      payload,
      start=_ => raise EngineError("start failed"),
      on_created=id => created.push(id),
      on_deleted=(id, _) => removed.push(id),
      on_worktree_changed=(_, _) => (),
    )
  catch {
    EngineError(message) => assert_eq(message, "start failed")
    error => raise error
  } noraise {
    _ => fail("accepted a failed start")
  }
  assert_true(store.exists(SessionId("source")))
  assert_eq(created.length(), 1)
  assert_true(removed.is_empty())
  @async.with_task_group(group => {
    let reply = edit_session(
      manager,
      payload,
      start=start => {
        assert_eq(start.task, "edited")
        assert_eq(start.system_prompt, Some(custom_prompt))
        ignore(
          group.spawn(() => {
            @async.sleep(40)
            assert_true(store.exists(SessionId("source")))
            assert_true(removed.is_empty())
            ignore(
              store.append(
                Session(
                  SessionId(start.session),
                  system_prompt=start.system_prompt.unwrap(),
                ),
                User(
                  UserMessage(
                    Content([Text(start.task)]),
                    submission_id?=start.submission_id,
                  ),
                ),
              ),
            )
          }),
        )
      },
      on_created=id => created.push(id),
      on_deleted=(id, _) => removed.push(id),
      on_worktree_changed=(_, _) => (),
    )
    assert_eq(created.length(), 2)
    assert_eq(removed, ["source"])
    assert_false(store.exists(SessionId("source")))
    assert_eq(
      store.load(SessionId(reply.session)).system_prompt(),
      custom_prompt,
    )
  })
}
