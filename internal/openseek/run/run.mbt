///|
/// `openseek run [TASK…]` — a headless one-shot agent run: the answer on
/// stdout, minimal progress on stderr.
pub async fn run_task_command(matches : @argparse.Matches) -> Unit {
  let result_file = result_file_path(matches)
  // A result left by an earlier run must not pass for this one's: if this
  // run dies before writing its own, the path is simply absent.
  if result_file is Some(path) {
    @fs.remove(path) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => ()
      error => raise error
    }
  }
  // The single run's turn, as it is recorded. Read after the output scope
  // (success or failure) to say how the run ended.
  let turn = TurnRecord::{ session: None, started_after: 0, latest: None, }
  // Why the run failed. It is set inside the output scope but acted on only
  // after it: an error escaping the body would cancel the drain before the
  // run's last events reached stdout and stderr.
  let mut failure : Error? = None
  @execution.with_text_output(() => {
    try {
      // --no-session contradicts an explicit --session; reject up front.
      @options.reject_session_contradiction(matches)
      // So is `--approval ask` on a command that reads no commands. Rejected
      // HERE, before a session directory exists and before the model is
      // contacted: resolving it at the first turn instead left a run that
      // announced `session_started` and only then refused, which is a failure
      // the caller pays for in artifacts on disk. Read once, and passed to the
      // turn rather than parsed again.
      let approval_policy = @execution.approval_policy(
        matches,
        interactive=false,
      )
      // Validated before the workspace is created, like the options above.
      let review_deadline_ms = @options.review_deadline_ms(matches)
      let workspace_root = @setup.prepare_workspace_root(
        matches,
        log_created=true,
      )
      let (model, thinking, api_url) = @options.agent_settings(matches)
      guard model.api_key(matches.values) is Some(api_key) else {
        fail("an API key is required for \{model}: pass --api-key")
      }
      let (retry_attempts, retry_backoff_ms) = @options.retry_overrides(matches)
      let max_steps = @options.max_steps(matches)
      let task = @options.task_text(matches)
      match @setup.resolved_session_id(matches) {
        None => {
          let system_prompt_text = @setup.configured_system_prompt(
            matches,
            model,
            workspace_root~,
          )
          let session = @agent_session.Session(
            SessionId("one-shot"),
            system_prompt=system_prompt_text,
          )
          turn.started_after = session.last_sequence()
          // Ephemeral parent: children keep their transcripts in-memory too —
          // a sibling session of a parent that never persisted would dangle.
          run_task_turn(
            matches,
            session,
            append_item=(session, item) => turn.record(session.append(item)),
            api_key~,
            model~,
            task~,
            max_steps?,
            thinking~,
            api_url?,
            retry_attempts?,
            retry_backoff_ms?,
            workspace_root~,
            review_deadline_ms~,
            approval_policy~,
          )
        }
        Some(id) => {
          // Name the recording up front so a user scanning the event stream knows
          // where to find this run later (`sessions show`, the viz server, or
          // resuming by id).
          @emit.emit(
            SessionStarted(
              session=id.value(),
              session_root=@setup.session_root(matches, workspace_root~),
              workspace_root=Some(workspace_root),
            ),
          )
          let store = @store.SessionStore(
            @setup.session_root(matches, workspace_root~),
          )
          let session = @setup.load_or_new_session(
            store,
            id,
            matches,
            model,
            workspace_root~,
          )
          turn.session = Some(id.value())
          turn.started_after = session.last_sequence()
          run_task_turn(
            matches,
            session,
            append_item=(session, item) => {
              turn.record(store.append(session, item))
            },
            job_log_dir=store.job_logs_dir(id),
            api_key~,
            model~,
            task~,
            max_steps?,
            thinking~,
            api_url?,
            retry_attempts?,
            retry_backoff_ms?,
            workspace_root~,
            review_deadline_ms~,
            approval_policy~,
            child_session=ChildSession(
              root=store.root(),
              parent=id.value(),
              first_free=@setup.first_free_child_ordinal(store, id.value()),
            ),
          )
        }
      }
    } catch {
      error => failure = Some(error)
    }
  }) catch {
    // Writing stdout or stderr failed. The run cannot report through them,
    // but it still owes its result file.
    error => if failure is None { failure = Some(error) }
  }
  let status = turn.status(failure~)
  if result_file is Some(path) {
    write_result_file(path, {
      status,
      session: turn.session,
      usage: turn.usage(),
    })
  }
  if failure is Some(error) {
    raise error
  }
  if incomplete_reason(status) is Some(reason) {
    fail("run did not complete: \{reason}")
  }
}

///|
/// The `--result-file` path, when one was given.
fn result_file_path(matches : @argparse.Matches) -> String? raise {
  match matches.values.get("result-file") {
    Some([path, ..]) if path.is_blank() => fail("--result-file needs a path")
    Some([path, ..]) => Some(path)
    _ => None
  }
}

///|
/// Write `result` to `path` so that a reader sees either no file or the whole
/// result: into a new, uniquely named sibling first, then renamed over `path`.
/// The sibling is created exclusively, so a run never writes into another
/// run's temporary file.
async fn write_result_file(
  path : String,
  result : @openseek_protocol.RunResult,
) -> Unit {
  let tmp_path = "\{path}.\{@setup.random_salt()}.tmp"
  @fs.write_file(
    tmp_path,
    result.to_json().stringify() + "\n",
    create_mode=CreateNew,
  )
  errdefer (@fs.remove(tmp_path) catch { _ => () })
  @fs.rename(tmp_path, path, replace=true)
}

///|
/// Why a run that ended with `status` did not complete its task, or `None`
/// when it did.
fn incomplete_reason(status : @openseek_protocol.RunStatus) -> String? {
  match status {
    Completed(_) => None
    ContextYield(_) =>
      Some(
        "the turn reached the model's context window and was checkpointed before the task was done",
      )
    MaxStepsExhausted => Some(@agent_session.MaxStepsExhaustedMessage)
    Aborted(reason~) => Some("aborted: \{reason}")
    Interrupted(reason~) => Some("interrupted: \{reason}")
    Failed(reason~) => Some(reason)
  }
}
