///|
async fn invoke_start_endpoint(
  state : @api.ApiState,
  name : String,
  params : Json,
) -> @protocol.SessionStartsSnapshot {
  let endpoints = @api.endpoints(state, HostConnection())
  guard endpoints.iter().find_first(endpoint => endpoint.name() == name)
    is Some(endpoint) else {
    fail("missing session suggestion endpoint")
  }
  @json.from_json(endpoint.invoke(params))
}

///|
#cfg(not(platform="windows"))
async test "session start MCP proposes without creating and user decisions submit once" {
  session_mcp_env_test_lock.acquire()
  defer session_mcp_env_test_lock.release()
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="seekmoon-start-proposals-")),
  ).resolve()
  defer @fs.rmdir(root.to_string(), recursive=true)
  let previous = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.to_string())
  defer (match previous {
    Some(value) => @sys.set_env_var("HOME", value)
    None => @sys.unset_env_var("HOME")
  })
  let workspace = root.join("project")
  @fs.mkdir(workspace.to_string())
  ignore(@workspaces.add(workspace.to_string(), _ => ()))
  guard workspace.to_uri_path() is Some(workspace_uri) else {
    fail("unsupported fixture workspace path")
  }
  let source = "source"
  let directory = workspace.join(".openseek/sessions").join(source)
  @fs.mkdir(directory.to_string(), recursive=true)
  let source_record =
    #|{"version":1,"id":"source","system_prompt":""}
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"Discuss a task"}}}
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"finished","message":"ok"}}}
    #|
  @fs.write_file(
    directory.join("openseek_session-source.jsonl").to_string(),
    source_record,
  )
  // This fixture implements the engine's append-before-notify contract. It
  // never calls a model, and leaves "hold-open" running to exercise steering.
  let script = root.join("engine.py").to_string()
  // Resolve Python before the engine prepends its bundled toolchain to PATH.
  let (python_status, python_output, _) = @processx.collect_output_no_stdin(
    "python3",
    ["-c", "import sys; print(sys.executable)"],
  )
  assert_eq(python_status, 0)
  let python = python_output.text().trim().to_owned()
  let engine_script =
    #|import json, os, pathlib, sys
    #|arguments = dict(arg[2:].split('=', 1) for arg in sys.argv[1:] if arg.startswith('--') and '=' in arg)
    #|if len(sys.argv) > 1 and sys.argv[1] == 'sessions':
    #|    print('[]', flush=True)
    #|    sys.exit(0)
    #|session = arguments['session']
    #|store = pathlib.Path(arguments['session-root'])
    #|record = store / 'sessions' / session / ('openseek_session-' + session + '.jsonl')
    #|def commit(item):
    #|    record.parent.mkdir(parents=True, exist_ok=True)
    #|    if not record.exists():
    #|        record.write_text(json.dumps({'version':1,'id':session,'system_prompt':''}) + '\n')
    #|    sequence = len(record.read_text().splitlines())
    #|    with record.open('a') as output:
    #|        output.write(json.dumps({'sequence':sequence,'item':item}) + '\n')
    #|        output.flush()
    #|        os.fsync(output.fileno())
    #|    (record.parent / 'fixture-options.json').write_text(json.dumps({'model':os.environ.get('OPENSEEK_MODEL'), 'thinking':os.environ.get('OPENSEEK_THINKING'), 'max_steps':os.environ.get('OPENSEEK_MAX_STEPS'), 'cwd':os.getcwd(), 'approval':sys.argv[sys.argv.index('--approval') + 1]}))
    #|for line in sys.stdin:
    #|    command = json.loads(line)
    #|    if command['command'] == 'jobs_snapshot':
    #|        print(json.dumps({'event':'jobs_snapshot','request_id':command['request_id'],'jobs':[]}), flush=True)
    #|    elif command['command'] == 'cancel':
    #|        print(json.dumps({'event':'agent_aborted','reason':'stopped'}), flush=True)
    #|    elif command['command'] in ('prompt', 'steer'):
    #|        if command['content'] == 'pause-before-write':
    #|            continue
    #|        if command['content'] == 'retry-once' and not (store / 'failed-once').exists():
    #|            (store / 'failed-once').write_text('failed before user commit')
    #|            print(json.dumps({'event':'agent_finished','answer':'fixture failure'}), flush=True)
    #|            continue
    #|        commit({'kind':'user','payload':{'content':command['content'],'submission_id':command.get('submission_id')}})
    #|        if (command['command'] == 'prompt' and command['content'] != 'hold-open') or command['content'] == 'finish-current':
    #|            commit({'kind':'terminal','payload':{'kind':'finished','message':'ok'}})
    #|            print(json.dumps({'event':'agent_finished','answer':'ok'}), flush=True)
    #|
  @fs.write_file(script, "#!" + python + "\n" + engine_script)
  @fs.chmod(script, 0o700)
  let server = @mcp.Server([], version="test")
  let state = @api.ApiState(
    engine=script,
    runtime_dir=root.to_path(),
    host_mcp=server,
  )
  ignore(
    @engine.update_settings(state.manager(), {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      glm_api_key: None,
      custom_api_key: None,
    }),
  )
  let notifications : @async.Queue[@protocol.Notification] = Queue(
    kind=Blocking(64),
  )
  let subscription = state.subscribe(
    notifications,
    map=notification => Some(notification),
    on_lag=sub => sub.close(),
  )
  defer subscription.close()
  @async.with_task_group(group => {
    state.start_services(group)
    let connected = @async.with_timeout(5000, () => {
      for ;; {
        if notifications.get() is AgentConnected(payload) {
          break payload
        }
      }
    })
    let grant = server.grant(source)
    guard grant.get(@mcp.TokenEnv) is Some(token) else {
      fail("missing MCP grant")
    }
    let connection = @streamhttp.connect(
      group,
      url=server.url(),
      headers={ "Authorization": "Bearer " + token },
      client_name="test",
      client_version="test",
    )
    defer connection.shutdown()
    let client = connection.client()
    let request : Json = {
      "action": "start",
      "request_id": "first",
      "title": "A separate task",
      "task": "Do the separate task",
      "workspace": workspace_uri,
      "workspace_mode": "local",
    }
    let proposed = client.call_tool(name="session", arguments=request)
    assert_false(proposed.is_error)
    let proposal : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(proposed.render_text()),
    )
    assert_eq(proposal.status, "pending")
    assert_true(proposal.target_session is None)
    assert_false(@fs.exists(workspace.join(".worktrees").to_string()))
    let target = "s" + proposal.id
    assert_false(
      @fs.exists(workspace.join(".openseek/sessions").join(target).to_string()),
    )
    let repeated = client.call_tool(name="session", arguments=request)
    assert_false(repeated.is_error)
    let recovered : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(repeated.render_text()),
    )
    assert_eq(recovered.id, proposal.id)
    assert_true(
      client.call_tool(name="session", arguments={
        "action": "start",
        "request_id": "first",
        "title": "Changed",
        "task": "different",
        "workspace": workspace_uri,
      }).is_error,
    )
    let decision : Json = {
      "session": source,
      "request_id": "first",
      "action": "start",
    }
    let left = group.spawn(() => {
      invoke_start_endpoint(state, "session.starts_decide", decision)
    })
    let right = group.spawn(() => {
      invoke_start_endpoint(state, "session.starts_decide", decision)
    })
    let started = left.wait()
    let other = right.wait()
    assert_eq(other, started)
    guard started.proposals is [created] else { fail("expected one proposal") }
    assert_eq(created.status, "started")
    assert_eq(created.target_session, Some(target))
    let loaded = @engine.load_session(state.manager(), {
      session: target,
      workspace: Some(workspace_uri),
    })
    let receipt = "session-start-" + proposal.id
    assert_eq(
      loaded.session.events
      .unwrap_or([])
      .filter(event => {
        event.item is User(user) && user.submission_id == Some(receipt)
      })
      .length(),
      1,
    )
    let reopened = @api.ApiState(engine=script)
    assert_eq(
      invoke_start_endpoint(reopened, "session.starts_list", {
        "session": source,
      }),
      started,
    )
    assert_eq(
      invoke_start_endpoint(reopened, "session.starts_decide", decision),
      started,
    )
    let after_start = client.call_tool(name="session", arguments=request)
    assert_false(after_start.is_error)
    let after_start : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(after_start.render_text()),
    )
    assert_eq(after_start.target_session, Some(target))
    // A host can restart after the input commits but before the card folds.
    ignore(
      @engine.with_session_starts(state.manager(), source, _ => (), store => {
        store.save(
          store.snapshot().proposals.map(value => {
            if value.id == proposal.id {
              { ..value, status: "starting", title: "Recovered task title", }
            } else {
              value
            }
          }),
        )
      }),
    )
    let reconciled = invoke_start_endpoint(reopened, "session.starts_list", {
      "session": source,
    })
    assert_eq(reconciled.proposals[0].status, "started")
    // Worktree selection and engine options reach the real host launch path.
    let (git_status, _, _) = @processx.collect_output_no_stdin("git", [
      "init",
      "-q",
      workspace.to_string(),
    ])
    assert_eq(git_status, 0)
    let (commit_status, _, _) = @processx.collect_output_no_stdin("git", [
      "-C",
      workspace.to_string(),
      "-c",
      "user.name=Fixture",
      "-c",
      "user.email=fixture@example.invalid",
      "commit",
      "--allow-empty",
      "-qm",
      "fixture",
    ])
    assert_eq(commit_status, 0)
    let tree_proposed = client.call_tool(name="session", arguments={
      "action": "start",
      "request_id": "tree",
      "title": "Worktree task",
      "task": "Use a worktree",
      "workspace": workspace_uri,
      "workspace_mode": "worktree",
      "model": "suggested-model",
      "thinking": "max",
      "max_steps": 9,
    })
    assert_false(tree_proposed.is_error)
    let tree_proposal : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(tree_proposed.render_text()),
    )
    assert_eq(@worktree.list(workspace_uri).worktrees.length(), 0)
    let tree_snapshot = invoke_start_endpoint(state, "session.starts_decide", {
      "session": source,
      "request_id": "tree",
      "action": "start",
      "model": "selected-model",
    })
    guard tree_snapshot.proposals
      .iter()
      .find_first(value => value.request_id == "tree")
      is Some(tree_started) &&
      tree_started.target_session is Some(tree_target) else {
      fail("missing worktree target")
    }
    assert_eq(tree_started.status, "started")
    assert_eq(@worktree.list(workspace_uri).worktrees.length(), 1)
    guard @worktree.tree_dir(workspace, tree_target) is Some(tree_dir) else {
      fail("missing worktree directory")
    }
    let tree_options : Map[String, String] = @json.from_json(
      @json.parse(
        @fs.read_file(
          workspace
          .join(".openseek/sessions")
          .join(tree_target)
          .join("fixture-options.json")
          .to_string(),
        ).text(),
      ),
    )
    assert_eq(tree_options["model"], "selected-model")
    assert_eq(tree_options["thinking"], "max")
    assert_eq(tree_options["max_steps"], "9")
    assert_eq(tree_options["cwd"], tree_dir.to_string())
    assert_eq(tree_options["approval"], "ask")
    assert_eq(tree_started.id, tree_proposal.id)
    // An idle source receives a normal prompt; an active source is steered.
    let mut source_run = ""
    for request_id in ["here-idle", "here-active"] {
      if request_id == "here-active" {
        source_run = @engine.start_run(state.sink(), state.manager(), {
            session: source,
            workspace: Some(workspace_uri),
            task: "hold-open",
            images: [],
            submission_id: Some("hold-source"),
            model: None,
            thinking: None,
            approval: None,
            max_steps: None,
          }).run_id
        @async.with_timeout(5000, () => {
          while !@engine.load_session(state.manager(), {
                  session: source,
                  workspace: None,
                }).session.events
                .unwrap_or([])
                .any(event => {
                  event.item is User(user) &&
                  user.submission_id == Some("hold-source")
                }) {
            @async.sleep(10)
          }
        })
      }
      let result = client.call_tool(name="session", arguments={
        "action": "start",
        "request_id": request_id,
        "title": "Do here",
        "task": request_id,
        "workspace": workspace_uri,
      })
      assert_false(result.is_error)
      let here : @protocol.SessionStartProposal = @json.from_json(
        @json.parse(result.render_text()),
      )
      let snapshot = invoke_start_endpoint(state, "session.starts_decide", {
        "session": source,
        "request_id": request_id,
        "action": "here",
        "here": {
          "model": "current-source-model",
          "thinking": "high",
          "approval": "review",
          "max_steps": 7,
          "followup_behavior": "steer",
        },
      })
      guard snapshot.proposals
        .iter()
        .find_first(value => value.request_id == request_id)
        is Some(done) else {
        fail("missing Here proposal")
      }
      assert_eq(done.status, "here")
      assert_eq(done.target_session, Some(source))
      let loaded = @engine.load_session(state.manager(), {
        session: source,
        workspace: None,
      })
      let id = "session-start-" + here.id
      assert_eq(
        loaded.session.events
        .unwrap_or([])
        .filter(event => {
          event.item is User(user) && user.submission_id == Some(id)
        })
        .length(),
        1,
      )
      assert_false(
        @fs.exists(
          workspace.join(".openseek/sessions").join("s" + here.id).to_string(),
        ),
      )
      let options : Map[String, String] = @json.from_json(
        @json.parse(
          @fs.read_file(directory.join("fixture-options.json").to_string()).text(),
        ),
      )
      if request_id == "here-idle" {
        assert_eq(options["model"], "current-source-model")
        assert_eq(options["thinking"], "high")
        assert_eq(options["max_steps"], "7")
        assert_eq(options["approval"], "review")
      } else {
        // A running source keeps the process configuration that ordinary
        // Send uses even when its composer is now set to review mode.
        assert_eq(options["approval"], "ask")
      }
    }
    // Queue follows ordinary Send policy, but stopped or withdrawn hosted
    // input must release its card for retry instead of waiting indefinitely.
    for outcome in ["promote", "withdraw", "stop"] {
      if outcome != "promote" {
        source_run = @engine.start_run(state.sink(), state.manager(), {
            session: source,
            workspace: Some(workspace_uri),
            task: "hold-open",
            images: [],
            submission_id: Some("hold-" + outcome),
            model: None,
            thinking: None,
            approval: None,
            max_steps: None,
          }).run_id
        @async.with_timeout(5000, () => {
          while !(notifications.get() is SessionEvent(commit) &&
                commit.session == source &&
                commit.event.item is User(user) &&
                user.submission_id == Some("hold-" + outcome)) {
            ()
          }
        })
      }
      let request_id = "here-queue-" + outcome
      let proposed = client.call_tool(name="session", arguments={
        "action": "start",
        "request_id": request_id,
        "title": "Queued task",
        "task": request_id,
        "workspace": workspace_uri,
      })
      assert_false(proposed.is_error)
      let proposal : @protocol.SessionStartProposal = @json.from_json(
        @json.parse(proposed.render_text()),
      )
      let id = "session-start-" + proposal.id
      let queued = group.spawn(() => {
        invoke_start_endpoint(state, "session.starts_decide", {
          "session": source,
          "request_id": request_id,
          "action": "here",
          "here": { "followup_behavior": "queue" },
        })
      })
      // QueueEdit is the ordinary public queue operation: accepted means the
      // input has actually entered the queue and has not reached the engine.
      @async.with_timeout(5000, () => {
        while !@engine.queue_run(state.manager(), {
                run_id: source_run,
                action: QueueEdit(id~, text=request_id, images=[]),
              }).accepted {
          @async.sleep(10)
        }
      })
      let refreshing = @async.with_timeout(1000, () => {
        invoke_start_endpoint(reopened, "session.starts_list", {
          "session": source,
        })
      })
      assert_true(
        refreshing.proposals.any(value => {
          value.request_id == request_id && value.status == "starting"
        }),
      )
      assert_false(
        @engine.load_session(state.manager(), {
          session: source,
          workspace: None,
        }).session.events
        .unwrap_or([])
        .any(event => event.item is User(user) && user.submission_id == Some(id)),
      )
      if outcome == "promote" {
        assert_true(
          @engine.steer_run(state.manager(), {
            text: "finish-current",
            images: [],
            run_id: Some(source_run),
            submission_id: None,
          }).steered,
        )
      } else if outcome == "withdraw" {
        assert_true(
          @engine.queue_run(state.manager(), {
            run_id: source_run,
            action: QueueWithdraw(id~),
          }).accepted,
        )
      } else {
        assert_eq(
          @engine.cancel_run(state.manager(), { run_id: Some(source_run), }).run_id,
          Some(source_run),
        )
      }
      let completed = @async.with_timeout(5000, () => queued.wait())
      guard completed.proposals
        .iter()
        .find_first(value => value.request_id == request_id)
        is Some(done) else {
        fail("missing queued Here outcome")
      }
      assert_eq(
        done.status,
        if outcome == "promote" {
          "here"
        } else {
          "failed"
        },
      )
      if outcome == "withdraw" {
        ignore(
          @engine.cancel_run(state.manager(), { run_id: Some(source_run), }),
        )
      }
      @async.with_timeout(5000, () => {
        while !(notifications.get() is AgentFinished(finished) &&
              finished.run_id == source_run) {
          ()
        }
      })
    }
    let result = client.call_tool(name="session", arguments={
      "action": "start",
      "request_id": "retry",
      "title": "Retry task",
      "task": "retry-once",
      "workspace": workspace_uri,
    })
    assert_false(result.is_error)
    let retry : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(result.render_text()),
    )
    let failed = invoke_start_endpoint(state, "session.starts_decide", {
      "session": source,
      "request_id": "retry",
      "action": "start",
    })
    guard failed.proposals
      .iter()
      .find_first(value => value.request_id == "retry")
      is Some(failed) else {
      fail("missing failed proposal")
    }
    assert_eq(failed.status, "failed")
    let retried = invoke_start_endpoint(state, "session.starts_decide", {
      "session": source,
      "request_id": "retry",
      "action": "start",
    })
    guard retried.proposals
      .iter()
      .find_first(value => value.request_id == "retry")
      is Some(retried) else {
      fail("missing retried proposal")
    }
    assert_eq(retried.status, "started")
    assert_eq(retried.target_session, failed.target_session)
    assert_eq(retried.id, retry.id)
    // The engine supervisor can replace a generation without delivering the
    // old consumer's Finished event. Its public reset notice settles startup.
    let reset_result = client.call_tool(name="session", arguments={
      "action": "start",
      "request_id": "pump-reset",
      "title": "Reset task",
      "task": "pause-before-write",
      "workspace": workspace_uri,
    })
    assert_false(reset_result.is_error)
    let reset_proposal : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(reset_result.render_text()),
    )
    let reset_target = "s" + reset_proposal.id
    let reset = group.spawn(() => {
      invoke_start_endpoint(state, "session.starts_decide", {
        "session": source,
        "workspace": workspace_uri,
        "request_id": "pump-reset",
        "action": "start",
      })
    })
    let reset_started = @async.with_timeout(5000, () => {
      for ;; {
        if notifications.get() is AgentStarted(payload) &&
          payload.session == reset_target {
          break payload
        }
      }
    })
    state.publish(AgentConnected(connected))
    let reset_snapshot = @async.with_timeout(5000, () => reset.wait())
    guard reset_snapshot.proposals
      .iter()
      .find_first(value => value.id == reset_proposal.id)
      is Some(reset_failed) else {
      fail("missing reset result")
    }
    assert_eq(reset_failed.status, "failed")
    assert_true(reset_failed.error is Some(_))
    assert_eq(
      @engine.try_with_session_start_decision(
        source,
        reset_proposal.id,
        () => true,
        workspace=workspace_uri,
      ),
      Some(true),
    )
    ignore(
      @engine.cancel_run(state.manager(), {
        run_id: Some(reset_started.run_id),
      }),
    )
    // Full service shutdown sends no replacement Connected event. Receipt
    // closure must still release the shielded request and its operation lock.
    let shutdown_result = client.call_tool(name="session", arguments={
      "action": "start",
      "request_id": "service-shutdown",
      "title": "Shutdown task",
      "task": "pause-before-write",
      "workspace": workspace_uri,
    })
    assert_false(shutdown_result.is_error)
    let shutdown_proposal : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(shutdown_result.render_text()),
    )
    let quiet = @api.ApiState(engine=script, runtime_dir=root.to_path())
    let quiet_events : @async.Queue[@protocol.Notification] = Queue(
      kind=Blocking(64),
    )
    let quiet_subscription = quiet.subscribe(
      quiet_events,
      map=value => Some(value),
      on_lag=sub => sub.close(),
    )
    defer quiet_subscription.close()
    @async.with_timeout(5000, () => {
      @async.with_task_group(owner => {
        quiet.start_services(owner)
        while !(quiet_events.get() is AgentConnected(_)) {
          ()
        }
        ignore(
          owner.spawn(() => {
            ignore(
              invoke_start_endpoint(quiet, "session.starts_decide", {
                "session": source,
                "workspace": workspace_uri,
                "request_id": "service-shutdown",
                "action": "start",
              }),
            )
          }),
        )
        while !(quiet_events.get() is AgentStarted(payload) &&
              payload.session == "s" + shutdown_proposal.id) {
          ()
        }
        owner.return_immediately(())
      })
    })
    let after_shutdown = @engine.session_starts_list(
      state.manager(),
      source,
      workspace=workspace_uri,
    )
    guard after_shutdown.proposals
      .iter()
      .find_first(value => value.id == shutdown_proposal.id)
      is Some(shutdown_failed) else {
      fail("missing shutdown result")
    }
    assert_eq(shutdown_failed.status, "failed")
    assert_eq(
      @engine.try_with_session_start_decision(
        source,
        shutdown_proposal.id,
        () => true,
        workspace=workspace_uri,
      ),
      Some(true),
    )
    // Archive can move the source while an already accepted target is waiting
    // for its first user commit. The result follows that same source record.
    let archive_result = client.call_tool(name="session", arguments={
      "action": "start",
      "request_id": "archive-source",
      "title": "Archived source task",
      "task": "pause-before-write",
      "workspace": workspace_uri,
    })
    assert_false(archive_result.is_error)
    let archive_proposal : @protocol.SessionStartProposal = @json.from_json(
      @json.parse(archive_result.render_text()),
    )
    let archive_target = "s" + archive_proposal.id
    let archival = group.spawn(() => {
      invoke_start_endpoint(state, "session.starts_decide", {
        "session": source,
        "workspace": workspace_uri,
        "request_id": "archive-source",
        "action": "start",
      })
    })
    @async.with_timeout(5000, () => {
      while !(notifications.get() is AgentStarted(payload) &&
            payload.session == archive_target) {
        ()
      }
    })
    ignore(@engine.archive_session(state.manager(), source, (_, _) => ()))
    seed_start_record(
      workspace,
      archive_target,
      "session-start-" + archive_proposal.id,
    )
    let archived_completion = @async.with_timeout(5000, () => archival.wait())
    assert_eq(archived_completion.workspace, Some(workspace_uri))
    assert_eq(archived_completion.archived, Some(true))
    assert_true(
      archived_completion.proposals.any(value => {
        value.id == archive_proposal.id && value.status == "started"
      }),
    )
    assert_false(
      @fs.exists(workspace.join(".openseek/sessions/source").to_string()),
    )
    assert_eq(
      invoke_start_endpoint(reopened, "session.starts_list", {
        "session": source,
        "workspace": workspace_uri,
        "archived": true,
      }),
      archived_completion,
    )
    group.return_immediately(())
  })
}

///|
async fn seed_start_record(
  workspace : @pathx.Absolute,
  session : String,
  submission_id : String,
) -> Unit {
  let directory = workspace.join(".openseek/sessions").join(session)
  @fs.mkdir(directory.to_string(), recursive=true)
  let header : Json = { "version": 1, "id": session, "system_prompt": "" }
  let user : Json = {
    "sequence": 1,
    "item": {
      "kind": "user",
      "payload": { "content": "Fixture task", "submission_id": submission_id },
    },
  }
  let terminal : Json = {
    "sequence": 2,
    "item": {
      "kind": "terminal",
      "payload": { "kind": "finished", "message": "done" },
    },
  }
  @fs.write_file(
    directory.join("openseek_session-" + session + ".jsonl").to_string(),
    header.stringify() +
    "\n" +
    user.stringify() +
    "\n" +
    terminal.stringify() +
    "\n",
  )
}

///|
fn recovery_start_proposal(
  workspace : String,
  request_id : String,
  id : String,
  target : String,
) -> @protocol.SessionStartProposal raise {
  let request : @protocol.SessionStartRequest = @json.from_json({
    "request_id": request_id,
    "title": "Suggestion " + request_id,
    "task": "Recover this task",
    "workspace": workspace,
  })
  { ..request.proposal(id), status: "starting", target_session: Some(target), }
}

///|
#cfg(not(platform="windows"))
async test "session start recovery preserves user titles and isolates archived or unreadable targets" {
  session_mcp_env_test_lock.acquire()
  defer session_mcp_env_test_lock.release()
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="seekmoon-start-recovery-")),
  ).resolve()
  defer @fs.rmdir(root.to_string(), recursive=true)
  let previous = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.to_string())
  defer (if previous is Some(value) {
    @sys.set_env_var("HOME", value)
  } else {
    @sys.unset_env_var("HOME")
  })
  let workspace = root.join("project")
  @fs.mkdir(workspace.to_string())
  ignore(@workspaces.add(workspace.to_string(), _ => ()))
  guard workspace.to_uri_path() is Some(workspace_uri) else {
    fail("unsupported fixture workspace")
  }
  seed_start_record(workspace, "source", "source-input")
  seed_start_record(workspace, "first-target", "session-start-first")
  seed_start_record(workspace, "good-target", "session-start-good")
  seed_start_record(workspace, "bad-target", "session-start-bad")
  @fs.write_file(
    workspace
    .join(".openseek/sessions/bad-target/openseek_session-bad-target.jsonl")
    .to_string(),
    "invalid record\n",
  )
  let first = recovery_start_proposal(
    workspace_uri, "first", "first", "first-target",
  )
  let good = recovery_start_proposal(
    workspace_uri, "good", "good", "good-target",
  )
  let bad = recovery_start_proposal(workspace_uri, "bad", "bad", "bad-target")
  let state = @api.ApiState(engine="unused-engine")
  let notifications : @async.Queue[@protocol.Notification] = Queue(
    kind=Blocking(64),
  )
  let subscription = state.subscribe(notifications, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer subscription.close()
  @async.with_task_group(group => {
    state.start_services(group)
    @async.with_timeout(5000, () => {
      while !(notifications.get() is AgentConnected(_)) {
        ()
      }
    })
    ignore(
      @engine.with_session_starts(state.manager(), "source", _ => (), store => {
        store.save([first])
      }),
    )
    let initial = invoke_start_endpoint(state, "session.starts_list", {
      "session": "source",
      "workspace": workspace_uri,
    })
    assert_eq(initial.proposals[0].status, "started")
    let title_file = workspace.join(
      ".openseek/sessions/first-target/session-title",
    )
    assert_eq(@fs.read_file(title_file.to_string()).text(), "Suggestion first")
    @engine.rename_session(state.manager(), {
      session: "first-target",
      workspace: workspace_uri,
      title: "User renamed title",
    })
    ignore(
      @engine.with_session_starts(state.manager(), "source", _ => (), store => {
        store.save([first, bad, good])
      }),
    )
    let recovered = invoke_start_endpoint(state, "session.starts_list", {
      "session": "source",
      "workspace": workspace_uri,
    })
    assert_eq(recovered.proposals.map(proposal => proposal.status), [
      "started", "failed", "started",
    ])
    assert_true(recovered.proposals[1].error is Some(_))
    assert_eq(
      @fs.read_file(title_file.to_string()).text(),
      "User renamed title",
    )
    ignore(
      @engine.with_session_starts(state.manager(), "source", _ => (), store => {
        store.save(
          store.snapshot().proposals.map(proposal => {
            if proposal.id == first.id {
              first
            } else {
              proposal
            }
          }),
        )
      }),
    )
    let retried = invoke_start_endpoint(state, "session.starts_decide", {
      "session": "source",
      "request_id": "first",
      "action": "start",
    })
    assert_eq(retried.proposals[0].status, "started")
    assert_eq(
      @fs.read_file(title_file.to_string()).text(),
      "User renamed title",
    )
    let bad_retry = invoke_start_endpoint(state, "session.starts_decide", {
      "session": "source",
      "request_id": "bad",
      "action": "start",
    })
    assert_eq(bad_retry.proposals[1].status, "failed")
    let dismissed = invoke_start_endpoint(state, "session.starts_decide", {
      "session": "source",
      "request_id": "bad",
      "action": "dismiss",
    })
    assert_eq(dismissed.proposals[1].status, "dismissed")
    ignore(
      @engine.archive_session(state.manager(), "first-target", (_, _) => ()),
    )
    ignore(
      @engine.with_session_starts(state.manager(), "source", _ => (), store => {
        store.save(
          store.snapshot().proposals.map(proposal => {
            if proposal.id == first.id {
              first
            } else {
              proposal
            }
          }),
        )
      }),
    )
    let archived_target = invoke_start_endpoint(state, "session.starts_list", {
      "session": "source",
      "workspace": workspace_uri,
    })
    assert_eq(archived_target.proposals[0].status, "started")
    assert_false(
      @fs.exists(workspace.join(".openseek/sessions/first-target").to_string()),
    )
    assert_eq(
      @fs.read_file(
        workspace
        .join(".openseek/archived/sessions/first-target/session-title")
        .to_string(),
      ).text(),
      "User renamed title",
    )
    // A cold archived source returns exactly its saved sidecar, including an
    // interrupted state, and performs no launch or recovery mutation.
    let before_archive = @engine.with_session_starts(
      state.manager(),
      "source",
      _ => (),
      store => {
        store.save(
          store.snapshot().proposals.map(proposal => {
            if proposal.id == first.id {
              first
            } else {
              proposal
            }
          }),
        )
      },
    )
    ignore(@engine.archive_session(state.manager(), "source", (_, _) => ()))
    let archived_file = workspace.join(
      ".openseek/archived/sessions/source/session-starts.json",
    )
    let untouched = @fs.read_file(archived_file.to_string()).text()
    let cold = @api.ApiState(engine="unused-engine")
    let archived_source = invoke_start_endpoint(cold, "session.starts_list", {
      "session": "source",
      "workspace": workspace_uri,
      "archived": true,
    })
    assert_eq(archived_source, { ..before_archive, archived: Some(true), })
    assert_eq(@fs.read_file(archived_file.to_string()).text(), untouched)
    let rejected = try {
      ignore(
        invoke_start_endpoint(cold, "session.starts_decide", {
          "session": "source",
          "request_id": "first",
          "action": "start",
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    let other = root.join("other-project")
    @fs.mkdir(other.to_string())
    ignore(@workspaces.add(other.to_string(), _ => ()))
    guard other.to_uri_path() is Some(other_uri) else {
      fail("unsupported second workspace")
    }
    @fs.mkdir(
      other.join(".openseek/archived/sessions/source").to_string(),
      recursive=true,
    )
    let other_snapshot : @protocol.SessionStartsSnapshot = {
      session: "source",
      workspace: Some(other_uri),
      archived: Some(true),
      generation: 99,
      proposals: [],
    }
    // Legacy files have no scope fields; the selected record supplies them.
    @fs.write_file(
      other
      .join(".openseek/archived/sessions/source/session-starts.json")
      .to_string(),
      ({ "session": "source", "generation": 99, "proposals": [] } : Json).stringify(),
    )
    assert_eq(
      invoke_start_endpoint(cold, "session.starts_list", {
        "session": "source",
        "workspace": other_uri,
        "archived": true,
      }),
      other_snapshot,
    )
    assert_eq(
      invoke_start_endpoint(cold, "session.starts_list", {
        "session": "source",
        "workspace": workspace_uri,
        "archived": true,
      }),
      { ..before_archive, archived: Some(true), },
    )
    // Same-id live sources also retain their selected store through a user
    // decision and its notification; one client's Dismiss cannot touch another.
    seed_start_record(workspace, "shared-source", "source-a")
    seed_start_record(other, "shared-source", "source-b")
    let from_a = recovery_start_proposal(
      workspace_uri, "shared", "proposal-a", "unused-a",
    )
    let from_b = recovery_start_proposal(
      other_uri, "shared", "proposal-b", "unused-b",
    )
    let pending_a : @protocol.SessionStartProposal = {
      ..from_a,
      status: "pending",
      target_session: None,
    }
    let pending_b : @protocol.SessionStartProposal = {
      ..from_b,
      status: "pending",
      target_session: None,
    }
    let snapshot_a = @engine.with_session_starts(
      state.manager(),
      "shared-source",
      _ => (),
      store => store.save([pending_a]),
      workspace=workspace_uri,
    )
    let snapshot_b = @engine.with_session_starts(
      state.manager(),
      "shared-source",
      _ => (),
      store => store.save([pending_b]),
      workspace=other_uri,
    )
    assert_eq(snapshot_a.workspace, Some(workspace_uri))
    assert_eq(snapshot_b.workspace, Some(other_uri))
    assert_eq(snapshot_b.archived, Some(false))
    let dismissed_b = invoke_start_endpoint(state, "session.starts_decide", {
      "session": "shared-source",
      "workspace": other_uri,
      "request_id": "shared",
      "action": "dismiss",
    })
    assert_eq(dismissed_b.workspace, Some(other_uri))
    assert_eq(dismissed_b.proposals[0].status, "dismissed")
    assert_eq(
      invoke_start_endpoint(state, "session.starts_list", {
        "session": "shared-source",
        "workspace": workspace_uri,
      }),
      snapshot_a,
    )
    @async.with_timeout(5000, () => {
      while !(notifications.get() is SessionStartsChanged(changed) &&
            changed == dismissed_b) {
        ()
      }
    })
    group.return_immediately(())
  })
}
