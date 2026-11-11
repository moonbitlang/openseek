///|
#derive(Eq)
priv struct ScheduleForm {
  id : String?
  name : String
  workspace : String?
  task : String
  model : String
  once : Bool
  once_at : Int64?
  minutes : String
  timeout : String
}

///|
fn ScheduleForm::empty() -> ScheduleForm {
  {
    id: None,
    name: "",
    workspace: None,
    task: "",
    model: "",
    once: false,
    once_at: None,
    minutes: "30",
    timeout: "30",
  }
}

///|
/// The schedules request a page is waiting on. A change (save or action)
/// supersedes a refresh in flight, whose stale reply the sequence then drops;
/// a refresh never preempts a change, whose reply carries the newer snapshot.
#derive(Eq)
priv enum SchedulePending {
  Refresh
  Change
}

///|
#derive(Eq)
priv struct SchedulePage {
  owner : @interop.ChannelId?
  snapshot : @protocol.SchedulesReply
  form : ScheduleForm?
  pending : SchedulePending?
  sequence : Int32
  error : String?
  log : (String, String)?
  // The schedule whose card is asking whether to delete it.
  confirm_delete : String?
}

///|
fn SchedulePage::empty() -> SchedulePage {
  {
    owner: None,
    snapshot: { entries: [], runs: [], },
    form: None,
    pending: None,
    sequence: 0,
    error: None,
    log: None,
    confirm_delete: None,
  }
}

///|
/// An edit to one field of the schedule form.
priv enum ScheduleField {
  Name(String)
  /// `None` selects the automatic working folder.
  Workspace(String?)
  Task(String)
  Model(String)
  OneTime(Bool)
  Minutes(String)
  Timeout(String)
}

///|
/// How a schedules request ended.
priv enum ScheduleOutcome {
  /// The host's schedules after a refresh or an applied change.
  Snapshot(@protocol.SchedulesReply)
  /// The host declined the change, for a reason the user can correct.
  Declined(@protocol.ScheduleRefusal)
  /// The request did not complete; the bridge's description of why.
  BridgeFailed(String)
}

///|
fn ScheduleOutcome::of_change(
  reply : @protocol.ScheduleChangeReply,
) -> ScheduleOutcome {
  match reply {
    Changed(snapshot) => Snapshot(snapshot)
    Refused(reason) => Declined(reason)
  }
}

///|
priv enum SchedulePageMsg {
  Poll
  New
  Edit(String)
  Field(ScheduleField)
  CloseForm
  Save(Bool)
  Action(String, @protocol.ScheduleAction)
  AskDelete(String)
  CancelDelete
  Loaded(@interop.ChannelId, Int32, Bool, ScheduleOutcome)
  Log(String)
  LogLoaded(@interop.ChannelId, String, Result[String, String])
  CloseLog
  Open(@protocol.ScheduleRun)
  Opened(@interop.ChannelId, String, Result[@protocol.SessionsReply, String])
}

///|
/// Whether a save or action is awaiting its reply. Only then are the page's
/// controls unavailable; a background refresh leaves them usable.
fn SchedulePage::changing(self : SchedulePage) -> Bool {
  self.pending is Some(Change)
}

///|
priv enum ScheduleRequest {
  List
  Save(@protocol.ScheduleSavePayload)
  Action(@protocol.ScheduleActionPayload)
}

///|
fn request_schedules(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  request : ScheduleRequest,
) -> (@cmd.Cmd, Model) {
  let page = model.schedules
  let pending : SchedulePending = match request {
    List => {
      guard page.pending is None else { return (@cmd.none, model) }
      Refresh
    }
    Save(_) | Action(_) => {
      guard !page.changing() else { return (@cmd.none, model) }
      Change
    }
  }
  let channel = model.focused
  let sequence = page.sequence + 1
  let cmd = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : ScheduleOutcome = try {
        match request {
          List =>
            Snapshot(
              @interop.bridge_request(
                channel,
                @commands.schedules_list,
                @protocol.EmptyPayload::NoPayload,
              ),
            )
          Save(payload) =>
            ScheduleOutcome::of_change(
              @interop.bridge_request(
                channel, @commands.schedules_save, payload,
              ),
            )
          Action(payload) =>
            ScheduleOutcome::of_change(
              @interop.bridge_request(
                channel, @commands.schedules_action, payload,
              ),
            )
        }
      } catch {
        error => BridgeFailed(@interop.bridge_error_text(error))
      }
      scheduler.add(
        dispatch(
          SchedulePage(Loaded(channel, sequence, request is Save(_), result)),
        ),
      )
    })
    |> ignore
  })
  (
    cmd,
    {
      ..model,
      schedules: {
        ..page,
        owner: Some(channel),
        pending: Some(pending),
        sequence,
        error: if request is List {
          page.error
        } else {
          None
        },
      },
    },
  )
}

///|
fn open_schedules(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  let page = if model.schedules.owner == Some(model.focused) {
    model.schedules
  } else {
    { ..SchedulePage::empty(), sequence: model.schedules.sequence, }
  }
  request_schedules(
    dispatch,
    {
      ..model,
      management_dialog: Some(Schedules),
      schedules: page,
      sidebar_open: model.sidebar_open && !model.narrow,
    },
    List,
  )
}

///|
fn schedule_client_now() -> Int64 {
  @interop.now_ms().to_int64()
}

///|
fn schedule_time(locale~ : @i18n.Locale = English, at : Int64) -> String {
  let ctor : @js.Value = @js.globalThis.get_with_string("Date")
  let date : @js.Value = ctor.new([@js.Value::cast_from(at.to_double())])
  date.apply_with_string("toLocaleString", [@js.Value::cast_from(locale.tag())])
}

///|
fn schedule_form_spec(
  locale~ : @i18n.Locale = English,
  form : ScheduleForm,
) -> Result[@protocol.ScheduleSpec, String] {
  let minutes = @string.parse_int(form.minutes) catch {
    _ => return Err(ui(locale, MinutesInteger))
  }
  let timeout = @string.parse_int(form.timeout) catch {
    _ => return Err(ui(locale, TimeoutInteger))
  }
  guard minutes >= 1 && minutes <= 525600 && timeout >= 1 && timeout <= 1440 else {
    return Err(ui(locale, ScheduleRange))
  }
  guard !form.name.trim().is_empty() && !form.task.trim().is_empty() else {
    return Err(ui(locale, ScheduleRequired))
  }
  Ok({
    name: form.name.trim().to_owned(),
    workspace: form.workspace,
    task: form.task,
    model: if form.model.trim().is_empty() {
      None
    } else {
      Some(form.model.trim().to_owned())
    },
    timing: if form.once {
      Once(
        form.once_at.unwrap_or_else(() => {
          schedule_client_now() + minutes.to_int64() * 60000
        }),
      )
    } else {
      Every(minutes)
    },
    timeout_minutes: timeout,
  })
}

///|
fn update_schedules(
  dispatch : @cmd.Emit[Msg],
  msg : SchedulePageMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let page = model.schedules
  match msg {
    Loaded(channel, sequence, saved, result) => {
      guard page.owner == Some(channel) && sequence == page.sequence else {
        return (@cmd.none, model)
      }
      let page = match result {
        Snapshot(snapshot) =>
          {
            ..page,
            snapshot,
            pending: None,
            form: if saved {
              None
            } else {
              page.form
            },
          }
        // A declined save keeps its draft so the user can correct it.
        Declined(reason) =>
          {
            ..page,
            pending: None,
            error: Some(schedule_refusal_text(model.locale, reason)),
          }
        BridgeFailed(error) => { ..page, pending: None, error: Some(error), }
      }
      (@cmd.none, { ..model, schedules: page, })
    }
    Opened(channel, session, result) => {
      guard model.management_dialog is Some(Schedules) &&
        model.focused == channel else {
        return (@cmd.none, model)
      }
      let items = match result {
        Ok(reply) => @transcript.sessions_from_reply(reply, channel)
        Err(error) =>
          return (
            @cmd.none,
            { ..model, schedules: { ..page, error: Some(error), }, },
          )
      }
      guard items.iter().find_first(item => item.id == session) is Some(item) &&
        model.device_state(channel) is Some(dev) else {
        return (
          @cmd.none,
          {
            ..model,
            schedules: {
              ..page,
              error: Some(ui(model.locale, SessionUnavailable)),
            },
          },
        )
      }
      let sessions = dev.sessions.filter(existing => existing.id != session)
      sessions.push(item)
      // The session list proves this store exists even if its directory
      // notification was missed. Adopt it and fetch its placement before
      // relying on cached worktree metadata.
      let projects = dev.projects.copy()
      if !projects.contains(item.workspace) {
        projects.push(item.workspace)
      }
      let (placement_cmd, placed) = adopt_projects(
        dispatch,
        channel,
        model.replace_device({ ..dev, sessions, }),
        projects,
      )
      let (open_cmd, opened) = update_msg(
        dispatch,
        OpenSession(channel, session),
        placed,
      )
      (
        @cmd.batch([placement_cmd, open_cmd]),
        { ..opened, management_dialog: None, },
      )
    }
    Poll => {
      guard model.wants_schedule_updates() else { return (@cmd.none, model) }
      let model = if page.owner != Some(model.focused) {
        {
          ..model,
          schedules: { ..SchedulePage::empty(), sequence: page.sequence + 1, },
        }
      } else {
        model
      }
      request_schedules(dispatch, model, List)
    }
    New =>
      (
        @cmd.none,
        {
          ..model,
          schedules: { ..page, form: Some(ScheduleForm::empty()), error: None, },
        },
      )
    Edit(id) => {
      guard page.snapshot.entries.iter().find_first(entry => entry.id == id)
        is Some(entry) else {
        return (@cmd.none, model)
      }
      let form : ScheduleForm = {
        id: Some(id),
        name: entry.spec.name,
        workspace: entry.spec.workspace,
        task: entry.spec.task,
        model: entry.spec.model.unwrap_or(""),
        once: entry.spec.timing is Once(_),
        once_at: match entry.spec.timing {
          Once(at) => Some(at)
          Every(_) => None
        },
        minutes: match entry.spec.timing {
          Every(n) => n.to_string()
          Once(at) =>
            @cmp.maximum(1L, (at - schedule_client_now() + 59999) / 60000).to_string()
        },
        timeout: entry.spec.timeout_minutes.to_string(),
      }
      (
        @cmd.none,
        { ..model, schedules: { ..page, form: Some(form), error: None, }, },
      )
    }
    CloseForm =>
      (@cmd.none, { ..model, schedules: { ..page, form: None, error: None, }, })
    Field(field) => {
      guard page.form is Some(form) else { return (@cmd.none, model) }
      let form = match field {
        Name(name) => { ..form, name, }
        Workspace(workspace) => { ..form, workspace, }
        Task(task) => { ..form, task, }
        Model(model) => { ..form, model, }
        OneTime(once) => { ..form, once, once_at: None, }
        Minutes(minutes) => { ..form, minutes, once_at: None, }
        Timeout(timeout) => { ..form, timeout, }
      }
      (@cmd.none, { ..model, schedules: { ..page, form: Some(form), }, })
    }
    Save(run_now) => {
      guard !page.changing() && page.form is Some(form) else {
        return (@cmd.none, model)
      }
      match schedule_form_spec(locale=model.locale, form) {
        Err(error) =>
          (@cmd.none, { ..model, schedules: { ..page, error: Some(error), }, })
        Ok(spec) =>
          request_schedules(
            dispatch,
            model,
            Save({ id: form.id, spec, run_now, }),
          )
      }
    }
    Action(id, action) =>
      request_schedules(
        dispatch,
        { ..model, schedules: { ..page, confirm_delete: None, }, },
        Action({ id, action, }),
      )
    AskDelete(id) =>
      (
        @cmd.none,
        { ..model, schedules: { ..page, confirm_delete: Some(id), }, },
      )
    CancelDelete =>
      (@cmd.none, { ..model, schedules: { ..page, confirm_delete: None, }, })
    CloseLog => (@cmd.none, { ..model, schedules: { ..page, log: None, }, })
    Log(path) => {
      let channel = model.focused
      (
        @cmd.custom_cmd(scheduler => {
          @js.Promise::from_async(() => {
            let result : Result[String, String] = try {
              let reply = @interop.bridge_request(
                channel,
                @commands.fs_read_file,
                { path, root: None, max_bytes: None, },
              )
              match reply {
                Content(content~, ..) => Ok(content)
                Oversized => Err(ui(model.locale, LogTooLarge))
                _ => Err(ui(model.locale, LogNotText))
              }
            } catch {
              error => Err(@interop.bridge_error_text(error))
            }
            scheduler.add(
              dispatch(SchedulePage(LogLoaded(channel, path, result))),
            )
          })
          |> ignore
        }),
        model,
      )
    }
    LogLoaded(channel, path, result) => {
      guard model.management_dialog is Some(Schedules) &&
        model.focused == channel else {
        return (@cmd.none, model)
      }
      match result {
        Ok(text) =>
          (
            @cmd.none,
            { ..model, schedules: { ..page, log: Some((path, text)), }, },
          )
        Err(error) =>
          if page.snapshot.runs.iter().find_first(run => run.log_path == path)
            is Some(run) &&
            run.status is Failed(message) {
            (
              @cmd.none,
              {
                ..model,
                schedules: {
                  ..page,
                  error: None,
                  log: Some(
                    (
                      path,
                      (
                        $|\{ui(model.locale, RecordedFailure)}
                        $|\{message}
                        $|
                        $|\{ui(model.locale, LogUnreadable)}
                        $|\{error}
                      ),
                    ),
                  ),
                },
              },
            )
          } else {
            (
              @cmd.none,
              { ..model, schedules: { ..page, error: Some(error), }, },
            )
          }
      }
    }
    Open(run) => {
      let channel = model.focused
      (
        @cmd.custom_cmd(scheduler => {
          @js.Promise::from_async(() => {
            let result : Result[@protocol.SessionsReply, String] = Ok(
              @interop.bridge_request(
                channel,
                @commands.session_list,
                @protocol.EmptyPayload::NoPayload,
              ),
            ) catch {
              error => Err(@interop.bridge_error_text(error))
            }
            scheduler.add(
              dispatch(SchedulePage(Opened(channel, run.session, result))),
            )
          })
          |> ignore
        }),
        model,
      )
    }
  }
}

///|
// A scheduled CLI accepts no follow-up input. Until its host snapshot arrives,
// a scheduled session remains read-only rather than exposing a dead composer.
fn Model::scheduled_session_read_only(
  self : Model,
  conv : Conversation,
) -> Bool {
  if self.schedules.owner == Some(conv.device) {
    if self.schedules.snapshot.runs
      .iter()
      .find_first(run => run.session == conv.session_id)
      is Some(run) {
      return run.status is Running
    }
  }
  conv.session_id.has_prefix("scheduled-")
}

///|
fn Model::wants_schedule_updates(self : Model) -> Bool {
  self.management_dialog is Some(Schedules) ||
  (
    self.screen is Chat &&
    self.active_conversation() is Some(conv) &&
    self.scheduled_session_read_only(conv)
  )
}
