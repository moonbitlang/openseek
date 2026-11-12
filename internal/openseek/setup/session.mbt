///|
/// The session this run records to: the explicit `--session` id, a generated
/// `cli-<stamp>-<salt>` id by default, or `None` under `--no-session`.
///
/// One-shot runs record by default because "what did the agent actually do?"
/// is asked after the run, when an unrecorded answer is gone for good; the
/// recording is a small JSONL directory under --session-root, and the
/// deferred first write means a run that fails before its first event still
/// leaves nothing behind. `--no-session` restores the ephemeral behavior for
/// callers that must not write to the workspace; combining it with an
/// explicit `--session` is a contradiction that command validation rejects up front
/// for every mode (this helper repeats the check as defense in depth).
///
/// The generated id carries a random salt: two timestamp-only ids collide
/// when a parallel driver launches two bare CLI runs in the same
/// millisecond under one session root, and the colliding runs would append
/// to each other's conversation (Codex review).
pub async fn resolved_session_id(
  matches : @argparse.Matches,
) -> @agent_session.SessionId? {
  let (session, no_session) = match matches {
    {
      values: {
        "session"? : Some([session, ..])
        | (Some([]) | None with session = ""),
        ..
      },
      flags: {
        "no-session"? : Some(no_session)
        | (None with no_session = false),
        ..
      },
      ..
    } => (session.trim(), no_session)
  }
  let session_id = match session {
    "" => None
    session => Some(@agent_session.SessionId("\{session}"))
  }
  match (session_id, no_session) {
    (Some(_), true) =>
      fail("--no-session contradicts --session; pick one behavior")
    (Some(id), false) => Some(id)
    (None, true) => None
    (None, false) => Some(generated_session_id())
  }
}

///|
/// A fresh `cli-<stamp>-<salt>` id for a session the caller did not name.
pub async fn generated_session_id() -> @agent_session.SessionId {
  @agent_session.SessionId::generated(
    prefix="cli",
    now_ms=@env.now().reinterpret_as_int64(),
    salt=random_salt(),
  )
}

///|
/// A short random token, or "" where none can be produced (the timestamp
/// alone then still names the session, as before).
///
/// The entropy comes from `mkdtemp` via `@fs.tmpdir`: the kernel arbitrates
/// the random suffix to be unique across concurrent processes — exactly the
/// guarantee two same-millisecond launches need — and the async runtime
/// cannot read `/dev/urandom` directly (character devices are not
/// pollable). The probe directory is removed immediately, and the suffix is
/// filtered to alphanumerics (platforms decorate it with pid and dots).
pub async fn random_salt() -> String {
  let prefix = "openseek-salt-"
  let dir = @fs.tmpdir(prefix~) catch { _ => return "" }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  // Locate the prefix instead of splitting on a path separator: Windows
  // paths use backslashes, and a `/`-only basename split would drop the
  // salt there entirely (Codex review).
  guard dir.rev_split_once(prefix) is Some((_, suffix)) else { return "" }
  let salt = StringBuilder()
  for ch in suffix {
    if ch is ('0'..<='9' | 'a'..<='z' | 'A'..<='Z') {
      salt <+ "\{ch}"
    }
  }
  salt.to_string()
}

///|
/// Resolve the configured session store relative to the workspace, rejecting an empty path.
pub fn session_root(
  matches : @argparse.Matches,
  workspace_root~ : String = ".",
) -> String raise {
  let root = match matches {
    { values: { "session-root": [root, ..], .. }, .. } => root.trim().to_owned()
    _ => fail("missing parsed argument: session-root")
  }
  guard !root.is_empty() else { fail("--session-root must not be empty") }
  @workspace_path.resolve(workspace_root, root)
}

///|
/// Load a durable session or prepare a fresh one without writing until its first append.
pub async fn load_or_new_session(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
  matches : @argparse.Matches,
  model : @deepseek.Model,
  workspace_root~ : String = ".",
) -> @agent_session.Session {
  // The prompt is built only when actually creating a fresh session: a
  // re-load must not read prompt files again.
  async fn fresh() -> @agent_session.Session {
    Session(
      id,
      system_prompt=configured_system_prompt(
        matches,
        model,
        workspace_root~,
        session_scratch_dir=store.scratch_dir(id),
      ),
    )
  }

  if store.exists(id) {
    store.load(id) catch {
      @os_error.OsError(NotFound, ..) => fresh()
      error => raise error
    }
  } else {
    fresh()
  }
}

///|
/// The model, thinking mode, and endpoint a run on a durable session uses.
/// What the session recorded (`SessionStore::model`) stands in for whichever
/// of `--model` and `--thinking` the user did not configure, by flag or by
/// environment, so resuming a session keeps the model it ran on; a
/// configured value wins and becomes the session's from this run on.
pub fn session_agent_settings(
  matches : @argparse.Matches,
  recorded : @store.SessionModel?,
) -> (@deepseek.Model, @deepseek.ThinkingMode, String?) raise {
  let (model, thinking, api_url) = @options.agent_settings(matches)
  guard recorded is Some(recorded) else { return (model, thinking, api_url) }
  (
    if matches.sources.get("model") is Some(Argv | Env) {
      model
    } else {
      recorded.model
    },
    if matches.sources.get("thinking") is Some(Argv | Env) {
      thinking
    } else {
      recorded.thinking
    },
    api_url,
  )
}

///|
/// Writes one run's appends to a durable session. The first append also
/// records the model the run uses as the session's model
/// (`SessionStore::save_model`), unless the session already recorded exactly
/// that; recording waits for an append so a run that fails before recording
/// anything still leaves nothing behind.
///
/// The transcript is the record that matters: a failed model write is
/// reported as a `session_error` and not retried, rather than failing a
/// turn whose events were already written.
struct SessionWriter {
  store : @store.SessionStore
  id : @agent_session.SessionId
  model : @store.SessionModel
  mut model_pending : Bool
}

///|
/// `recorded` is what the session's `model.json` held when the run started.
pub fn SessionWriter::SessionWriter(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
  model : @store.SessionModel,
  recorded : @store.SessionModel?,
) -> SessionWriter {
  { store, id, model, model_pending: recorded != Some(model), }
}

///|
/// Append `item` to the session's transcript, and record the model on the
/// first append.
pub async fn SessionWriter::append(
  self : SessionWriter,
  session : @agent_session.Session,
  item : @agent_session.SessionItem,
) -> @agent_session.Session {
  let next = self.store.append(session, item)
  if self.model_pending {
    self.model_pending = false
    self.store.save_model(self.id, self.model) catch {
      error =>
        @emit.emit(
          SessionError(error="failed to record the session model: \{error}"),
        )
    }
  }
  next
}
