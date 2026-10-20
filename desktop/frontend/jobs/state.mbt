///|
pub(all) struct Owner {
  channel : @interop.ChannelId
  scope : @protocol.JobsScope
} derive(Eq)

///|
/// Who on screen reads the listing. The listing serves both readers; the
/// selected job's output is the panel's alone.
pub(all) enum Watch {
  /// Nobody: no requests and no timer.
  Unwatched
  /// A summary of the conversation's jobs, such as the conversation
  /// overview's card: the first page, at a slower pace, and no output reads.
  Summary
  /// The Jobs panel: the listing every second and the selected job's output.
  Panel
} derive(Eq)

///|
pub extend Watch with Eq::{equal, not_equal}

///|
pub(all) struct State {
  owner : Owner?
  watch : Watch
  epoch : Int32
  jobs : Array[@protocol.JobView]
  history_expanded : Bool
  selected : (String, String)?
  listing : Bool
  next_offset : Int32?
  error : String?
  warnings : Array[String]
  text : String
  cursor : Int64?
  reading : Bool
  read_serial : Int32
  reading_state : @wire.JobState?
  eof_state : @wire.JobState?
  read_budget : Int32
  catching_up : Bool
  reload_pending : Bool
  manual_read : Bool
  read_error : String?
  follow : Bool
  clipped : Bool
  control_error : String?
  stopping : Bool
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    owner: None,
    watch: Unwatched,
    epoch: 0,
    jobs: [],
    history_expanded: false,
    selected: None,
    listing: false,
    next_offset: None,
    error: None,
    warnings: [],
    text: "",
    cursor: None,
    reading: false,
    read_serial: 0,
    reading_state: None,
    eof_state: None,
    read_budget: 4,
    catching_up: false,
    reload_pending: false,
    manual_read: false,
    read_error: None,
    follow: true,
    clipped: false,
    control_error: None,
    stopping: false,
  }
}

///|
pub(all) enum Msg {
  Poll
  More
  Select(String, String)
  ToggleFollow
  ToggleHistory
  Pause
  Reload
  Stop
  Listed(Int32, Int32, Result[@protocol.JobsListReply, String])
  Read(Int32, Int32, Result[@protocol.JobReadReply, String])
  Stopped(Int32, (String, String), Result[@protocol.JobStopReply, String])
  /// Open a subagent job's own session; the shell handles it.
  OpenSession(String)
}

///|
fn selected_job(state : State) -> @protocol.JobView? {
  state.jobs
  .iter()
  .find_first(view => Some((view.job.generation, view.job.id)) == state.selected)
}

///|
fn selected_terminal(state : State) -> Bool {
  selected_job(state) is Some(view) && view.job.state.is_terminal()
}

///|
// Persisted byte counts can lag the retained file after an engine crash.
// Only an EOF from a read requested in this terminal state can finish draining.
fn output_complete(state : State, job : @wire.JobRecord) -> Bool {
  job.state.is_terminal() &&
  state.eof_state == Some(job.state) &&
  !state.catching_up &&
  state.cursor is Some(cursor) &&
  cursor >= job.output_bytes
}

///|
fn target(owner : Owner, key : (String, String)) -> @protocol.JobTarget {
  { scope: owner.scope, generation: key.0, job_id: key.1, }
}

///|
fn request_list(
  emit : @cmd.Emit[Msg],
  state : State,
  offset : Int32,
) -> (@cmd.Cmd, State) {
  guard !(state.watch is Unwatched) &&
    !state.listing &&
    state.owner is Some(owner) else {
    return (@cmd.none, state)
  }
  let cmd = @cmd.attempt(
    result => {
      emit(
        Listed(state.epoch, offset, result.map_err(@interop.bridge_error_text)),
      )
    },
    () => {
      @interop.bridge_request(owner.channel, @commands.jobs_list, {
        scope: owner.scope,
        offset,
        selected: state.selected.map(key => target(owner, key)),
      })
    },
  )
  (cmd, { ..state, listing: true, })
}

///|
fn request_read(emit : @cmd.Emit[Msg], state : State) -> (@cmd.Cmd, State) {
  guard state.watch is Panel &&
    !state.reading &&
    state.read_budget > 0 &&
    state.owner is Some(owner) &&
    state.selected is Some(key) &&
    selected_job(state) is Some(view) &&
    view.output_path is Some(_) &&
    (!output_complete(state, view.job) || state.manual_read) else {
    return (@cmd.none, state)
  }
  let serial = state.read_serial + 1
  let cmd = @cmd.attempt(
    result => {
      emit(
        Read(state.epoch, serial, result.map_err(@interop.bridge_error_text)),
      )
    },
    () => {
      @interop.bridge_request(owner.channel, @commands.jobs_read, {
        target: target(owner, key),
        offset: state.cursor,
        limit: 65536,
      })
    },
  )
  (
    cmd,
    {
      ..state,
      reading: true,
      read_serial: serial,
      reading_state: Some(view.job.state),
      read_budget: state.read_budget - 1,
    },
  )
}

///|
/// Scope and watcher changes invalidate outstanding replies, including a
/// reused session name on a different channel. Unwatched jobs have no polling.
pub fn reconcile(
  emit : @cmd.Emit[Msg],
  state : State,
  owner : Owner?,
  watch : Watch,
) -> (@cmd.Cmd, State) {
  if state.owner != owner {
    let state = { ..State::empty(), owner, watch, epoch: state.epoch + 1, }
    return request_list(emit, state, 0)
  }
  if state.watch != watch {
    let state = {
      ..state,
      watch,
      epoch: state.epoch + 1,
      listing: false,
      reading: false,
      reading_state: None,
      reload_pending: false,
      manual_read: false,
      read_budget: 4,
      read_error: if watch is Panel {
        None
      } else {
        state.read_error
      },
      stopping: false,
    }
    return request_list(emit, state, 0)
  }
  (@cmd.none, state)
}

///|
pub fn subscriptions(state : State, emit : @cmd.Emit[Msg]) -> @sub.Sub {
  guard state.owner is Some(_) else { return @sub.none }
  match state.watch {
    Panel => @sub.every(1000, emit(Poll))
    // A summary also hears the engine's job changes; the timer only keeps
    // what it shows from going stale between them.
    Summary => @sub.every(3000, emit(Poll))
    Unwatched => @sub.none
  }
}

///|
pub fn update(
  locale~ : @i18n.Locale = English,
  emit : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
) -> (@cmd.Cmd, State) {
  match msg {
    // The shell opens the session; nothing changes here.
    OpenSession(_) => (@cmd.none, state)
    Poll => {
      let state = { ..state, read_budget: 4, }
      let (list, state) = request_list(emit, state, 0)
      let (read, state) = if (state.follow || selected_terminal(state)) &&
        state.read_error is None {
        request_read(emit, state)
      } else {
        (@cmd.none, state)
      }
      (@cmd.batch([list, read]), state)
    }
    ToggleHistory =>
      (@cmd.none, { ..state, history_expanded: !state.history_expanded, })
    More =>
      match state.next_offset {
        Some(offset) => request_list(emit, state, offset)
        None => (@cmd.none, state)
      }
    Listed(epoch, offset, result) => {
      guard epoch == state.epoch else { return (@cmd.none, state) }
      match result {
        Err(error) =>
          (@cmd.none, { ..state, listing: false, error: Some(error), })
        Ok(reply) => {
          let jobs = if offset == 0 && reply.next_offset is None {
            []
          } else {
            state.jobs.copy()
          }
          for view in reply.jobs {
            upsert_job(jobs, view)
          }
          if reply.selected is Some(view) {
            upsert_job(jobs, view)
          }
          // Put the refreshed first page first while retaining loaded history.
          if offset == 0 {
            let ordered = reply.jobs.copy()
            for view in jobs {
              if !ordered.any(existing => {
                  existing.job.generation == view.job.generation &&
                  existing.job.id == view.job.id
                }) {
                ordered.push(view)
              }
            }
            jobs.clear()
            jobs.append(ordered)
          }
          let selected = match state.selected {
            Some(_) => state.selected
            None =>
              jobs
              .iter()
              .find_first(view => !view.job.state.is_terminal())
              .map(view => (view.job.generation, view.job.id))
          }
          let next_offset = if offset == 0 &&
            reply.next_offset is Some(_) &&
            state.jobs.length() > 100 {
            state.next_offset
          } else {
            reply.next_offset
          }
          let changed = selected != state.selected
          let state = {
            ..state,
            jobs,
            selected,
            listing: false,
            error: None,
            warnings: reply.errors,
            next_offset,
          }
          if changed {
            request_read(emit, state)
          } else {
            (@cmd.none, state)
          }
        }
      }
    }
    Select(generation, id) => {
      let state = {
        ..state,
        selected: Some((generation, id)),
        text: "",
        cursor: None,
        read_error: None,
        reading: false,
        read_serial: state.read_serial + 1,
        reading_state: None,
        eof_state: None,
        read_budget: 4,
        catching_up: false,
        reload_pending: false,
        manual_read: false,
        clipped: false,
        follow: true,
        control_error: None,
        stopping: false,
      }
      request_read(emit, state)
    }
    Read(epoch, serial, result) => {
      guard epoch == state.epoch && serial == state.read_serial else {
        return (@cmd.none, state)
      }
      if state.reload_pending {
        return request_read(emit, {
          ..state,
          reading: false,
          reading_state: None,
          reload_pending: false,
        })
      }
      if !state.follow && !state.manual_read && !selected_terminal(state) {
        return (@cmd.none, { ..state, reading: false, reading_state: None, })
      }
      match result {
        Err(error) =>
          (
            @cmd.none,
            {
              ..state,
              reading: false,
              reading_state: None,
              eof_state: None,
              manual_read: false,
              catching_up: false,
              read_error: Some(error),
            },
          )
        Ok(page) => {
          let combined = state.text + page.text
          // <= 262144 characters keeps even four-byte UTF-8 below 1 MiB.
          let trimmed = combined.length() > 262144
          let text = if trimmed {
            let start = combined.length() - 262144
            let start = if combined.code_units()[start].is_trailing_surrogate() {
              start + 1
            } else {
              start
            }
            combined[start:].to_owned()
          } else {
            combined
          }
          let state = {
            ..state,
            text,
            cursor: Some(page.next_offset),
            eof_state: if page.more {
              None
            } else {
              state.reading_state
            },
            reading_state: None,
            catching_up: page.more,
            reading: false,
            manual_read: false,
            read_error: None,
            clipped: state.clipped ||
            trimmed ||
            (state.cursor is None && page.start_offset > 0L),
          }
          let scroll = if state.follow { scroll_to_end() } else { @cmd.none }
          // At most four pages per refresh cycle. A partial UTF-8 suffix may report
          // more without cursor progress; always wait for the next tick then.
          if (state.follow || selected_terminal(state)) &&
            page.more &&
            page.next_offset > page.start_offset {
            let (read, state) = request_read(emit, state)
            (@cmd.batch([scroll, read]), state)
          } else {
            (scroll, state)
          }
        }
      }
    }
    Pause =>
      (
        @cmd.none,
        { ..state, follow: false, manual_read: false, reload_pending: false, },
      )
    ToggleFollow =>
      if state.follow {
        update(emit, Pause, state)
      } else {
        let (cmd, state) = request_read(emit, {
          ..state,
          follow: true,
          read_budget: 4,
          read_error: None,
        })
        (@cmd.batch([cmd, scroll_to_end()]), state)
      }
    Reload => {
      let state = {
        ..state,
        text: "",
        cursor: None,
        eof_state: None,
        clipped: false,
        catching_up: false,
        read_error: None,
        manual_read: true,
        read_budget: 4,
      }
      if state.reading {
        (@cmd.none, { ..state, reload_pending: true, })
      } else {
        request_read(emit, state)
      }
    }
    Stop => {
      guard !state.stopping &&
        state.owner is Some(owner) &&
        state.selected is Some(key) &&
        selected_job(state) is Some(view) &&
        view.controllable &&
        view.job.state is Running else {
        return (@cmd.none, state)
      }
      let cmd = @cmd.attempt(
        result => {
          emit(
            Stopped(
              state.epoch,
              key,
              result.map_err(@interop.bridge_error_text),
            ),
          )
        },
        () => {
          @interop.bridge_request(
            owner.channel,
            @commands.jobs_stop,
            target(owner, key),
          )
        },
      )
      (cmd, { ..state, stopping: true, control_error: None, })
    }
    Stopped(epoch, key, result) => {
      guard epoch == state.epoch && state.selected == Some(key) else {
        return (@cmd.none, state)
      }
      let error = match result {
        Err(error) => Some(error)
        Ok({ outcome: Stopped | AlreadyTerminal, }) => None
        Ok({ outcome: NotFound, }) =>
          Some(
            match locale {
              SimplifiedChinese =>
                "此任务已不属于当前引擎，请刷新其历史记录。"
              TraditionalChinese =>
                "此任務已不屬於當前引擎，請重新整理其歷史記錄。"
              Japanese =>
                "このジョブは現在のエンジンに属していません。履歴を更新してください。"
              English =>
                "This job no longer belongs to the live engine. Refresh its history."
              Spanish =>
                "Este trabajo ya no pertenece al motor activo. Actualiza su historial."
            },
          )
        Ok({ outcome: WrongRuntime, }) =>
          Some(
            match locale {
              SimplifiedChinese =>
                "引擎已重启，无法从新的运行环境停止此旧任务。"
              TraditionalChinese =>
                "引擎已重啟，無法從新的執行環境停止此舊任務。"
              Japanese =>
                "エンジンが再起動したため、新しい実行環境から古いジョブを停止できません。"
              English =>
                "The engine restarted; this old job cannot be stopped from the new runtime."
              Spanish =>
                "El motor se reinició; no se puede detener este trabajo anterior desde la nueva instancia."
            },
          )
      }
      let (cmd, state) = request_list(emit, { ..state, stopping: false, }, 0)
      (cmd, { ..state, control_error: error, })
    }
  }
}

///|
fn scroll_end() -> Unit {
  if @dom.document().get_element_by_id("bg-job-output").to_option() is Some(el) {
    el.set_scroll_top(el.get_scroll_height())
  }
}

///|
fn scroll_to_end() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => scroll_end(), kind=@cmd.after_render)
}

///|
pub extend Owner with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
fn upsert_job(
  jobs : Array[@protocol.JobView],
  view : @protocol.JobView,
) -> Unit {
  for index in 0..<jobs.length() {
    if jobs[index].job.generation == view.job.generation &&
      jobs[index].job.id == view.job.id {
      jobs[index] = view
      return
    }
  }
  jobs.push(view)
}
