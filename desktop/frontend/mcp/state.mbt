// The Settings page's MCP panel: what the current conversation's engine holds
// of its MCP servers. The host keeps no connections of its own — every
// conversation's engine connects its servers when it starts, and reports
// what came of it then and whenever it changes — so the panel asks the host
// for that engine's latest report and shows it. Asking starts nothing, so
// the panel asks every time Settings opens, and again each time the engine
// of the conversation on show reports.

///|
pub(all) enum Msg {
  /// The Settings page opened with this conversation current, or with none.
  Opened(@interop.ConversationKey?)
  /// The user asked again about the conversation the panel is showing.
  Refresh(@interop.ConversationKey)
  /// This conversation's engine reported to the host: whatever the panel
  /// holds for it is out of date.
  Changed(@interop.ConversationKey)
  /// The host answered question number `serial`.
  Checked(serial~ : Int32, Result[@protocol.McpStatusReply, String])
}

///|
/// What the panel has to show for its conversation.
pub enum Phase {
  /// Nothing has been asked yet.
  Unchecked
  /// A question is out; its answer is `Checked` with the state's serial.
  Checking
  /// The host answered.
  Loaded(@protocol.McpStatusReply)
  /// The host answered, the engine has reported since, and the question is
  /// out again. The last answer stays up until its replacement arrives, so a
  /// change the user did not ask about does not blank the list.
  Reloading(@protocol.McpStatusReply)
  /// The question itself failed — the host could not be reached, or could
  /// not answer. Distinct from an engine that is not running and from a
  /// configuration the engine could not load, which are both answers.
  CheckFailed(String)
} derive(Eq)

///|
pub extend Phase with Eq::{equal, not_equal}

///|
pub struct State {
  /// The conversation the phase describes; `None` when Settings last opened
  /// with no conversation current, and before it first opens.
  conversation : @interop.ConversationKey?
  phase : Phase
  /// Counts questions, so the answer to a superseded one is recognized and
  /// dropped instead of overwriting its successor's.
  serial : Int32
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
pub fn State::initial() -> State {
  { conversation: None, phase: Unchecked, serial: 0, }
}

///|
/// What there is to show for `conversation`. An answer belongs to the
/// conversation whose engine gave it: for any other, nothing has been asked.
pub fn State::phase_for(
  self : State,
  conversation : @interop.ConversationKey?,
) -> Phase {
  if conversation is Some(_) && self.conversation == conversation {
    self.phase
  } else {
    Unchecked
  }
}

///|
pub fn update(
  emit : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
) -> (@cmd.Cmd, State) {
  match msg {
    Opened(Some(conversation)) | Refresh(conversation) =>
      // One question at a time per conversation; another conversation's
      // supersedes it.
      if state.conversation == Some(conversation) &&
        state.phase is (Checking | Reloading(_)) {
        (@cmd.none, state)
      } else {
        ask(emit, conversation, state, waiting=Checking)
      }
    // A report from an engine the panel is not showing changes nothing here:
    // its conversation is asked about when Settings opens on it. For the one
    // on show, a question already out may have been answered before this
    // report, so it is superseded rather than awaited.
    Changed(conversation) => {
      guard state.conversation == Some(conversation) else {
        return (@cmd.none, state)
      }
      let waiting = match state.phase {
        Loaded(reply) | Reloading(reply) => Reloading(reply)
        Unchecked | Checking | CheckFailed(_) => Checking
      }
      ask(emit, conversation, state, waiting~)
    }
    // No conversation, no engine to ask. Advancing the serial retires any
    // question still out for the conversation that was current before.
    Opened(None) =>
      (
        @cmd.none,
        { conversation: None, phase: Unchecked, serial: state.serial + 1, },
      )
    Checked(serial~, result) => {
      guard serial == state.serial && state.phase is (Checking | Reloading(_)) else {
        return (@cmd.none, state)
      }
      let phase = match result {
        Ok(reply) => Loaded(reply)
        Err(message) => CheckFailed(message)
      }
      (@cmd.none, { ..state, phase, })
    }
  }
}

///|
/// Ask the host about `conversation`, showing `waiting` until it answers.
fn ask(
  emit : @cmd.Emit[Msg],
  conversation : @interop.ConversationKey,
  state : State,
  waiting~ : Phase,
) -> (@cmd.Cmd, State) {
  let serial = state.serial + 1
  let cmd = @cmd.attempt(
    result => emit(Checked(serial~, result.map_err(@interop.bridge_error_text))),
    () => {
      @interop.bridge_request(conversation.channel, @commands.mcp_status, {
        session: conversation.session,
      })
    },
  )
  (cmd, { conversation: Some(conversation), phase: waiting, serial, })
}
