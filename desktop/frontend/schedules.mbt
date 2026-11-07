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
#derive(Eq)
priv struct SchedulePage {
  owner : @interop.ChannelId?
  snapshot : @protocol.SchedulesReply
  form : ScheduleForm?
  busy : Bool
  sequence : Int32
  error : String?
  log : (String, String)?
}

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
    Int32,
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
    @js.Promise::from_async(() => {
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
    |> ignore
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
      management_dialog: Some(Schedules),
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
fn schedule_save_payload(
  locale~ : @i18n.Locale = English,
  form : ScheduleForm,
  run_now : Bool,
) -> Result[@protocol.ScheduleSavePayload, String] {
  schedule_form_spec(locale~, form).map(spec => { id: form.id, spec, run_now, })
}

///|
fn SchedulePage::can_run(
  self : SchedulePage,
  entry : @protocol.ScheduleEntry,
) -> Bool {
  !self.busy &&
  !entry.run_requested &&
  !self.snapshot.runs.any(run => {
    run.schedule_id == entry.id && run.status is Running
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
      match schedule_save_payload(locale=model.locale, form, run_now) {
        Err(error) =>
          (@cmd.none, { ..model, schedules: { ..page, error: Some(error), }, })
        Ok(payload) => request_schedules(dispatch, model, Save(payload))
      }
    }
    Action(id, action) =>
      request_schedules(dispatch, model, Action({ id, action, }))
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
                      (match model.locale {
                        SimplifiedChinese => "已记录的失败：\n"
                        TraditionalChinese => "已記錄的失敗：\n"
                        Japanese => "記録されたエラー：\n"
                        English => "Recorded failure:\n"
                        Spanish => "Fallo registrado:\n"
                      }) +
                      message +
                      (match model.locale {
                        SimplifiedChinese => "\n\n无法读取日志：\n"
                        TraditionalChinese => "\n\n無法讀取日誌：\n"
                        Japanese =>
                          "\n\nログを読み取れませんでした：\n"
                        English => "\n\nLog could not be read:\n"
                        Spanish => "\n\nNo se pudo leer el registro:\n"
                      }) +
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

///|
test "failed schedule saves retain every field and explicit retry preserves the saved form" {
  let dispatch = test_dispatch()
  let (_, opened) = update_schedules(dispatch, New, test_model())
  let (_, named) = update_schedules(
    dispatch,
    Field("name", "Daily work"),
    opened,
  )
  let (_, edited) = update_schedules(
    dispatch,
    Field("task", "Inspect changes"),
    named,
  )
  guard edited.schedules.form is Some(form) else {
    fail("expected schedule form")
  }
  assert_eq(form.minutes, "30")
  guard schedule_save_payload(form, false) is Ok(payload) else {
    fail("expected a valid schedule request")
  }
  assert_eq(payload.to_json(), {
    "spec": {
      "name": "Daily work",
      "task": "Inspect changes",
      "timing": { "kind": "every", "minutes": 30 },
      "timeout_minutes": 30,
    },
    "run_now": false,
  })
  let (_, saving) = update_schedules(dispatch, Save(false), edited)
  let (_, repeated) = update_schedules(dispatch, Save(false), edited)
  assert_true(saving.schedules == repeated.schedules)
  let (_, duplicate) = update_schedules(dispatch, Save(false), saving)
  assert_true(duplicate.schedules == saving.schedules)
  let (_, failed) = update_schedules(
    dispatch,
    Loaded(
      saving.focused,
      saving.schedules.sequence,
      true,
      Err("Cannot save: disk full"),
    ),
    saving,
  )
  assert_true(failed.schedules.form == Some(form))
  assert_eq(failed.schedules.error, Some("Cannot save: disk full"))
  assert_false(failed.schedules.busy)
  let (_, retry) = update_schedules(dispatch, Save(false), failed)
  assert_true(retry.schedules.busy)
  assert_true(retry.schedules.sequence > saving.schedules.sequence)
  assert_eq(retry.schedules.error, None)
  let entry : @protocol.ScheduleEntry = {
    id: "plan-1",
    spec: payload.spec,
    enabled: true,
    run_requested: false,
    notice: None,
    next_at: None,
  }
  let (_, saved) = update_schedules(
    dispatch,
    Loaded(
      retry.focused,
      retry.schedules.sequence,
      true,
      Ok({ entries: [entry], runs: [], }),
    ),
    retry,
  )
  assert_true(saved.schedules.form is None)
  let (_, reopened) = update_schedules(dispatch, Edit(entry.id), saved)
  assert_true(reopened.schedules.form == Some({ ..form, id: Some(entry.id), }))
}

///|
test "automatic schedule save and run omits workspace and keeps its queued entry unavailable for another run" {
  let dispatch = test_dispatch()
  let (_, opened) = update_schedules(dispatch, New, test_model())
  let (_, named) = update_schedules(
    dispatch,
    Field("name", "Community updates"),
    opened,
  )
  let (_, edited) = update_schedules(
    dispatch,
    Field("task", "Summarize new community posts."),
    named,
  )
  guard edited.schedules.form is Some(form) else {
    fail("expected schedule form")
  }
  assert_eq(form.workspace, None)
  guard schedule_save_payload(form, true) is Ok(payload) else {
    fail("expected a valid save-and-run request")
  }
  assert_eq(payload.to_json(), {
    "spec": {
      "name": "Community updates",
      "task": "Summarize new community posts.",
      "timing": { "kind": "every", "minutes": 30 },
      "timeout_minutes": 30,
    },
    "run_now": true,
  })
  let (_, saving) = update_schedules(dispatch, Save(true), edited)
  let entry : @protocol.ScheduleEntry = {
    id: "plan-1",
    spec: payload.spec,
    enabled: true,
    run_requested: true,
    notice: None,
    next_at: None,
  }
  let (_, saved) = update_schedules(
    dispatch,
    Loaded(
      saving.focused,
      saving.schedules.sequence,
      true,
      Ok({ entries: [entry], runs: [], }),
    ),
    saving,
  )
  assert_true(saved.schedules.form is None)
  assert_eq(saved.schedules.snapshot.entries, [entry])
  assert_false(saved.schedules.can_run(entry))
  assert_true(saved.schedules.can_run({ ..entry, run_requested: false, }))
  let (_, reopened) = update_schedules(dispatch, Edit(entry.id), saved)
  assert_true(reopened.schedules.form == Some({ ..form, id: Some(entry.id), }))
}

///|
test "a missing schedule log preserves the recorded setup failure without a page error" {
  let base = test_model()
  let run : @protocol.ScheduleRun = {
    id: "old-run",
    schedule_id: "old-plan",
    name: "Community",
    workspace: "/workspace",
    session: "old-session",
    started_at: 1,
    finished_at: Some(2),
    status: Failed("Could not prepare working directory"),
    log_path: "/missing.log",
  }
  let model = {
    ..base,
    management_dialog: Some(Schedules),
    schedules: {
      ..SchedulePage::empty(),
      owner: Some(base.focused),
      snapshot: { entries: [], runs: [run], },
    },
  }
  let msg = LogLoaded(base.focused, run.log_path, Err("No such file"))
  let (_, failed) = update_schedules(test_dispatch(), msg, model)
  let (_, repeated) = update_schedules(test_dispatch(), msg, model)
  assert_true(failed.schedules == repeated.schedules)
  assert_eq(failed.schedules.error, None)
  assert_eq(
    failed.schedules.log,
    Some(
      (
        "/missing.log", "Recorded failure:\nCould not prepare working directory\n\nLog could not be read:\nNo such file",
      ),
    ),
  )
}
