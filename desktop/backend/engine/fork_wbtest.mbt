///|
#cfg(not(platform="windows"))
async test "a committed fork succeeds even when its title cannot be saved" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-fork-title-failure-"))
  defer @fs.rmdir(dir, recursive=true)
  let workspace = dir + "/workspace"
  @sys.set_env_var("HOME", dir + "/home")
  @fs.mkdir(dir + "/home/.openseek", recursive=true)
  @fs.mkdir(workspace + "/.openseek", recursive=true)
  @fs.write_file(
    dir + "/home/.openseek/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
  )
  let newline = "\\n"
  // Commit a loadable session, then make the title destination a directory.
  // Atomic title replacement must fail even when tests run with write access.
  let engine = dir + "/engine.sh"
  let script =
    $|#!/bin/sh
    $|set -eu
    $|while [ "$#" -gt 0 ]; do
    $|  case "$1" in
    $|    --as) fork="$2"; shift 2 ;;
    $|    --session-root) root="$2"; shift 2 ;;
    $|    *) shift ;;
    $|  esac
    $|done
    $|target="$root/sessions/$fork"
    $|mkdir -p "$target/session-title"
    $|printf '{"version":1,"id":"%s","system_prompt":"test"}\{newline}' "$fork" > "$target/openseek_session-$fork.jsonl"
    $|printf '%s\{newline}' "$fork"
  @fs.write_file(engine, script)
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let reply = fork_session(
    manager,
    {
      session: "source",
      workspace: @pathx.Path(workspace).resolve().resource_path(),
      through: 3,
      model: "deepseek-flash",
      source_title: "Original title",
      side_chat: None,
    },
    on_created=_ => (),
    on_worktree_changed=(_, _) => (),
  )
  assert_eq(reply.title, "Original title")
  let store = @store.SessionStore(workspace + "/.openseek")
  let id : @agent_session.SessionId = SessionId(reply.session)
  assert_eq(store.load(id).id().value(), reply.session)
  assert_true(manager.record_guards.get("source") is None)
  let title_failed = try {
    store.set_title(id, "Retry title")
    false
  } catch {
    _ => true
  }
  assert_true(title_failed)
}

///|
/// A stand-in for the engine's `sessions fork <id> --as <fork> --through <n>
/// --session-root <root> --dir <dir> --model <model> [--notice=<text>]`. It
/// copies the record, refuses an id that exists, writes what the host handed
/// it — the directory, the model, the cut — as the fork's system prompt, the
/// notice text to `<root>/notice-<fork>` when there is one, and prints the
/// fork's id. The model `fails-before` makes it fail without writing anything, and
/// `fails-after` once the record is written; `noisy` succeeds but prints more
/// than the id; `hangs-after` writes the record, leaves `<root>/committed` to
/// say so, and then never finishes. Any other
/// command lists no sessions, which is all archiving asks of it.
fn worktree_fork_engine_script() -> String {
  // `\{newline}` is the two characters a shell `printf` format needs, not an
  // actual line break.
  let newline = "\\n"
  let script =
    $|#!/bin/sh
    $|if [ "$2" != fork ]; then
    $|  printf '[]'
    $|  exit 0
    $|fi
    $|source="$3"
    $|shift 3
    $|notice=""
    $|while [ "$#" -gt 1 ]; do
    $|  case "$1" in
    $|    --notice=*)
    $|      notice="${1#--notice=}"
    $|      shift
    $|      continue
    $|      ;;
    $|    --as) fork="$2" ;;
    $|    --through) through="$2" ;;
    $|    --session-root) root="$2" ;;
    $|    --dir) dir="$2" ;;
    $|    --model) model="$2" ;;
    $|  esac
    $|  shift 2
    $|done
    $|if [ "$model" = fails-before ]; then
    $|  printf 'error: refused\{newline}' >&2
    $|  exit 1
    $|fi
    $|to="$root/sessions/$fork"
    $|mkdir "$to" || exit 1
    $|record="$to/openseek_session-$fork.jsonl"
    $|printf '{"version":1,"id":"%s","system_prompt":"dir=%s model=%s through=%s"}\{newline}' "$fork" "$dir" "$model" "$through" > "$record"
    $|if [ -n "$notice" ]; then
    $|  printf '%s' "$notice" > "$root/notice-$fork"
    $|fi
    $|tail -n +2 "$root/sessions/$source/openseek_session-$source.jsonl" >> "$record"
    $|if [ "$model" = fails-after ]; then
    $|  printf 'error: lost after the record\{newline}' >&2
    $|  exit 1
    $|fi
    $|if [ "$model" = noisy ]; then
    $|  printf 'note: something else on stdout\{newline}'
    $|fi
    $|if [ "$model" = hangs-after ]; then
    $|  printf '%s' "$fork" > "$root/committed"
    $|  exec sleep 30
    $|fi
    $|printf '%s\{newline}' "$fork"
    $|
  script
}

///|
/// A registered repository whose conversation `s-src` works in a worktree of
/// its own and has two finished turns, ending at sequences 2 and 4. The body
/// gets the manager, the repository, its store, and the worktree's checkout.
#cfg(not(platform="windows"))
async fn with_worktree_fork_fixture(
  body : async (
    EngineManager,
    @pathx.Absolute,
    @store.SessionStore,
    @pathx.Absolute,
  ) -> Unit,
) -> Unit {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-fork-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  @fsx.ensure_dir(root.join("global").to_path())
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let engine = root.join("engine.sh").to_string()
  @fs.write_file(engine, worktree_fork_engine_script())
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  manager.pump = Serving(sessions=Map([]))
  let created = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    @worktree.WorktreeOwner::openseek("s-src"),
    _ => (),
  )
  let store = @store.SessionStore(@workspaces.store_root(repo).to_string())
  store.create(
    @agent_session.Session(SessionId("s-src"), system_prompt="system")
    .append(Runtime(RuntimeNotice("first turn")))
    .append(Terminal(Finished("first")))
    .append(Runtime(RuntimeNotice("second turn")))
    .append(Terminal(Finished("second"))),
  )
  body(manager, repo, store, repo.join(".worktrees").join(created.name))
}

///|
#cfg(not(platform="windows"))
async test "a fork of a worktree conversation works in a checkout of its own" {
  with_worktree_fork_fixture((manager, repo, store, checkout) => {
    @fsx.write_text(checkout.join("draft.txt").to_path(), "uncommitted")
    let placements : Array[Array[WorktreeInfo]] = []
    let created : Array[String] = []
    let reply = fork_session(
      manager,
      {
        session: "s-src",
        workspace: repo.resource_path(),
        through: 2,
        model: "fork-model",
        source_title: "Original",
        side_chat: None,
      },
      on_created=session => created.push(session),
      on_worktree_changed=(_, rows) => placements.push(rows),
    )
    assert_eq(created, [reply.session])
    guard placements is [[source, own]] else {
      fail("the fork's worktree must be broadcast once")
    }
    assert_eq(source.sessions, ["s-src"])
    assert_eq(own.sessions, [reply.session])
    let fork_checkout = @worktree.run_dir(repo, reply.session)
    assert_true(fork_checkout != checkout)
    assert_eq(own.base, source.base)
    // The engine wrote the fork's prompt in the fork's own checkout, and the
    // host told it what the source had uncommitted there.
    assert_eq(
      store.load(SessionId(reply.session)).system_prompt(),
      "dir=\{fork_checkout.to_string()} model=fork-model through=2",
    )
    assert_eq(
      @fsx.read_text(
        @workspaces.store_root(repo).join("notice-\{reply.session}").to_path(),
      ),
      new_worktree_notice(uncommitted=["draft.txt"], omitted=0),
    )
    assert_eq(store.title(SessionId(reply.session)), Some("Original"))
    assert_false(@fsx.exists(fork_checkout.join("draft.txt").to_path()))
    // Each checkout goes with its own conversation.
    assert_true(
      archive_session(manager, reply.session, (_, _) => ()) is Archived(_),
    )
    assert_false(@fsx.exists(fork_checkout.to_path()))
    assert_true(@fsx.is_dir(checkout.to_path()))
  })
}

///|
#cfg(not(platform="windows"))
async test "a later-message edit takes over its source's checkout" {
  with_worktree_fork_fixture((manager, repo, store, checkout) => {
    let placements : Array[Array[WorktreeInfo]] = []
    let reply = prepare_session_edit(
      manager,
      {
        session: "s-src",
        workspace: repo.resource_path(),
        through: Some(2),
        model: "edit-model",
        source_title: "Original",
      },
      on_created=_ => (),
      on_worktree_changed=(_, rows) => placements.push(rows),
    )
    assert_eq(
      store.load(SessionId(reply.session)).system_prompt(),
      "dir=\{checkout.to_string()} model=edit-model through=2",
    )
    // An edit works where its source did; the host has nothing to add.
    assert_false(
      @fsx.exists(
        @workspaces.store_root(repo).join("notice-\{reply.session}").to_path(),
      ),
    )
    guard placements is [[row]] else {
      fail("the edit's binding must be broadcast once")
    }
    assert_eq(row.sessions, ["s-src", reply.session])
    assert_eq(
      @worktree.run_dir(repo, reply.session).to_string(),
      checkout.to_string(),
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "a fork is committed exactly when its record was written" {
  with_worktree_fork_fixture((manager, repo, store, checkout) => {
    let placements : Array[Array[WorktreeInfo]] = []
    let created : Array[String] = []
    async fn fork_with(model : String) -> @protocol.SessionForkReply? {
      let payload : @protocol.SessionForkPayload = {
        session: "s-src",
        workspace: repo.resource_path(),
        through: 2,
        model,
        source_title: "Original",
        side_chat: None,
      }
      Some(
        fork_session(
          manager,
          payload,
          on_created=session => created.push(session),
          on_worktree_changed=(_, rows) => placements.push(rows),
        ),
      ) catch {
        EngineError(_) => None
        error => raise error
      }
    }

    // The engine refused before writing anything: no fork, no worktree.
    assert_true(fork_with("fails-before") is None)
    guard @worktree.list(repo.to_string()).worktrees is [row] else {
      fail("a refused fork must leave only the source's worktree")
    }
    assert_eq(row.sessions, ["s-src"])
    assert_eq(@fs.readdir(repo.join(".worktrees").to_string()).length(), 1)
    assert_eq(placements.length(), 0)
    assert_eq(created.length(), 0)
    // The engine wrote the record and then failed. The fork exists, so the
    // request reports it like any other: clients learn of it, it keeps its
    // title, and it works in the worktree made for it.
    guard fork_with("fails-after") is Some(reply) else {
      fail("a fork whose record exists must be reported as made")
    }
    assert_eq(created, [reply.session])
    assert_true(store.exists(SessionId(reply.session)))
    assert_eq(store.title(SessionId(reply.session)), Some("Original"))
    guard placements is [[_, reported]] else {
      fail("the fork's worktree must be broadcast once")
    }
    assert_eq(reported.sessions, [reply.session])
    assert_true(reported.present)
    assert_true(@worktree.run_dir(repo, reply.session) != checkout)
    // Likewise when the engine succeeded but printed more than the id.
    guard fork_with("noisy") is Some(noisy) else {
      fail("what the engine printed must not undo a fork it wrote")
    }
    assert_true(store.exists(SessionId(noisy.session)))
    assert_eq(created, [reply.session, noisy.session])
  })
}

///|
#cfg(not(platform="windows"))
async test "a fork cancelled after its record was written keeps its worktree and is announced" {
  with_worktree_fork_fixture((manager, repo, store, checkout) => {
    let placements : Array[Array[WorktreeInfo]] = []
    let created : Array[String] = []
    let committed = @workspaces.store_root(repo).join("committed").to_path()
    @async.with_task_group(group => {
      let request = group.spawn(() => {
        ignore(
          fork_session(
            manager,
            {
              session: "s-src",
              workspace: repo.resource_path(),
              through: 2,
              model: "hangs-after",
              source_title: "Original",
              side_chat: None,
            },
            on_created=session => created.push(session),
            on_worktree_changed=(_, rows) => placements.push(rows),
          ),
        )
      })
      while !@fsx.exists(committed) {
        @async.sleep(1)
      }
      request.cancel()
      let cancelled = try {
        request.wait()
        false
      } catch {
        @async.WaitedTaskAlreadyCancelled => true
        _ => false
      }
      assert_true(cancelled)
    })
    // The request has no reply to give, but the fork is there: every client
    // hears of it, it has its title, and it works in the worktree made for
    // it.
    let fork = @fsx.read_text(committed)
    assert_true(store.exists(SessionId(fork)))
    assert_eq(created, [fork])
    assert_eq(store.title(SessionId(fork)), Some("Original"))
    guard placements is [[_, row]] else {
      fail("the fork's worktree must be broadcast once")
    }
    assert_eq(row.sessions, [fork])
    let fork_checkout = @worktree.run_dir(repo, fork)
    assert_true(fork_checkout != checkout)
    assert_true(@fsx.is_dir(fork_checkout.to_path()))
  })
}

///|
#cfg(not(platform="windows"))
async test "a side chat is a numbered member of its conversation's family" {
  with_worktree_fork_fixture((manager, repo, store, checkout) => {
    let placements : Array[Array[WorktreeInfo]] = []
    let created : Array[String] = []
    async fn side_chat_of(session : String) -> @protocol.SessionForkReply {
      fork_session(
        manager,
        {
          session,
          workspace: repo.resource_path(),
          through: 2,
          model: "fork-model",
          source_title: "Original",
          side_chat: Some(true),
        },
        on_created=session => created.push(session),
        on_worktree_changed=(_, rows) => placements.push(rows),
      )
    }

    // Side chats are named beside their conversation, each its own, and
    // work in the conversation's checkout.
    let first = side_chat_of("s-src")
    let second = side_chat_of("s-src")
    assert_eq(@protocol.split_side_chat_id(first.session), Some("s-src"))
    assert_eq(@protocol.split_side_chat_id(second.session), Some("s-src"))
    assert_true(first.session != second.session)
    assert_eq(created, [first.session, second.session])
    assert_eq(store.title(SessionId(first.session)), Some("Original"))
    assert_eq(
      @worktree.run_dir(repo, second.session).to_string(),
      checkout.to_string(),
    )
    // A side chat opens none of its own.
    let nested = try {
      ignore(side_chat_of(first.session))
      false
    } catch {
      EngineError(_) => true
      error => raise error
    }
    assert_true(nested)
    // Closing one keeps the checkout the conversation still works in.
    assert_true(
      delete_session(manager, first.session, repo.resource_path(), (_, _) => ())
      is Deleted,
    )
    assert_true(@fsx.is_dir(checkout.to_path()))
    guard @worktree.list(repo.to_string()).worktrees is [row] else {
      fail("the worktree row must survive a closed side chat")
    }
    assert_eq(row.sessions, ["s-src", second.session])
    let third = side_chat_of("s-src")
    // Its side chats leave with the conversation, so they do not keep the
    // checkout from the conversation's own delete or archive.
    assert_true(
      delete_session_check(manager, "s-src", repo.resource_path()).checkout
      is Some(_),
    )
    // Archiving the conversation takes its side chats along, and with them
    // the last holders of the checkout.
    assert_true(archive_session(manager, "s-src", (_, _) => ()) is Archived(_))
    assert_false(store.exists(SessionId(second.session)))
    assert_false(store.exists(SessionId(third.session)))
    assert_false(@fsx.exists(checkout.to_path()))
  })
}
