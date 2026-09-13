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
        () => self.run_cli(entry.spec, run, sink?, on_workspaces?),
      ) {
      Some(0) => scheduled_session_result(run)
      Some(code) => Failed("CLI exited with code \{code}; see the run log")
      None => TimedOut
    }
  } catch {
    error if @async.is_being_cancelled() => raise error
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
      let runs = state.runs.map(item => {
        if item.id == run.id {
          { ..item, status, finished_at: Some(schedule_now()), }
        } else {
          item
        }
      })
      self.commit({ ..state, runs, })
      if on_finished is Some(notify) {
        notify(run)
      }
    }) catch {
      error if @async.is_being_cancelled() => raise error
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
async fn Schedules::run_cli(
  self : Schedules,
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
  let record_guard = self.manager.begin_record_op(run.session)
  defer self.manager.end_record_op(run.session, record_guard)
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
  // File redirection keeps memory bounded and never leaves a pipe undrained.
  let output = @process.redirect_to_file(
    run.log_path,
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let (input, writer) = @process.write_to_process()
  writer.close()
  @async.with_task_group(group => {
    if self.stopped.contains(run.id) {
      return 0
    }
    let follower = match sink {
      Some(sink) =>
        ensure_follower(sink~, group~, manager=self.manager, config~)
      None => None
    }
    defer (if follower is Some(follower) {
      discard_follower_startup(self.manager, follower)
    })
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
      cancel_handler=@process.graceful_cancel(timeout=1000),
    )
    self.processes[run.id] = process
    if self.stopped.contains(run.id) {
      process.cancel()
    }
    let code = process.wait()
    if follower is Some(follower) {
      stop_follower_instance(self.manager, follower, writer_exited=true)
    }
    code
  })
}

///|
// CLI exit zero alone is not task success: max-steps and setup failures also
// settle a durable turn. Reuse that terminal record instead of parsing logs.
async fn scheduled_session_result(
  run : @protocol.ScheduleRun,
) -> @protocol.ScheduleRunStatus {
  guard @pathx.Absolute::from_uri_path(run.workspace) is Some(workspace) else {
    raise EngineError("Invalid scheduled workspace")
  }
  let store = @store.SessionStore(@workspaces.store_root(workspace).to_string())
  let session = store.load(SessionId(run.session))
  let mut result : @protocol.ScheduleRunStatus? = None
  for event in session.events() {
    if event.item() is Terminal(terminal) {
      result = Some(
        match terminal {
          Finished(_) => Succeeded
          Failed(message) | Aborted(message) => Failed(message)
          Interrupted(_) => Interrupted
        },
      )
    }
  }
  match result {
    Some(result) => result
    None => Failed("CLI exited without a completed session; see the run log")
  }
}
