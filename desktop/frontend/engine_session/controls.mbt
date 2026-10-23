///|
pub(all) enum CompactionPhase {
  // Nothing pending; the only phase that accepts a `/compact`.
  NotCompacting
  // Requested while idle: the op is on the wire and the host may still be
  // spawning a serve engine for it (a resumed conversation compacted before
  // its first prompt — seconds, not milliseconds). `compaction_started`
  // confirms it.
  Requested
  // Requested mid-turn: the engine queues it behind the open run, so this
  // holds the gate through the gap between the turn's end and the queued
  // compaction's start.
  Queued
  // The engine reported `compaction_started` and has not yet reported the
  // summary or a failure.
  Compacting
} derive(Eq)

///|
pub(all) struct GoalCommand {
  id : String
  request : GoalRequest
  // The durable frontier when this was sent. Its marker can only commit
  // above it, which is what separates "the record just did this" from "the
  // record already said this before I asked" — the two are indistinguishable
  // by state when a set re-asserts an unchanged goal, or a clear lands on an
  // already-goalless session.
  since : Int32
} derive(Eq)

///|
pub(all) enum GoalRequest {
  // The text this set asks to be standing.
  Setting(String)
  Clearing
} derive(Eq)

///|
fn GoalRequest::settled_by(
  self : GoalRequest,
  since : Int32,
  markers : Array[(Int32, @transcript.GoalMarker)],
) -> Bool {
  for (sequence, marker) in markers {
    if sequence > since && self.matches(marker) {
      return true
    }
  }
  false
}

///|
/// Command UI state is independent of the host transport and chatting task.
pub(all) struct State {
  goal : @transcript.GoalStanding?
  edit : GoalEdit?
  pending : GoalCommand?
  compaction : CompactionPhase
  compact_request : String?
  automatic_compacting : Bool
} derive(Eq)

///|
pub(all) enum Action {
  EditGoal
  CloseGoal
  SetGoal(String)
  ClearGoal
  Send(@wire.Command)
}

///|
/// Register a native slash command here once for both hosts. Goal opens the
/// shared editor; commands with no extra input go straight to the transport.
pub fn composer_action(action : @composer.Action) -> Action? {
  match action {
    @composer.SlashCommand(command~, ..) => slash_action(command)
    @composer.GoalEditStarted(..) => Some(EditGoal)
    @composer.GoalCancelled(..) => Some(CloseGoal)
    @composer.GoalSubmitted(draft~, ..) => Some(SetGoal(draft))
    @composer.GoalCleared(..) => Some(ClearGoal)
    _ => None
  }
}

///|
pub fn slash_action(command : String) -> Action? {
  match command {
    "goal" => Some(EditGoal)
    "compact" => Some(Send(@wire.Compact))
    _ => None
  }
}

///|
pub fn State::input(self : State) -> @composer.GoalInput {
  {
    standing: self.goal,
    draft: self.edit.map(edit => edit.draft),
    pending: self.pending.map(command => {
      match command.request {
        Setting(text) => @composer.GoalSetting(text)
        Clearing => @composer.GoalClearing
      }
    }),
  }
}

///|
pub fn State::seed(self : State) -> String {
  match self.pending {
    Some({ request: Setting(text), .. }) => text
    Some({ request: Clearing, .. }) => ""
    None => self.goal.map_or("", goal => goal.text)
  }
}

///|
/// Return an effect only when a native command must be sent. The caller
/// supplies ownership and the durable frontier, never command-specific logic.
pub fn State::act(
  self : State,
  action : Action,
  id : String,
  since : Int32,
  running~ : Bool,
) -> (State, @wire.Command?) {
  let command = match action {
    EditGoal => return ({ ..self, edit: Some({ draft: self.seed(), }), }, None)
    CloseGoal => return ({ ..self, edit: None, }, None)
    SetGoal(text) => {
      guard self.edit is Some(_) && !text.trim().is_empty() else {
        return (self, None)
      }
      @wire.GoalSet(text=text.trim().to_owned(), auto=false)
    }
    ClearGoal => @wire.GoalClear
    Send(command) => command
  }
  let next = match command {
    @wire.GoalSet(text~, ..) =>
      {
        ..self,
        edit: None,
        pending: Some({ id, request: Setting(text), since, }),
      }
    @wire.GoalClear =>
      { ..self, edit: None, pending: Some({ id, request: Clearing, since, }), }
    @wire.Compact => {
      guard self.compaction is NotCompacting else { return (self, None) }
      {
        ..self,
        compaction: if running {
          Queued
        } else {
          Requested
        },
        compact_request: Some(id),
      }
    }
    _ => self
  }
  (next, Some(command))
}

///|
/// A definite refusal restores only the goal send it answers. Uncertain
/// transport failures do not call this reducer.
fn State::reject(self : State, command : @wire.Command, id : String) -> State {
  match command {
    @wire.GoalSet(..) | @wire.GoalClear if self.pending is Some(pending) &&
      pending.id == id =>
      {
        ..self,
        pending: None,
        edit: if self.edit is Some(_) {
          self.edit
        } else {
          match pending.request {
            Setting(text) => Some({ draft: text, })
            Clearing => None
          }
        },
      }
    @wire.Compact if self.compact_request == Some(id) =>
      { ..self, compaction: NotCompacting, compact_request: None, }
    _ => self
  }
}

///|
pub fn State::host_failed(self : State) -> State {
  let next = if self.pending is Some(pending) {
    self.reject(@wire.GoalClear, pending.id)
  } else {
    self
  }
  {
    ..next,
    compaction: NotCompacting,
    compact_request: None,
    automatic_compacting: false,
  }
}

///|
pub fn State::restore_goal(
  self : State,
  goal : @transcript.GoalStanding?,
  markers : Array[(Int32, @transcript.GoalMarker)],
) -> State {
  {
    ..self,
    goal,
    pending: if self.pending is Some(pending) &&
      pending.request.settled_by(pending.since, markers) {
      None
    } else {
      self.pending
    },
  }
}

///|
/// Live native events settle command state; durable history remains the goal
/// authority for Local, which already receives per-record commits.
pub fn State::event(
  self : State,
  event : @wire.Event,
  live_goal~ : Bool = false,
) -> State {
  let self = match event {
    @wire.AutoCompactionStarted(..) => { ..self, automatic_compacting: true, }
    @wire.AutoCompactionFinished(..) | @wire.AutoCompactionFailed(..) =>
      { ..self, automatic_compacting: false, }
    _ => self
  }
  let self = match @transcript.decode_engine_event(event) {
    Some(event) => self.progress(event)
    None => self
  }
  guard live_goal else { return self }
  let marker : @transcript.GoalMarker = match event {
    @wire.GoalUpdated(goal=Some(text)) => @transcript.GoalSet(text)
    @wire.GoalUpdated(goal=None) => @transcript.GoalCleared
    @wire.GoalBlocked(reason~) => @transcript.GoalBlocked(reason)
    @wire.GoalUnblocked => @transcript.GoalUnblocked
    _ => return self
  }
  {
    ..self,
    goal: @transcript.apply_goal_marker(self.goal, marker),
    pending: if self.pending is Some(pending) && pending.request.matches(marker) {
      None
    } else {
      self.pending
    },
  }
}

///|
fn GoalRequest::matches(
  self : GoalRequest,
  marker : @transcript.GoalMarker,
) -> Bool {
  match (self, marker) {
    (Setting(text), @transcript.GoalSet(saved)) => text == saved
    (Clearing, @transcript.GoalCleared) => true
    _ => false
  }
}

///|
fn State::progress(self : State, event : @transcript.EngineEvent) -> State {
  match event {
    @transcript.CompactionStarted =>
      { ..self, compaction: Compacting, compact_request: None, }
    @transcript.CompactionFinished(_) | @transcript.CompactionFailed(_) =>
      { ..self, compaction: NotCompacting, compact_request: None, }
    _ => self
  }
}

///|
pub extend CompactionPhase with Eq::{equal, not_equal}

///|
pub extend GoalCommand with Eq::{equal, not_equal}

///|
pub extend GoalRequest with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
/// Commands can emit these events without opening a chatting turn.
pub fn is_idle_event(event : @wire.Event) -> Bool {
  event
  is (@wire.GoalUpdated(..)
  | @wire.GoalBlocked(..)
  | @wire.GoalUnblocked
  | @wire.CompactionStarted(..)
  | @wire.CompactionFinished(..)
  | @wire.AutoCompactionFinished(..)
  | @wire.CompactionFailed(..)
  | @wire.CommandError(..)
  | @wire.SessionError(..))
}

///|
/// Semantic events never become a second durable transcript. A host without
/// commit pushes reloads its native document at these boundaries.
pub fn refreshes_history(event : @wire.Event) -> Bool {
  event
  is (@wire.AssistantMessage(..)
  | @wire.ToolResult(..)
  | @wire.BackgroundNotice(..)
  | @wire.SteerApplied(..)
  | @wire.CompactionFinished(..)
  | @wire.AutoCompactionFinished(..)
  | @wire.GoalUpdated(..)
  | @wire.GoalBlocked(..)
  | @wire.GoalUnblocked)
}

///|
pub(all) struct GoalEdit {
  draft : String
} derive(Eq)

///|
pub(all) enum Delivery {
  Accepted
  Rejected
  Unknown
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    goal: None,
    edit: None,
    pending: None,
    compaction: NotCompacting,
    compact_request: None,
    automatic_compacting: false,
  }
}

///|
pub fn State::awaits(
  self : State,
  command : @wire.Command,
  id : String,
) -> Bool {
  match command {
    @wire.GoalSet(..) | @wire.GoalClear =>
      self.pending is Some(pending) && pending.id == id
    @wire.Compact => self.compact_request == Some(id)
    _ => true
  }
}

///|
/// Transport acceptance never completes a native command. Unknown delivery
/// keeps its recoverable input; a stale response cannot settle a newer send.
pub fn State::delivered(
  self : State,
  command : @wire.Command,
  id : String,
  delivery : Delivery,
) -> State {
  guard self.awaits(command, id) else { return self }
  match delivery {
    Rejected => self.reject(command, id)
    Accepted if command is @wire.Compact => { ..self, compact_request: None, }
    _ => self
  }
}

///|
pub fn State::is_compacting(self : State) -> Bool {
  self.compaction is Compacting || self.automatic_compacting
}

///|
pub fn State::is_compact_queued(self : State) -> Bool {
  self.compaction is (Queued | Requested)
}

///|
/// A new observation baseline is authoritative. On a live connection an older
/// idle snapshot cannot erase a request whose HTTP result is still unknown.
pub fn State::observe_compaction(
  self : State,
  queued~ : Bool,
  compacting~ : Bool,
  baseline~ : Bool,
) -> State {
  let pending = !baseline &&
    self.compact_request is Some(_) &&
    !queued &&
    !compacting
  {
    ..self,
    compaction: if queued {
      Queued
    } else if compacting {
      Compacting
    } else if pending {
      self.compaction
    } else {
      NotCompacting
    },
    compact_request: if pending {
      self.compact_request
    } else {
      None
    },
    automatic_compacting: queued && compacting,
  }
}

///|
pub extend GoalEdit with Eq::{equal, not_equal}

///|
pub extend Delivery with Eq::{equal, not_equal}
