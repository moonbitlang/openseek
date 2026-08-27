// A session id names a record only inside one store, so two attached projects
// can hold the same id — the `openseek` CLI takes `--session <name>` verbatim
// under any `--session-root`, and a project's store travels inside the project
// directory. Three host behaviors follow, and none can be read off the id:
//
//   * the desktop never *adds* to that population — a start opens a record in
//     the store it named or continues one already there, never a second twin;
//   * an operation that addresses one store — moving its record, compacting
//     it, setting its goal — ignores live engines and followers serving
//     another, even though both are filed under the id;
//   * a record's own store decides whether it is archived, so an archived
//     twin elsewhere never holds a live conversation hostage.
//
// All are exercised against a real pump: the refusals under test are the ones
// a live host issues, and a start that slips past them must show up as a
// spawned engine rather than as a stalled request.

///|
/// A host whose engine binary accepts every command and reports nothing, so a
/// conversation can be left mid-turn while another store is acted on. It reads
/// until stdin closes, so an engine this host replaces exits on EOF instead of
/// waiting out the graceful-close timeout.
#cfg(not(platform="windows"))
async fn store_identity_host(prefix : String) -> (@pathx.Absolute, EngineActor) {
  let root = worktree_test_root(prefix)
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  @sys.set_env_var("HOME", root.join("home").to_string())
  prepare_fake_moonbit_seed(
    root.join("bin/toolchains/moonbit/macos-arm64").to_path(),
    version="0.10.0-test",
  )
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64").to_path(),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}' ; exit 0; fi\nwhile IFS= read -r line; do :; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(
    engine.to_string(),
    runtime_dir=runtime.to_path(),
  )
  ignore(
    update_settings(actor.manager(), {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  (root, actor)
}

///|
#cfg(not(platform="windows"))
async test "a start cannot open a second record for an id another store owns" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let (root, actor) = store_identity_host("openseek-start-unique-")
  defer restore_home_env(previous)
  let manager = actor.manager()
  let owner = root.join("owner")
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.to_path())
  @fsx.ensure_dir(owner.to_path())
  @fsx.ensure_dir(
    @workspaces.store_root(owner).join("sessions/s-dup").to_path(),
  )
  let sink = EventSink(fn(_) {  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) {  })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(@workspaces.add(owner.to_string(), fn(_) {  }))
    ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
    // The first project owns `s-dup`. Running it in the second would file a
    // second record under the same id — the fork this refusal exists to stop.
    let detail = try {
      ignore(
        start_run(sink, manager, {
          task: "fork me",
          submission_id: None,
          model: None,
          thinking: None,
          max_steps: None,
          session: "s-dup",
          workspace: ws.to_string(),
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.has_suffix("; start a new one here"))
    assert_true(detail.contains(@workspaces.store_root(owner).to_string()))
    guard manager.pump is Serving(sessions~) else { fail("pump stopped") }
    assert_true(sessions.get("s-dup") is None)
    // The refusal is about opening a *second* record, so it must not reach
    // the ordinary cases: a genuinely new id in the project, and the store
    // that already owns this one continuing it.
    let fresh = start_run(sink, manager, {
      task: "mine",
      submission_id: None,
      model: None,
      thinking: None,
      max_steps: None,
      session: "s-fresh",
      workspace: ws.to_string(),
    })
    assert_eq(fresh.status, "accepted")
    // Now this project holds `s-dup` too — copied in by the CLI, or carried in
    // with the project directory. The owning project's conversation continues
    // its own record: the store the request named places the run, and the id
    // it shares with another project's record decides nothing.
    @fsx.ensure_dir(@workspaces.store_root(ws).join("sessions/s-dup").to_path())
    let owned = start_run(sink, manager, {
      task: "continue",
      submission_id: None,
      model: None,
      thinking: None,
      max_steps: None,
      session: "s-dup",
      workspace: owner.to_string(),
    })
    assert_eq(owned.status, "accepted")
    guard sessions.get("s-dup") is Some(slot) && slot.engine is Some(live) else {
      fail("the accepted start left no engine on the slot")
    }
    assert_true(live.writes_store(@workspaces.store_root(owner)))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "no command opens a second record for an id another store owns" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let (root, actor) = store_identity_host("openseek-unique-commands-")
  defer restore_home_env(previous)
  let manager = actor.manager()
  let owner = root.join("owner")
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.to_path())
  @fsx.ensure_dir(owner.to_path())
  let sink = EventSink(fn(_) {  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) {  })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(@workspaces.add(owner.to_string(), fn(_) {  }))
    ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
    // The first project owns `s-live`. A goal is reachable before the first
    // prompt, and its spawn writes a record, so it must refuse for the same
    // reason a start does rather than filing the second twin itself.
    @fsx.ensure_dir(
      @workspaces.store_root(owner).join("sessions/s-live").to_path(),
    )
    let goal_refusal = try {
      ignore(
        goal_run(manager, {
          session: "s-live",
          workspace: ws.to_string(),
          text: Some("ship it"),
          auto: None,
          model: None,
          thinking: None,
          max_steps: None,
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(goal_refusal.has_suffix("; start a new one here"))
    guard manager.pump is Serving(sessions~) else { fail("pump stopped") }
    assert_true(sessions.get("s-live") is None)
    // An *archived* record in the other store counts as well: it is one
    // unarchive away from standing beside whatever this start would create.
    @fsx.ensure_dir(
      @workspaces.store_root(owner)
      .join("archived/sessions/s-put-away")
      .to_path(),
    )
    let start_refusal = try {
      ignore(
        start_run(sink, manager, {
          task: "fork me",
          submission_id: None,
          model: None,
          thinking: None,
          max_steps: None,
          session: "s-put-away",
          workspace: ws.to_string(),
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(start_refusal.contains("archived record"))
    assert_true(
      start_refusal.contains(@workspaces.store_root(owner).to_string()),
    )
    assert_true(sessions.get("s-put-away") is None)
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "an archived record in another store does not block a live one" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let (root, actor) = store_identity_host("openseek-archived-twin-")
  defer restore_home_env(previous)
  let manager = actor.manager()
  let other = root.join("other")
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.to_path())
  @fsx.ensure_dir(other.to_path())
  let sink = EventSink(fn(_) {  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) {  })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
    ignore(@workspaces.add(other.to_string(), fn(_) {  }))
    // The other project archived its `s-twin`; this project's `s-twin` is a
    // different conversation and is live.
    @fsx.ensure_dir(
      @workspaces.store_root(other).join("archived/sessions/s-twin").to_path(),
    )
    @fsx.ensure_dir(
      @workspaces.store_root(ws).join("sessions/s-twin").to_path(),
    )
    let reply = start_run(sink, manager, {
      task: "continue",
      submission_id: None,
      model: None,
      thinking: None,
      max_steps: None,
      session: "s-twin",
      workspace: ws.to_string(),
    })
    assert_eq(reply.status, "accepted")
    // The store that did archive it still refuses: this is a scope, not a
    // removal of the defense.
    let detail = try {
      ignore(
        start_run(sink, manager, {
          task: "resurrect",
          submission_id: None,
          model: None,
          thinking: None,
          max_steps: None,
          session: "s-twin",
          workspace: other.to_string(),
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("archived"))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "a command addressed to one store never reaches a same-id twin's engine" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let (root, actor) = store_identity_host("openseek-store-command-")
  defer restore_home_env(previous)
  let manager = actor.manager()
  let owner = root.join("owner")
  let other = root.join("other")
  @fsx.ensure_dir(owner.to_path())
  @fsx.ensure_dir(other.to_path())
  let sink = EventSink(fn(_) {  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) {  })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(@workspaces.add(owner.to_string(), fn(_) {  }))
    ignore(@workspaces.add(other.to_string(), fn(_) {  }))
    // Both projects hold a record under each id, so nothing below can be
    // answered by which store happens to own the id.
    for workspace in [owner, other] {
      for session in ["s-busy", "s-idle"] {
        @fsx.ensure_dir(
          @workspaces.store_root(workspace)
          .join("sessions")
          .join(session)
          .to_path(),
        )
      }
    }
    // `owner`'s conversation holds an open turn. Compacting `other`'s record
    // would be written to that engine — rewriting the wrong history and
    // reporting its progress into this conversation — so it is refused by
    // name rather than silently steered or silently replaced.
    let started = start_run(sink, manager, {
      task: "keep running",
      submission_id: None,
      model: None,
      thinking: None,
      max_steps: None,
      session: "s-busy",
      workspace: owner.to_string(),
    })
    assert_eq(started.status, "accepted")
    let detail = try {
      ignore(
        compact_run(manager, {
          session: "s-busy",
          model: None,
          thinking: None,
          max_steps: None,
          workspace: other.to_string(),
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains(@workspaces.store_root(owner).to_string()))
    guard manager.pump is Serving(sessions~) else { fail("pump stopped") }
    guard sessions.get("s-busy") is Some(busy) && busy.engine is Some(live) else {
      fail("an unrelated compaction replaced the running engine")
    }
    assert_true(live.phase is Running(..))
    assert_true(live.writes_store(@workspaces.store_root(owner)))
    // An idle twin holds nothing but a warm process, so the goal takes the
    // slot instead of being refused — and lands on an engine writing the
    // store it named.
    ignore(
      goal_run(manager, {
        session: "s-idle",
        text: Some("owner goal"),
        auto: None,
        model: None,
        thinking: None,
        max_steps: None,
        workspace: owner.to_string(),
      }),
    )
    ignore(
      goal_run(manager, {
        session: "s-idle",
        text: Some("other goal"),
        auto: None,
        model: None,
        thinking: None,
        max_steps: None,
        workspace: other.to_string(),
      }),
    )
    guard sessions.get("s-idle") is Some(idle) && idle.engine is Some(rebound) else {
      fail("the goal left no engine on the slot")
    }
    assert_true(rebound.writes_store(@workspaces.store_root(other)))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archiving one store's record ignores another store's live engine" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let (root, actor) = store_identity_host("openseek-store-slot-")
  defer restore_home_env(previous)
  let manager = actor.manager()
  let other = root.join("other")
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.to_path())
  @fsx.ensure_dir(other.to_path())
  let sink = EventSink(fn(_) {  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) {  })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
    ignore(@workspaces.add(other.to_string(), fn(_) {  }))
    // The first project's record runs a turn that never finishes.
    let reply = start_run(sink, manager, {
      task: "keep running",
      submission_id: None,
      model: None,
      thinking: None,
      max_steps: None,
      session: "s-dup",
      workspace: ws.to_string(),
    })
    assert_eq(reply.status, "accepted")
    // A record with the same id in the other project, idle — the CLI could
    // have written it, or it travelled in with that directory. Its archive is
    // the user's to take: the busy engine belongs to the first project's
    // conversation.
    let other_store = @workspaces.store_root(other)
    @fsx.ensure_dir(other_store.join("sessions/s-dup").to_path())
    assert_true(
      archive_session(manager, "s-dup", other.resource_path(), (_, _) => ())
      is Archived(_),
    )
    assert_true(
      @fsx.is_dir(other_store.join("archived/sessions/s-dup").to_path()),
    )
    assert_false(@fsx.exists(other_store.join("sessions/s-dup").to_path()))
    // The first project's conversation is untouched: same process, still running,
    // and its follower still rooted in the store it tails.
    guard manager.pump is Serving(sessions~) else { fail("pump stopped") }
    guard sessions.get("s-dup") is Some(slot) && slot.engine is Some(live) else {
      fail("the other store's engine was closed by an unrelated archive")
    }
    assert_true(live.phase is Running(..))
    assert_true(live.writes_store(@workspaces.store_root(ws)))
    guard live.follower is Some(follower) else { fail("follower retired") }
    assert_true(follower.tails_store(@workspaces.store_root(ws)))
    assert_false(follower.retired)
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}
