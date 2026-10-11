///|
async fn Schedules::execute(
  self : Schedules,
  entry : @protocol.ScheduleEntry,
  run : @protocol.ScheduleRun,
  on_finished? : (@protocol.ScheduleRun) -> Unit,
  timeout_ms? : Int,
  sink? : EventSink,
  on_workspaces? : (Array[String]) -> Unit,
) -> Unit {
  let status : @protocol.ScheduleRunStatus = @async.with_task_group(group => {
    let record_guard = self.manager.begin_record_op(run.session)
    defer self.manager.end_record_op(run.session, record_guard)
    // The follower outlives the timed writer scope so Stop and timeout can
    // reap the CLI first, then drain its last durable commits.
    defer (if self.manager.followers.get(run.session) is Some(follower) {
      discard_follower_startup(self.manager, follower)
    })
    let status : @protocol.ScheduleRunStatus = try {
      @fs.write_file(
        run.log_path,
        "Starting scheduled task\n",
        create_mode=CreateOrTruncate,
        permission=0o600,
      )
      match
        @async.with_timeout_opt(
          timeout_ms.unwrap_or(entry.spec.timeout_minutes * 60000),
          () => self.run_cli(group, entry.spec, run, sink?, on_workspaces?),
        ) {
        Some(code) => scheduled_session_result(run, exit_code=code)
        None => TimedOut
      }
    } catch {
      error => Failed("\{error}")
    }
    if self.manager.followers.get(run.session) is Some(follower) {
      stop_follower_instance(self.manager, follower, writer_exited=true) catch {
        error =>
          @xlog.warn() <?
            { "event": "schedule_final_scan_failed", "message": "\{error}" }
      }
    }
    status
  }) catch {
    error => Failed("\{error}")
  }
  self.processes.remove(run.id)
  let status : @protocol.ScheduleRunStatus = if self.stopped.contains(run.id) {
    Stopped
  } else {
    status
  }
  self.stopped.remove(run.id)
  if status is Failed(message) {
    @fs.write_file(
      run.log_path,
      "\nFailed: " + message + "\n",
      create_mode=OpenOrCreate,
      append=true,
      permission=0o600,
    ) catch {
      error =>
        @xlog.warn() <?
          { "event": "schedule_log_write_failed", "message": "\{error}" }
    }
  }
  for ;; {
    @async.protect_from_cancel(() => {
      self.lock.acquire()
      defer self.lock.release()
      let state = self.load()
      let settled = { ..run, status, finished_at: Some(schedule_now()), }
      let runs = state.runs.map(item => {
        if item.id == run.id {
          settled
        } else {
          item
        }
      })
      self.commit({ ..state, runs, })
      if on_finished is Some(notify) {
        notify(settled)
      }
    }) catch {
      error => {
        @xlog.warn() <?
          { "event": "schedule_result_save_failed", "message": "\{error}" }
        @async.sleep(5000)
        continue
      }
    }
    break
  }
}

///|
// async 0.21 exposes abandoned stdin cleanup only through its deprecated
// close method; retain it until the dependency supplies a replacement.
#warnings("-deprecated")
async fn[G] Schedules::run_cli(
  self : Schedules,
  follower_group : @async.TaskGroup[G],
  spec : @protocol.ScheduleSpec,
  run : @protocol.ScheduleRun,
  sink? : EventSink,
  on_workspaces? : (Array[String]) -> Unit,
) -> Int {
  if spec.workspace is None {
    guard @pathx.Absolute::from_uri_path(run.workspace) is Some(directory) else {
      raise EngineError("Invalid automatic working directory")
    }
    @fsx.ensure_dir(directory.to_path())
    @workspaces.register_task_directory(directory, on_committed=paths => {
      if on_workspaces is Some(notify) {
        notify(paths.map(path => path.resource_path()))
      }
    })
  }
  let config = serve_config(
    spec.task,
    self.manager,
    model?=spec.model,
    max_steps=1000,
    session=run.session,
    workspace=run.workspace,
  )
  guard config.cwd is Some(cwd) && @fs.kind(cwd.to_string()) is Directory else {
    raise EngineError("The scheduled project's directory is unavailable")
  }
  let env = engine_process_env(config, self.manager.runtime_dir)
  let args = ["run", "--session=\{run.session}", "--dir=.", "--approval=never"]
  if config.session_root is Some(root) {
    args.push("--session-root=\{root.to_string()}")
  }
  args.append(["--", spec.task])
  if self.stopped.contains(run.id) {
    return 0
  }
  // File redirection keeps memory bounded and never leaves a pipe undrained.
  let output = @process.redirect_to_file(
    run.log_path,
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  defer output.close()
  let (input, writer) = @process.write_to_process()
  defer input.close()
  writer.close()
  @async.with_task_group(group => {
    if self.stopped.contains(run.id) {
      return 0
    }
    ignore(
      match sink {
        Some(sink) =>
          ensure_follower(
            sink~,
            group=follower_group,
            manager=self.manager,
            config~,
          )
        None => None
      },
    )
    let process = @process.spawn(
      group,
      config.engine,
      args,
      stdin=input,
      stdout=output,
      stderr=output,
      cwd=cwd.to_string(),
      extra_env=env,
      inherit_env=false,
      no_console_window=true,
      // The CLI runtime cancels its tools, whose default grace is 5s.
      // Leave time for their kill/reap barriers before killing the CLI.
      cancel_handler=@process.graceful_cancel(timeout=10000),
    )
    self.processes[run.id] = process
    if self.stopped.contains(run.id) {
      process.cancel()
    }
    process.wait()
  })
}

///|
// The CLI exits non-zero whenever its turn did not complete, so the exit code
// alone cannot say why. The session's durable terminal can: reuse it instead of
// parsing logs, and fall back to the exit code only when the turn has none.
async fn scheduled_session_result(
  run : @protocol.ScheduleRun,
  exit_code~ : Int,
) -> @protocol.ScheduleRunStatus {
  guard @pathx.Absolute::from_uri_path(run.workspace) is Some(workspace) else {
    raise EngineError("Invalid scheduled workspace")
  }
  let store = @store.SessionStore(@workspaces.store_root(workspace).to_string())
  // A CLI that failed before its first append left no session: that is a
  // turn without a terminal, and the exit code explains it. Any other load
  // failure is real and still raises.
  let terminal = store.load(SessionId(run.session)).last_terminal() catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => None
      error => raise error
    }
  schedule_run_status(terminal, exit_code~)
}

///|
fn schedule_run_status(
  terminal : @agent_session.TurnTerminal?,
  exit_code~ : Int,
) -> @protocol.ScheduleRunStatus {
  match terminal {
    Some(Finished(_)) if exit_code == 0 => Succeeded
    Some(Interrupted(_)) => Interrupted
    Some(ContextYield(_)) =>
      Failed(
        "Stopped at the model's context window before the task was done; see the run log",
      )
    Some(MaxStepsExhausted) => Failed(@agent_session.MaxStepsExhaustedMessage)
    Some(Failed(message)) | Some(Aborted(message)) => Failed(message)
    None if exit_code == 0 =>
      Failed("CLI exited without a completed session; see the run log")
    Some(Finished(_)) | None =>
      Failed("CLI exited with code \{exit_code}; see the run log")
  }
}
