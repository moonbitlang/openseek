// A conversation's changes: the pull requests and branches its agent
// attached to it, shown in the conversation overview's changes card beside
// the checkout the conversation works in. The host keeps the attached list
// beside the transcript and says only that it changed, never what it now
// holds, so the overview asks for the list whenever it comes on screen for a
// conversation, again each time the host says that conversation's list
// changed, and again when that device reconnects, since a change announced
// while the connection was down is not replayed. The user can take an
// attached item off the list; that removes the association only — it closes
// no pull request and deletes no branch.
//
// The list holds only addresses, so the title and state of each attached pull
// request are looked up on GitHub when a list answer names it. What a lookup
// found is kept by address, across conversations, and replaced only by a later
// lookup; one that fails leaves it standing. Each arrival of the overview and
// each change to the list starts a new generation, in which every pull request
// the next answer names is looked up once more.

///|
pub(all) enum Msg {
  /// The overview came on screen for this conversation.
  Opened(@interop.ConversationKey)
  /// The host saved a new list for this conversation, or may have while it
  /// was unreachable: whatever the overview holds for it is out of date.
  Changed(@interop.ConversationKey)
  /// The host answered list question number `serial`.
  Listed(serial~ : Int32, Result[@protocol.SessionArtifacts, String])
  /// The user asked to take `artifact` off the conversation's list.
  Remove(@interop.ConversationKey, @protocol.SessionArtifact)
  /// The host answered the removal of `artifact` with the list that remains.
  Removed(
    @interop.ConversationKey,
    @protocol.SessionArtifact,
    Result[@protocol.SessionArtifacts, String]
  )
  /// GitHub answered the lookup of the pull request at `url`, asked in
  /// generation `generation`. `Ok(None)` means the address is not a pull
  /// request GitHub knows how to describe.
  Summarized(
    url~ : String,
    generation~ : Int32,
    Result[@protocol.GitPullRequest?, String]
  )
}

///|
/// What the overview has of its conversation's attached list.
pub enum Phase {
  /// Nothing has been asked yet.
  Unchecked
  /// A question is out; its answer is `Listed` with the state's serial.
  Checking
  /// The host answered.
  Loaded(Array[@protocol.SessionArtifact])
  /// The host answered, and the question is out again. The last answer stays
  /// up until its replacement arrives, so the overview coming back or another
  /// client's change does not blank the list.
  Reloading(Array[@protocol.SessionArtifact])
  /// The question itself failed: the host could not be reached or could not
  /// read the saved list.
  CheckFailed(String)
} derive(Eq)

///|
pub extend Phase with Eq::{equal, not_equal}

///|
pub struct State {
  /// The conversation the phase describes; `None` before the overview first
  /// shows.
  conversation : @interop.ConversationKey?
  phase : Phase
  /// Counts list questions, so the answer to a superseded one is recognized
  /// and dropped instead of overwriting its successor's.
  serial : Int32
  /// Removals of the conversation's items the host has not answered yet;
  /// their rows stay on show without a second remove button.
  removing : Array[@protocol.SessionArtifact]
  /// Why the last removal for the conversation failed, until the next one
  /// succeeds or the overview moves to another conversation.
  remove_error : String?
  /// Each attached pull request's lookups, by address.
  lookups : Map[String, Lookup]
  /// Counts the overview's arrivals and the list's changes, the moments every
  /// attached pull request is looked up again.
  generation : Int32
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
/// One address's lookups. An address is looked up at most once per
/// generation, and a lookup is answered only while it is still its address's
/// latest.
pub struct Lookup {
  /// The generation the address was last looked up in, answered or not.
  generation : Int32
  /// What GitHub last said about it: absent until a lookup finds a pull
  /// request, cleared when one finds none, and kept when one fails.
  summary : PullRequest?
} derive(Eq)

///|
pub extend Lookup with Eq::{equal, not_equal}

///|
/// What GitHub last said about the pull request at `url`.
pub fn State::summary(self : State, url : String) -> PullRequest? {
  self.lookups.get(url).bind(lookup => lookup.summary)
}

///|
pub fn State::initial() -> State {
  {
    conversation: None,
    phase: Unchecked,
    serial: 0,
    removing: [],
    remove_error: None,
    lookups: {},
    generation: 0,
  }
}

///|
/// What there is to show for `conversation`. An answer belongs to the
/// conversation it was asked about: for any other, nothing has been asked.
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
  match msg {
    // One question at a time per conversation; another conversation's
    // supersedes it. Another client may have changed the list while the
    // overview was away, so every arrival asks, with the last answer on show.
    Opened(conversation) =>
      match state.phase_for(conversation) {
        Checking | Reloading(_) => (@cmd.none, state)
        Loaded(artifacts) =>
          ask(
            emit,
            conversation,
            state.next_generation(),
            waiting=Reloading(artifacts),
          )
        Unchecked | CheckFailed(_) =>
          ask(emit, conversation, state.next_generation(), waiting=Checking)
      }
    // A change to a list the overview is not showing changes nothing here:
    // that conversation is asked about when the overview shows it. For the
    // one it is showing, a question already out may have been answered
    // before the change, so it is superseded rather than awaited.
    Changed(conversation) => {
      guard state.conversation == Some(conversation) else {
        return (@cmd.none, state)
      }
      let waiting = match state.phase {
        Loaded(artifacts) | Reloading(artifacts) => Reloading(artifacts)
        Unchecked | Checking | CheckFailed(_) => Checking
      }
      ask(emit, conversation, state.next_generation(), waiting~)
    }
    Listed(serial~, result) => {
      guard serial == state.serial &&
        state.phase is (Checking | Reloading(_)) &&
        state.conversation is Some(conversation) else {
        return (@cmd.none, state)
      }
      match result {
        Ok(list) =>
          look_up(emit, conversation.channel, list.artifacts, {
            ..state,
            phase: Loaded(list.artifacts),
          })
        Err(message) => (@cmd.none, { ..state, phase: CheckFailed(message), })
      }
    }
    Remove(conversation, artifact) => {
      guard state.conversation == Some(conversation) &&
        !state.removing.contains(artifact) else {
        return (@cmd.none, state)
      }
      let cmd = @cmd.attempt(
        result => {
          emit(
            Removed(
              conversation,
              artifact,
              result.map_err(@interop.bridge_error_text),
            ),
          )
        },
        () => {
          @interop.bridge_request(
            conversation.channel,
            @commands.session_artifacts_remove,
            { session: conversation.session, artifact, },
          )
        },
      )
      (cmd, { ..state, removing: [..state.removing, artifact], })
    }
    // The reply is the list as the removal left it, which another client may
    // already have changed again, and an answer still out may predate the
    // removal. Neither is the last word: the list is asked for again, showing
    // what the removal left until the answer arrives.
    Removed(conversation, artifact, result) => {
      guard state.conversation == Some(conversation) else {
        return (@cmd.none, state)
      }
      let removing = state.removing.filter(item => item != artifact)
      match result {
        Ok(list) =>
          ask(
            emit,
            conversation,
            { ..state, removing, remove_error: None, },
            waiting=Reloading(list.artifacts),
          )
        Err(message) =>
          (@cmd.none, { ..state, removing, remove_error: Some(message), })
      }
    }
    // An answer a later lookup of the same address superseded is dropped. A
    // failed lookup keeps what an earlier one found.
    Summarized(url~, generation~, result) => {
      guard state.lookups.get(url) is Some(lookup) &&
        lookup.generation == generation else {
        return (@cmd.none, state)
      }
      match result {
        Ok(found) => {
          let lookups = state.lookups.copy()
          lookups[url] = {
            ..lookup,
            summary: found.bind(PullRequest::from_reply),
          }
          (@cmd.none, { ..state, lookups, })
        }
        Err(_) => (@cmd.none, state)
      }
    }
  }
}

///|
fn State::next_generation(self : State) -> State {
  { ..self, generation: self.generation + 1, }
}

///|
/// Look up each attached pull request in `artifacts` that this generation has
/// not looked up yet, through the host on `channel`.
fn look_up(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  artifacts : Array[@protocol.SessionArtifact],
  state : State,
) -> (@cmd.Cmd, State) {
  let generation = state.generation
  let lookups = state.lookups.copy()
  let commands : Array[@cmd.Cmd] = []
  for artifact in artifacts {
    guard artifact.type_ is PullRequest else { continue }
    let url = artifact.url
    // A new lookup keeps what the last one found until it answers.
    let summary = match lookups.get(url) {
      Some(lookup) if lookup.generation == generation => continue
      Some(lookup) => lookup.summary
      None => None
    }
    lookups[url] = { generation, summary, }
    commands.push(
      @cmd.attempt(
        result => {
          emit(
            Summarized(
              url~,
              generation~,
              result
              .map((reply : @protocol.GithubPullRequestSummaryReply) => {
                reply.pull_request
              })
              .map_err(@interop.bridge_error_text),
            ),
          )
        },
        () => {
          @interop.bridge_request(
            channel,
            @commands.github_pull_request_summary,
            { url, },
          )
        },
      ),
    )
  }
  (@cmd.batch(commands), { ..state, lookups, })
}

///|
/// Ask the host for `conversation`'s list, showing `waiting` until it answers.
/// A conversation the state did not describe starts with no removals of its
/// own.
fn ask(
  emit : @cmd.Emit[Msg],
  conversation : @interop.ConversationKey,
  state : State,
  waiting~ : Phase,
) -> (@cmd.Cmd, State) {
  let serial = state.serial + 1
  let cmd = @cmd.attempt(
    result => emit(Listed(serial~, result.map_err(@interop.bridge_error_text))),
    () => {
      @interop.bridge_request(
        conversation.channel,
        @commands.session_artifacts_list,
        { session: conversation.session, },
      )
    },
  )
  let state = if state.conversation == Some(conversation) {
    state
  } else {
    { ..state, removing: [], remove_error: None, }
  }
  (cmd, { ..state, conversation: Some(conversation), phase: waiting, serial, })
}

///|
/// An unrecognized state is a host speaking a vocabulary this build does not
/// know; the row then reads as the bare address rather than misreporting
/// whether the work has landed.
fn PullRequest::from_reply(reply : @protocol.GitPullRequest) -> PullRequest? {
  let state : PullRequestState = match reply.state {
    "open" if reply.draft => Draft
    "open" => Open
    "merged" => Merged
    "closed" => Closed
    _ => return None
  }
  Some({ number: reply.number, title: reply.title, state, url: reply.url, })
}
