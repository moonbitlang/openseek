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
/// --session-root <root> --dir <dir> --model <model>`. It copies the record,
/// refuses an id that exists, writes what the host handed it — the directory,
/// the model, the cut — as the fork's system prompt, and prints the fork's
/// id. The model `fails-before` makes it fail without writing anything, and
/// `fails-after` once the record is written; `noisy` succeeds but prints more
/// than the id; `hangs-after` writes the record, leaves `<root>/committed` to
/// say so, and then never finishes. Any other
/// command lists no sessions, which is all archiving asks of it.
#cfg(not(platform="windows"))
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
    $|while [ "$#" -gt 1 ]; do
    $|  case "$1" in
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
async test "a fork of a worktree conversation works in the same checkout" {
  with_worktree_fork_fixture((manager, repo, store, checkout) => {
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
      },
      on_created=session => created.push(session),
      on_worktree_changed=(_, rows) => placements.push(rows),
    )
    assert_eq(created, [reply.session])
    // The engine wrote the fork's prompt in the original's checkout.
    assert_eq(
      store.load(SessionId(reply.session)).system_prompt(),
      "dir=\{checkout.to_string()} model=fork-model through=2",
    )
    assert_eq(store.title(SessionId(reply.session)), Some("Original"))
    guard placements is [[row]] else {
      fail("the fork's binding must be broadcast once")
    }
    assert_eq(row.sessions, ["s-src", reply.session])
    assert_eq(
      @worktree.run_dir(repo, reply.session).to_string(),
      checkout.to_string(),
    )
    // The checkout outlives the original's archive and goes with the fork's.
    assert_true(archive_session(manager, "s-src", (_, _) => ()) is Archived(_))
    assert_true(@fsx.is_dir(checkout.to_path()))
    assert_true(
      archive_session(manager, reply.session, (_, _) => ()) is Archived(_),
    )
    assert_false(@fsx.exists(checkout.to_path()))
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

    // The engine refused before writing anything: no fork, no binding.
    assert_true(fork_with("fails-before") is None)
    guard @worktree.list(repo.to_string()).worktrees is [row] else {
      fail("the worktree row must survive a refused fork")
    }
    assert_eq(row.sessions, ["s-src"])
    assert_eq(placements.length(), 0)
    assert_eq(created.length(), 0)
    // The engine wrote the record and then failed. The fork exists, so the
    // request reports it like any other: clients learn of it, it keeps its
    // title, and it works in the worktree it was made in.
    guard fork_with("fails-after") is Some(reply) else {
      fail("a fork whose record exists must be reported as made")
    }
    assert_eq(created, [reply.session])
    assert_true(store.exists(SessionId(reply.session)))
    assert_eq(store.title(SessionId(reply.session)), Some("Original"))
    assert_eq(
      @worktree.run_dir(repo, reply.session).to_string(),
      checkout.to_string(),
    )
    guard placements is [[reported]] else {
      fail("the fork's binding must be broadcast once")
    }
    assert_eq(reported.sessions, ["s-src", reply.session])
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
async test "a fork cancelled after its record was written is still bound and announced" {
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
    // hears of it, it has its title, and it works in the worktree it was
    // made in.
    let fork = @fsx.read_text(committed)
    assert_true(store.exists(SessionId(fork)))
    assert_eq(created, [fork])
    assert_eq(store.title(SessionId(fork)), Some("Original"))
    guard placements is [[row]] else {
      fail("the fork's binding must be broadcast once")
    }
    assert_eq(row.sessions, ["s-src", fork])
    assert_eq(@worktree.run_dir(repo, fork).to_string(), checkout.to_string())
  })
}
