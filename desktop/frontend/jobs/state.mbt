///|
pub(all) struct Owner {
  channel : @interop.ChannelId
  scope : @protocol.JobsScope
} derive(Eq)

///|
pub(all) struct State {
  owner : Owner?
  active : Bool
  epoch : Int
  jobs : Array[@protocol.JobView]
  selected : (String, String)?
  listing : Bool
  next_offset : Int?
  error : String?
  warnings : Array[String]
  text : String
  cursor : Int64?
  reading : Bool
  read_serial : Int
  read_budget : Int
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
    active: false,
    epoch: 0,
    jobs: [],
    selected: None,
    listing: false,
    next_offset: None,
    error: None,
    warnings: [],
    text: "",
    cursor: None,
    reading: false,
    read_serial: 0,
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
  Pause
  Reload
  Stop
  Listed(Int, Int, Result[@protocol.JobsListReply, String])
  Read(Int, Int, Result[@protocol.JobReadReply, String])
  Stopped(Int, (String, String), Result[@protocol.JobStopReply, String])
}

///|
fn selected_job(state : State) -> @protocol.JobView? {
  state.jobs
  .iter()
  .find_first(view => Some((view.job.generation, view.job.id)) == state.selected)
}

///|
fn target(owner : Owner, key : (String, String)) -> @protocol.JobTarget {
  { scope: owner.scope, generation: key.0, job_id: key.1, }
}

///|
fn request_list(
  emit : @cmd.Emit[Msg],
  state : State,
  offset : Int,
) -> (@cmd.Cmd, State) {
  guard state.active && !state.listing && state.owner is Some(owner) else {
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
  guard state.active &&
    !state.reading &&
    state.read_budget > 0 &&
    state.owner is Some(owner) &&
    state.selected is Some(key) &&
    selected_job(state) is Some(view) &&
    view.output_path is Some(_) else {
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
      read_budget: state.read_budget - 1,
    },
  )
}

///|
/// Scope and visibility changes invalidate outstanding replies, including a
/// reused session name on a different channel. Hidden panels have no polling.
pub fn reconcile(
  emit : @cmd.Emit[Msg],
  state : State,
  owner : Owner?,
  active : Bool,
) -> (@cmd.Cmd, State) {
  if state.owner != owner {
    let state = { ..State::empty(), owner, active, epoch: state.epoch + 1, }
    return request_list(emit, state, 0)
  }
  if state.active != active {
    let state = {
      ..state,
      active,
      epoch: state.epoch + 1,
      listing: false,
      reading: false,
      reload_pending: false,
      manual_read: false,
      read_budget: 4,
      read_error: if active {
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
  if state.active && state.owner is Some(_) {
    @sub.every(1000, emit(Poll))
  } else {
    @sub.none
  }
}

///|
pub fn update(
  emit : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
) -> (@cmd.Cmd, State) {
  match msg {
    Poll => {
      let state = { ..state, read_budget: 4, }
      let (list, state) = request_list(emit, state, 0)
      let (read, state) = if state.follow && state.read_error is None {
        request_read(emit, state)
      } else {
        (@cmd.none, state)
      }
      (@cmd.batch([list, read]), state)
    }
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
            None => jobs.get(0).map(view => (view.job.generation, view.job.id))
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
          reload_pending: false,
        })
      }
      if !state.follow && !state.manual_read {
        return (@cmd.none, { ..state, reading: false, })
      }
      match result {
        Err(error) =>
          (
            @cmd.none,
            {
              ..state,
              reading: false,
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
          if state.follow && page.more && page.next_offset > page.start_offset {
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
        view.controllable else {
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
            "This job no longer belongs to the live engine. Refresh its history.",
          )
        Ok({ outcome: WrongRuntime, }) =>
          Some(
            "The engine restarted; this old job cannot be stopped from the new runtime.",
          )
      }
      let (cmd, state) = request_list(emit, { ..state, stopping: false, }, 0)
      (cmd, { ..state, control_error: error, })
    }
  }
}

///|
extern "js" fn scroll_end() -> Unit =
  #| () => { const el = document.getElementById("bg-job-output"); if (el) el.scrollTop = el.scrollHeight; }

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
