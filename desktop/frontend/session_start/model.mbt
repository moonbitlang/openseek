///|
pub(all) enum Action {
  ToggleOptions
  ToggleModel
  ToggleWorkspace
  CloseMenu
  ModelChanged(String)
  WorkspaceChanged(String)
  Decide(String)
  Open
} derive(Eq, Debug)

///|
pub(all) struct Source {
  session : String
  workspace : String?
  archived : Bool
} derive(Eq, Debug)

///|
pub(all) enum Msg {
  Snapshot(@protocol.SessionStartsSnapshot)
  LoadFailed(source~ : Source, error~ : String)
  Retry(Source)
  CloseMenus
  Interact(source~ : Source, request~ : String, Action)
  Failed(source~ : Source, request~ : String, attempt~ : Int32, error~ : String)
} derive(Eq, Debug)

///|
priv enum Editor {
  Closed
  Options
  ModelMenu
  WorkspaceMenu
} derive(Eq, Debug)

///|
priv enum Delivery {
  Idle
  Sending(String, attempt~ : Int32)
  Failed(String)
} derive(Eq, Debug)

///|
pub struct Card {
  source : Source
  proposal : @protocol.SessionStartProposal
  priv editor : Editor
  priv delivery : Delivery
  priv model : String?
  priv workspace_mode : String
  priv attempts : Int32
} derive(Eq, Debug)

///|
priv struct SourceState {
  source : Source
  generation : Int32
  cards : Array[Card]
  load_error : String?
} derive(Eq, Debug)

///|
struct Model {
  sources : Array[SourceState]
} derive(Eq, Debug)

///|
pub fn Model::Model() -> Model {
  { sources: [], }
}

///|
pub fn Model::cards(self : Model, source : Source) -> Array[Card] {
  self.sources
  .iter()
  .find_first(entry => entry.source == source)
  .map(source => source.cards)
  .unwrap_or([])
}

///|
pub fn Card::request_id(self : Card) -> String {
  self.proposal.request_id
}

///|
pub fn Card::is_visible(self : Card) -> Bool {
  self.proposal.status != "dismissed" && self.proposal.status != "here"
}

///|
fn Model::snapshot(
  self : Model,
  snapshot : @protocol.SessionStartsSnapshot,
) -> Model {
  let source : Source = {
    session: snapshot.session,
    workspace: snapshot.workspace,
    archived: snapshot.archived.unwrap_or(false),
  }
  let previous = self.sources.iter().find_first(entry => entry.source == source)
  if previous is Some(source) && source.generation > snapshot.generation {
    return self
  }
  let cards = snapshot.proposals.map(proposal => {
    let existing = previous.bind(source => {
      source.cards
      .iter()
      .find_first(card => card.proposal.request_id == proposal.request_id)
    })
    if existing is Some(card) &&
      (proposal.status == "pending" || proposal.status == "failed") &&
      card.proposal == proposal {
      card
    } else {
      {
        source,
        proposal,
        editor: Closed,
        delivery: Idle,
        model: proposal.model,
        workspace_mode: proposal.workspace_mode,
        attempts: existing.map(card => card.attempts).unwrap_or(0),
      }
    }
  })
  let entry : SourceState = {
    source,
    generation: snapshot.generation,
    cards,
    load_error: None,
  }
  let sources = self.sources.filter(value => value.source != source)
  { sources: [..sources, entry], }
}

///|
pub fn Model::update(
  self : Model,
  msg : Msg,
  channel : @interop.ChannelId,
  emit : @cmd.Emit[Msg],
  here_options? : @protocol.SessionStartHereOptions,
) -> (@cmd.Cmd, Model) {
  if msg is Snapshot(snapshot) {
    return (@cmd.none, self.snapshot(snapshot))
  }
  if msg is Retry(source) {
    return (fetch(channel, source, emit), self)
  }
  if msg is CloseMenus {
    return (@cmd.none, self.close_menus())
  }
  if msg is LoadFailed(source~, error~) {
    let previous = self.sources
      .iter()
      .find_first(entry => entry.source == source)
    let entry : SourceState = if previous is Some(entry) {
      { ..entry, load_error: Some(error), }
    } else {
      { source, generation: -1, cards: [], load_error: Some(error), }
    }
    return (
      @cmd.none,
      {
        sources: [..self.sources.filter(value => value.source != source), entry],
      },
    )
  }
  let commands : Array[@cmd.Cmd] = []
  let sources = self.sources.map(source => {
    let cards = source.cards.map(card => {
      match msg {
        Interact(source~, request~, action) if source == card.source &&
          request == card.proposal.request_id => {
          guard !(card.delivery is Sending(_, ..)) &&
            (
              card.proposal.status == "pending" ||
              card.proposal.status == "failed"
            ) else {
            return card
          }
          match action {
            ToggleOptions =>
              {
                ..card,
                editor: if card.editor is Closed {
                  Options
                } else {
                  Closed
                },
              }
            ToggleModel =>
              {
                ..card,
                editor: if card.editor is ModelMenu {
                  Options
                } else {
                  ModelMenu
                },
              }
            ToggleWorkspace =>
              {
                ..card,
                editor: if card.editor is WorkspaceMenu {
                  Options
                } else {
                  WorkspaceMenu
                },
              }
            CloseMenu =>
              {
                ..card,
                editor: if card.editor is Closed {
                  Closed
                } else {
                  Options
                },
              }
            ModelChanged(value) =>
              {
                ..card,
                model: if value.is_empty() {
                  None
                } else {
                  Some(value)
                },
                editor: Options,
              }
            WorkspaceChanged(value) =>
              if value == "local" || value == "worktree" {
                { ..card, workspace_mode: value, editor: Options, }
              } else {
                card
              }
            Decide(action) => {
              guard action == "start" || action == "here" || action == "dismiss" else {
                return card
              }
              if card.proposal.target_session is Some(target) &&
                action != "dismiss" &&
                (action == "here") != (target == card.source.session) {
                return card
              }
              guard !card.source.archived else { return card }
              commands.push(
                decide(
                  channel,
                  card.decision(action, here_options?),
                  card.source,
                  emit,
                  attempt=card.attempts + 1,
                ),
              )
              {
                ..card,
                delivery: Sending(action, attempt=card.attempts + 1),
                attempts: card.attempts + 1,
                editor: Closed,
              }
            }
            Open => card
          }
        }
        Failed(source~, request~, attempt~, error~) if source == card.source &&
          request == card.proposal.request_id &&
          card.delivery is Sending(_, attempt=current) &&
          current == attempt &&
          (
            card.proposal.status == "pending" ||
            card.proposal.status == "failed"
          ) => { ..card, delivery: Failed(error), }
        Interact(ToggleModel | ToggleWorkspace, ..) => card.close_menu()
        _ => card
      }
    })
    { ..source, cards, }
  })
  (@cmd.batch(commands), { sources, })
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Card with Eq::{equal, not_equal}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with Debug::{to_repr}

///|
pub extend Msg with Eq::{equal, not_equal}

///|
pub extend Msg with Debug::{to_repr}

///|
pub extend Model with Debug::{to_repr}

///|
pub extend Card with Debug::{to_repr}

///|
pub fn Model::load_error(self : Model, source : Source) -> String? {
  self.sources
  .iter()
  .find_first(entry => entry.source == source)
  .bind(source => source.load_error)
}

///|
fn Card::close_menu(self : Card) -> Card {
  if self.editor is ModelMenu || self.editor is WorkspaceMenu {
    { ..self, editor: Options, }
  } else {
    self
  }
}

///|
pub fn Model::close_menus(self : Model) -> Model {
  {
    sources: self.sources.map(source => {
      ..source,
      cards: source.cards.map(card => card.close_menu()),
    }),
  }
}

///|
pub fn Model::reconnecting(self : Model) -> Model {
  {
    sources: self.sources.map(source => {
      ..source,
      cards: source.cards.map(card => {
        ..card.close_menu(),
        // Completions from the old connection are fenced at the root. The
        // fresh durable snapshot settles accepted work; an unchanged pending
        // proposal must remain actionable if its decision never reached Host.
        delivery: Idle,
      }),
    }),
  }
}

///|
pub fn Model::has_open_menu(self : Model) -> Bool {
  self.sources.any(source => {
    source.cards.any(card => {
      card.editor is ModelMenu || card.editor is WorkspaceMenu
    })
  })
}

///|
fn Card::decision(
  self : Card,
  action : String,
  here_options? : @protocol.SessionStartHereOptions,
) -> @protocol.SessionStartDecision {
  {
    session: self.source.session,
    workspace: self.source.workspace,
    request_id: self.proposal.request_id,
    action,
    // An explicit null clears an agent-suggested model back to the project's
    // default. Here and Dismiss do not adopt any new-session options.
    model: if action == "start" {
      Some(self.model)
    } else {
      None
    },
    workspace_mode: if action == "start" {
      Some(self.workspace_mode)
    } else {
      None
    },
    here: if action == "here" {
      here_options
    } else {
      None
    },
  }
}

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend Source with Debug::{to_repr}
