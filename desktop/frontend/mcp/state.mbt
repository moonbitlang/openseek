// A conversation's connectors: what its engine holds of its MCP servers,
// shown in the conversation overview's connectors card. The host keeps no
// connections of its own — every conversation's engine connects its servers
// when it starts, and reports what came of it then and whenever it changes —
// so the overview asks the host for that engine's latest report and shows
// it. Asking starts nothing, so the overview asks every time it comes on
// screen for a conversation, again each time the engine of its conversation
// reports, and again when that device reconnects, since a report sent while
// the connection was down is not replayed.

///|
pub(all) enum Msg {
  /// The overview came on screen for this conversation.
  Opened(@interop.ConversationKey)
  /// The user asked again about the conversation the overview is showing.
  Refresh(@interop.ConversationKey)
  /// This conversation's engine reported to the host, or the host may have
  /// heard from it while unreachable: whatever the overview holds for it is out
  /// of date.
  Changed(@interop.ConversationKey)
  /// The host answered question number `serial`.
  Checked(serial~ : Int32, Result[@protocol.McpStatusReply, String])
}

///|
/// What the overview has to show for its conversation.
#derive(Eq)
pub enum Phase {
  /// Nothing has been asked yet.
  Unchecked
  /// A question is out; its answer is `Checked` with the state's serial.
  Checking
  /// The host answered.
  Loaded(@protocol.McpStatusReply)
  /// The host answered, and the question is out again. The last answer stays
  /// up until its replacement arrives, so the overview coming back or a change the
  /// user did not ask about does not blank the list.
  Reloading(@protocol.McpStatusReply)
  /// The question itself failed — the host could not be reached, or could
  /// not answer. Distinct from an engine that is not running and from a
  /// configuration the engine could not load, which are both answers.
  CheckFailed(String)
}

///|
pub extend Phase with Eq::{equal, not_equal}

///|
#derive(Eq)
pub struct State {
  /// The conversation the phase describes; `None` before the overview first
  /// shows.
  conversation : @interop.ConversationKey?
  phase : Phase
  /// Counts questions, so the answer to a superseded one is recognized and
  /// dropped instead of overwriting its successor's.
  serial : Int32
}

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
  conversation : @interop.ConversationKey,
) -> Phase {
  if self.conversation == Some(conversation) {
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
  let (query, next) = transition(msg, state)
  let cmd = if query is Some(query) { ask(emit, query) } else { @cmd.none }
  (cmd, next)
}

///|
#derive(Eq)
priv struct Query {
  channel : @interop.ChannelId
  payload : @protocol.McpStatusPayload
  serial : Int32
}

///|
fn transition(msg : Msg, state : State) -> (Query?, State) {
  match msg {
    // One question at a time per conversation; another conversation's
    // supersedes it. Whatever was last answered for this conversation stays
    // on show while it is asked again.
    Opened(conversation) | Refresh(conversation) =>
      match state.phase_for(conversation) {
        Checking | Reloading(_) => (None, state)
        Loaded(reply) => question(conversation, state, waiting=Reloading(reply))
        Unchecked | CheckFailed(_) =>
          question(conversation, state, waiting=Checking)
      }
    // A report from an engine the overview is not about changes nothing here:
    // its conversation is asked about when the overview shows it. For the one
    // it is about, a question already out may have been answered before this
    // report, so it is superseded rather than awaited.
    Changed(conversation) => {
      guard state.conversation == Some(conversation) else {
        return (None, state)
      }
      let waiting = match state.phase {
        Loaded(reply) | Reloading(reply) => Reloading(reply)
        Unchecked | Checking | CheckFailed(_) => Checking
      }
      question(conversation, state, waiting~)
    }
    Checked(serial~, result) => {
      guard serial == state.serial && state.phase is (Checking | Reloading(_)) else {
        return (None, state)
      }
      let phase = match result {
        Ok(reply) => Loaded(reply)
        Err(message) => CheckFailed(message)
      }
      (None, { ..state, phase, })
    }
  }
}

///|
/// Ask the host about `conversation`, showing `waiting` until it answers.
fn question(
  conversation : @interop.ConversationKey,
  state : State,
  waiting~ : Phase,
) -> (Query?, State) {
  let serial = state.serial + 1
  (
    Some({
      channel: conversation.channel,
      payload: { session: conversation.session, },
      serial,
    }),
    { conversation: Some(conversation), phase: waiting, serial, },
  )
}

///|
fn ask(emit : @cmd.Emit[Msg], query : Query) -> @cmd.Cmd {
  @cmd.attempt(
    result => {
      emit(
        Checked(serial=query.serial, result.map_err(@interop.bridge_error_text)),
      )
    },
    () => {
      @interop.bridge_request(
        query.channel,
        @commands.mcp_status,
        query.payload,
      )
    },
  )
}

///|
test "reshowing and refreshing connectors each plan one status read and preserve distinct errors" {
  let conversation : @interop.ConversationKey = {
    channel: Remote("device-a"),
    session: "session-1",
  }
  let (query, checking) = transition(Opened(conversation), State::initial())
  guard query is Some(query) else { fail("opening must request status") }
  assert_eq(query.channel, conversation.channel)
  assert_eq(query.payload.to_json(), { "session": "session-1" })
  assert_eq(query.serial, 1)
  let (none, stopped) = transition(
    Checked(serial=query.serial, Ok(Stopped)),
    checking,
  )
  assert_true(none is None)
  assert_eq(row_data(conversation, stopped), [
    Note("Not running. Servers connect with the next message."),
  ])
  let (query, reopened) = transition(Opened(conversation), stopped)
  guard query is Some(query) else {
    fail("reshowing must request fresh status")
  }
  assert_eq(query.serial, 2)
  assert_eq(query.payload.to_json(), { "session": "session-1" })
  assert_true(reopened.phase is Reloading(Stopped))
  let path = "/home/user/.openseek/mcp.json"
  let error = "mcp config error: configuration is missing an `mcpServers` object"
  let (_, invalid) = transition(
    Checked(
      serial=query.serial,
      Ok(
        Running({
          configs: [
            { path: "/runtime/host-mcp.json", state: Loaded, },
            { path, state: Failed(error), },
          ],
          servers: [],
        }),
      ),
    ),
    reopened,
  )
  assert_eq(row_data(conversation, invalid), [
    Item(
      tone="danger",
      name=path,
      note=Some("Failed"),
      detail=Some(error),
      title="\{path}\n\{error}",
    ),
  ])
  let (query, refreshing) = transition(Refresh(conversation), invalid)
  guard query is Some(query) else { fail("refresh must request status") }
  assert_eq(query.serial, 3)
  assert_eq(query.payload.to_json(), { "session": "session-1" })
  let (_, empty) = transition(
    Checked(serial=query.serial, Ok(Running({ configs: [], servers: [], }))),
    refreshing,
  )
  assert_eq(row_data(conversation, empty), [Note("No MCP servers configured.")])
  let (query, refreshing) = transition(Refresh(conversation), empty)
  guard query is Some(query) else { fail("refresh must request status again") }
  assert_eq(query.serial, 4)
  let (_, failed) = transition(
    Checked(serial=query.serial, Err("the host did not answer")),
    refreshing,
  )
  assert_eq(summary(conversation, failed), "The status could not be read")
  assert_true(failed.phase is CheckFailed("the host did not answer"))
  assert_eq(row_data(conversation, failed), [
    Item(
      tone="danger",
      name="The status could not be read",
      note=None,
      detail=Some("the host did not answer"),
      title="the host did not answer",
    ),
  ])
}

///|
test "engine reports plan one fresh status query only for the visible conversation" {
  let conversation : @interop.ConversationKey = {
    channel: Local,
    session: "session-1",
  }
  let (_, checking) = transition(Opened(conversation), State::initial())
  let (_, connecting) = transition(
    Checked(serial=checking.serial, Ok(Connecting)),
    checking,
  )
  assert_eq(summary(conversation, connecting), "Connecting…")
  let tools : Array[@wire.McpTool] = [
    { name: "mcp__memory__recall", description: "Recall a note", },
  ]
  let connected : @wire.McpServerStatus = {
    name: "memory",
    transport: Stdio,
    target: "memory-mcp",
    state: Connected(tools),
  }
  let (query, reloading) = transition(Changed(conversation), connecting)
  let (repeated_query, repeated) = transition(Changed(conversation), connecting)
  assert_true(query == repeated_query && reloading == repeated)
  guard query is Some(query) else { fail("a report must re-read host status") }
  assert_eq(query.serial, 2)
  assert_eq(query.payload.to_json(), { "session": "session-1" })
  let (_, loaded) = transition(
    Checked(
      serial=query.serial,
      Ok(Running({ configs: [], servers: [connected], })),
    ),
    reloading,
  )
  assert_eq(summary(conversation, loaded), "1 connected")
  assert_eq(row_data(conversation, loaded), [
    Item(
      tone="ok",
      name="memory",
      note=Some("1 tool"),
      detail=None,
      title="stdio · memory-mcp\nmcp__memory__recall — Recall a note",
    ),
  ])
  let (query, reloading) = transition(Changed(conversation), loaded)
  guard query is Some(query) else {
    fail("a lost server must trigger another status read")
  }
  assert_eq(query.serial, 3)
  let (_, lost) = transition(
    Checked(
      serial=query.serial,
      Ok(
        Running({
          configs: [],
          servers: [{ ..connected, state: Lost(tools), }],
        }),
      ),
    ),
    reloading,
  )
  assert_eq(summary(conversation, lost), "0 connected · 1 failed")
  assert_eq(row_data(conversation, lost), [
    Item(
      tone="warn",
      name="memory",
      note=Some(text(English, Lost)),
      detail=Some(text(English, LostReason)),
      title="stdio · memory-mcp\nmcp__memory__recall — Recall a note",
    ),
  ])
  let (query, ignored) = transition(
    Changed({ ..conversation, session: "another-session", }),
    lost,
  )
  assert_true(query is None && ignored == lost)
}
