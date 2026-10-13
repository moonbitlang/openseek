///|
const InputByteLimit : Int32 = 4 * 1024 * 1024

///|
const InputChunkLimit = 4096

///|
priv struct InputChunk {
  data : String
  binary : Bool
  bytes : Int32
} derive(Eq)

///|
priv struct InputBatch {
  token : String
  chunk : InputChunk
} derive(Eq)

///|
/// Keep transport loss distinct until the terminal state handles the reply.
pub(all) enum InputWriteFailure {
  ConnectionLost
  WriteFailed(String)
} derive(Eq)

///|
priv enum InputPause {
  Reconnecting
  Failed(String)
} derive(Eq)

///|
/// Exactly one write is in flight for each PTY. Pending input belongs to the
/// tab generation and is discarded with it, never replayed after reconnect.
priv struct InputQueue {
  pending : Array[InputChunk]
  pending_bytes : Int32
  active : InputBatch?
  failure : InputPause?
} derive(Eq)

///|
fn InputQueue::empty() -> InputQueue {
  { pending: [], pending_bytes: 0, active: None, failure: None, }
}

///|
fn pause_input(
  dispatch : @cmd.Emit[Msg],
  tab : Tab,
  message : String,
) -> (@cmd.Cmd, Tab) {
  let message = message +
    "; input is paused. Close this terminal and open a new one."
  (
    dispatch(InputFailed(message~)),
    {
      ..tab,
      input: {
        pending: [],
        pending_bytes: 0,
        active: tab.input.active,
        failure: Some(Failed(message)),
      },
    },
  )
}

///|
fn start_input(dispatch : @cmd.Emit[Msg], tab : Tab) -> (@cmd.Cmd, Tab) {
  let queue = tab.input
  guard tab.status is TabRunning &&
    tab.id is Some(id) &&
    queue.active is None &&
    queue.failure is None &&
    queue.pending.get(0) is Some(first) else {
    return (@cmd.none, tab)
  }
  let mut count = 1
  let mut bytes = first.bytes
  let pieces = [first.data]
  if !first.binary {
    // Coalesce consecutive text events once, when the previous write finishes.
    // Binary base64 records remain separate: concatenating encoded strings
    // would corrupt padding and their byte-transparent meaning.
    while count < queue.pending.length() {
      let next = queue.pending[count]
      if next.binary || next.bytes > 65536 - bytes {
        break
      }
      pieces.push(next.data)
      bytes += next.bytes
      count += 1
    }
  }
  let chunk : InputChunk = {
    data: pieces.join(""),
    binary: first.binary,
    bytes,
  }
  let batch : InputBatch = { token: @uuid.mint(), chunk, }
  let tab = {
    ..tab,
    input: {
      ..queue,
      pending: queue.pending[count:].to_owned(),
      pending_bytes: queue.pending_bytes - bytes,
      active: Some(batch),
    },
  }
  (send_input(dispatch, tab.workspace.channel(), tab.key, id, batch), tab)
}

///|
fn queue_input(
  dispatch : @cmd.Emit[Msg],
  tab : Tab,
  data : String,
  binary : Bool,
) -> (@cmd.Cmd, Tab) {
  guard tab.input.failure is None && !data.is_empty() else {
    return (@cmd.none, tab)
  }
  let bytes = @utf8.encode(data).length()
  let active_bytes = match tab.input.active {
    Some(batch) => batch.chunk.bytes
    None => 0
  }
  guard bytes <= InputByteLimit - tab.input.pending_bytes - active_bytes &&
    tab.input.pending.length() < InputChunkLimit else {
    return pause_input(
      dispatch, tab, "Terminal input buffer limit exceeded; queued input was discarded",
    )
  }
  let tab = {
    ..tab,
    input: {
      ..tab.input,
      pending: tab.input.pending + [{ data, binary, bytes, }],
      pending_bytes: tab.input.pending_bytes + bytes,
    },
  }
  start_input(dispatch, tab)
}

///|
fn finish_input(
  dispatch : @cmd.Emit[Msg],
  state : State,
  key : String,
  id : String,
  token : String,
  result : Result[Unit, InputWriteFailure],
) -> (@cmd.Cmd, State) {
  guard state.tab_by_key(key) is Some(tab) &&
    tab.id == Some(id) &&
    tab.input.active is Some(batch) &&
    batch.token == token else {
    return (@cmd.none, state)
  }
  let tab = { ..tab, input: { ..tab.input, active: None, }, }
  let (cmd, tab) = match result {
    Ok(_) => start_input(dispatch, tab)
    Err(ConnectionLost) =>
      (
        @cmd.none,
        {
          ..tab,
          input: {
            pending: [],
            pending_bytes: 0,
            active: None,
            failure: Some(Reconnecting),
          },
        },
      )
    Err(WriteFailed(message)) =>
      if tab.input.failure is Some(_) {
        (@cmd.none, tab)
      } else {
        pause_input(
          dispatch,
          tab,
          "Terminal write failed (delivery may be incomplete): " + message,
        )
      }
  }
  (cmd, state.replace_tab(tab))
}

///|
pub extend InputWriteFailure with Eq::{equal, not_equal}
