///|
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
} derive(Eq)

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
priv struct SchedulePage {
  owner : @interop.ChannelId?
  snapshot : @protocol.SchedulesReply
  form : ScheduleForm?
  busy : Bool
  sequence : Int
  error : String?
  log : (String, String)?
} derive(Eq)

///|
fn SchedulePage::empty() -> SchedulePage {
  {
    owner: None,
    snapshot: { entries: [], runs: [], },
    form: None,
    busy: false,
    sequence: 0,
    error: None,
    log: None,
  }
}

///|
priv enum SchedulePageMsg {
  Poll
  New
  Edit(String)
  Field(String, String)
  CloseForm
  Save(Bool)
  Action(String, String)
  Loaded(
    @interop.ChannelId,
    Int,
    Bool,
    Result[@protocol.SchedulesReply, String]
  )
  Log(String)
  LogLoaded(@interop.ChannelId, String, Result[String, String])
  CloseLog
  Open(@protocol.ScheduleRun)
  Opened(@interop.ChannelId, String, Result[@protocol.SessionsReply, String])
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
  guard !page.busy else { return (@cmd.none, model) }
  let channel = model.focused
  let sequence = page.sequence + 1
  let cmd = @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let result : Result[@protocol.SchedulesReply, String] = try {
        let reply = match request {
          List =>
            @interop.bridge_request(
              channel,
              @commands.schedules_list,
              @protocol.EmptyPayload::NoPayload,
            )
          Save(payload) =>
            @interop.bridge_request(channel, @commands.schedules_save, payload)
          Action(payload) =>
            @interop.bridge_request(
              channel, @commands.schedules_action, payload,
            )
        }
        Ok(reply)
      } catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(
        dispatch(
          SchedulePage(Loaded(channel, sequence, request is Save(_), result)),
        ),
      )
    })
  })
  (
    cmd,
    {
      ..model,
      schedules: {
        ..page,
        owner: Some(channel),
        busy: true,
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
      screen: Schedules,
      schedules: page,
      sidebar_open: model.sidebar_open && !model.narrow,
    },
    List,
  )
}

///|
fn schedule_client_now() -> Int64 {
  let date : @js.Value = @js.globalThis.get_with_string("Date")
  let now : Double = date.apply_with_string("now", ([] : FixedArray[@js.Value]))
  now.to_int64()
}

///|
fn schedule_time(at : Int64) -> String {
  let ctor : @js.Value = @js.globalThis.get_with_string("Date")
  let date : @js.Value = ctor.new([@js.Value::cast_from(at.to_double())])
  date.apply_with_string("toLocaleString", ([] : FixedArray[@js.Value]))
}

///|
fn schedule_form_spec(
  form : ScheduleForm,
) -> Result[@protocol.ScheduleSpec, String] {
  let minutes = @string.parse_int(form.minutes) catch {
    _ => return Err("Enter a whole number of minutes")
  }
  let timeout = @string.parse_int(form.timeout) catch {
    _ => return Err("Enter a whole number for the timeout")
  }
  guard minutes >= 1 && minutes <= 525600 && timeout >= 1 && timeout <= 1440 else {
    return Err("Interval: 1–525600 minutes. Timeout: 1–1440 minutes.")
  }
  guard !form.name.trim().is_empty() && !form.task.trim().is_empty() else {
    return Err("Enter a name and task")
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
        Ok(snapshot) =>
          {
            ..page,
            snapshot,
            busy: false,
            form: if saved {
              None
            } else {
              page.form
            },
          }
        Err(error) => { ..page, busy: false, error: Some(error), }
      }
      (@cmd.none, { ..model, schedules: page, })
    }
    Opened(channel, session, result) => {
      guard model.screen is Schedules && model.focused == channel else {
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
              error: Some(
                "The session record is not available yet, or it has been archived. Check the run status and log.",
              ),
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
      (@cmd.batch([placement_cmd, open_cmd]), opened)
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
    Field(field, value) => {
      guard page.form is Some(form) else { return (@cmd.none, model) }
      let form = match field {
        "name" => { ..form, name: value, }
        "workspace" =>
          {
            ..form,
            workspace: if value == "auto" {
              None
            } else {
              Some(value)
            },
          }
        "task" => { ..form, task: value, }
        "model" => { ..form, model: value, }
        "timing" => { ..form, once: value == "once", once_at: None, }
        "minutes" => { ..form, minutes: value, once_at: None, }
        "timeout" => { ..form, timeout: value, }
        _ => form
      }
      (@cmd.none, { ..model, schedules: { ..page, form: Some(form), }, })
    }
    Save(run_now) => {
      guard !page.busy && page.form is Some(form) else {
        return (@cmd.none, model)
      }
      match schedule_form_spec(form) {
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
      request_schedules(dispatch, model, Action({ id, action, }))
    CloseLog => (@cmd.none, { ..model, schedules: { ..page, log: None, }, })
    Log(path) => {
      let channel = model.focused
      (
        @cmd.custom_cmd(scheduler => {
          @js.async_run(() => {
            let result : Result[String, String] = try {
              let reply = @interop.bridge_request(
                channel,
                @commands.fs_read_file,
                { path, root: None, },
              )
              match reply {
                Content(content~, ..) => Ok(content)
                Oversized =>
                  Err(
                    "This log is too large to display. Open its saved path with an external viewer.",
                  )
                _ => Err("This log is not a text file")
              }
            } catch {
              error => Err(@interop.bridge_error_text(error))
            }
            scheduler.add(
              dispatch(SchedulePage(LogLoaded(channel, path, result))),
            )
          })
        }),
        model,
      )
    }
    LogLoaded(channel, path, result) => {
      guard model.screen is Schedules && model.focused == channel else {
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
                      "Recorded failure:\n" +
                      message +
                      "\n\nLog could not be read:\n" +
                      error,
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
          @js.async_run(() => {
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
  self.screen is Schedules ||
  (
    self.screen is Chat &&
    self.active_conversation() is Some(conv) &&
    self.scheduled_session_read_only(conv)
  )
}
