// Generic composer input behavior. Callers keep their result rows and send
// protocol; this package owns trigger parsing, menu selection, and delayed
// request generations.

///|
/// A live completion token at the end of a composer draft. The marker is `/`
/// for a whole-draft command or one of the inline markers accepted by the
/// caller. The text before an inline token is retained verbatim for insertion.
struct Trigger {
  marker : String
  query : String
  draft_without_token : String
} derive(Eq)

///|
/// Parse the completion grammar used by conversation composers. Slash
/// commands only apply to the whole draft; `$`, `#`, and `@` are trailing,
/// whitespace-delimited tokens, with the caller selecting which inline
/// markers it supports.
pub fn Trigger::parse(text : String, inline_markers~ : String) -> Trigger? {
  if text =~ (re"^/", after=query) && query =~ re"^[^[:space:]]*$" {
    return Some({
      marker: "/",
      query: query.to_owned(),
      draft_without_token: "",
    })
  }
  // The trailing anchor skips earlier marker text. The boundary check rejects
  // a marker embedded in a word without consuming whitespace that accepting
  // the completion must preserve.
  guard text =~ (re"[$#@][^[:space:]]*$" as token, before=draft) &&
    (draft.is_empty() || draft =~ re"[[:space:]]$") &&
    token =~ (re"^[$#@]" as marker, after=query) else {
    return None
  }
  let marker = "\{marker}"
  guard inline_markers.contains(marker) else { return None }
  Some({
    marker,
    query: query.to_owned(),
    draft_without_token: draft.to_owned(),
  })
}

///|
pub fn Trigger::marker(self : Trigger) -> String {
  self.marker
}

///|
pub fn Trigger::query(self : Trigger) -> String {
  self.query
}

///|
pub fn Trigger::draft_without_token(self : Trigger) -> String {
  self.draft_without_token
}

///|
/// Whether a result row survives this trigger's query. A blank query keeps
/// every row; otherwise any supplied field may contain it, case-insensitively.
pub fn Trigger::matches(self : Trigger, fields : Array[String]) -> Bool {
  let query = self.query.trim().to_owned().to_lower()
  if query.is_empty() {
    return true
  }
  for field in fields {
    if field.to_lower().contains(query) {
      return true
    }
  }
  false
}

///|
/// The application-independent part of an open completion menu. The caller keeps
/// its result type and provider kind; this value owns selection, loading, and
/// the exact draft prefix restored when a row is accepted.
struct Menu[T] {
  items : Array[T]
  selected : Int
  loading : Bool
  draft_without_token : String
} derive(Eq)

///|
pub fn[T] Menu::Menu(
  items : Array[T],
  loading~ : Bool,
  draft_without_token~ : String,
) -> Menu[T] {
  { items, selected: 0, loading, draft_without_token }
}

///|
pub fn[T] Menu::selected(self : Menu[T]) -> Int {
  self.selected
}

///|
pub fn[T] Menu::loading(self : Menu[T]) -> Bool {
  self.loading
}

///|
pub fn[T] Menu::draft_without_token(self : Menu[T]) -> String {
  self.draft_without_token
}

///|
pub fn[T] Menu::length(self : Menu[T]) -> Int {
  self.items.length()
}

///|
pub fn[T] Menu::get(self : Menu[T], index : Int) -> T? {
  self.items.get(index)
}

///|
pub fn[T] Menu::iter2(self : Menu[T]) -> Iter2[Int, T] {
  self.items.iter2()
}

///|
/// Move the highlighted row by `delta`, wrapping at both ends. An empty menu
/// is left unchanged so keyboard navigation remains safe while loading.
pub fn[T] Menu::shifted(self : Menu[T], delta : Int) -> Menu[T] {
  let count = self.items.length()
  if count == 0 {
    return self
  }
  { ..self, selected: (self.selected + delta + count) % count }
}

///|
pub fn[T] Menu::current(self : Menu[T]) -> T? {
  self.items.get(self.selected)
}

///|
/// One provider-specific completion menu. Applications choose the provider
/// kind and row payload, while this package owns the common menu shape.
struct ControllerCompletion[Kind, Item] {
  kind : Kind
  menu : Menu[Item]
} derive(Eq)

///|
pub fn[Kind, Item] ControllerCompletion::ControllerCompletion(
  kind : Kind,
  menu : Menu[Item],
) -> ControllerCompletion[Kind, Item] {
  { kind, menu }
}

///|
pub fn[Kind, Item] ControllerCompletion::kind(
  self : ControllerCompletion[Kind, Item],
) -> Kind {
  self.kind
}

///|
pub fn[Kind, Item] ControllerCompletion::menu(
  self : ControllerCompletion[Kind, Item],
) -> Menu[Item] {
  self.menu
}

///|
/// Monotonic identity for delayed composer lookups. Every draft change spends
/// one generation, so a delayed request and its eventual reply can both be
/// rejected after any newer keystroke, provider switch, or trigger dismissal.
struct Debounce {
  generation : Int
} derive(Eq)

///|
pub fn Debounce::Debounce(generation? : Int = 0) -> Debounce {
  { generation, }
}

///|
pub fn Debounce::advanced(self : Debounce) -> Debounce {
  { generation: self.generation + 1 }
}

///|
pub fn Debounce::generation(self : Debounce) -> Int {
  self.generation
}

///|
pub fn Debounce::accepts(self : Debounce, generation : Int) -> Bool {
  self.generation == generation
}

///|
/// Delay a lookup using the same 150 ms pause as workspace symbol Quick Open.
/// The caller carries this generation in its own message and checks `accepts`
/// before starting work or adopting a reply.
pub fn Debounce::delayed(
  self : Debounce,
  command : (Int) -> @cmd.Cmd,
) -> @cmd.Cmd {
  @cmd.delay(command(self.generation), 150)
}

///|
/// Transient completion state shared by every conversation composer. Each
/// composer owns a separate value, but OpenSeek and Codex now use these exact
/// transitions for draft edits, keyboard selection, dismissal, and delayed
/// request fencing instead of maintaining parallel state machines.
struct CompletionState[Kind, Item] {
  current : ControllerCompletion[Kind, Item]?
  debounce : Debounce
} derive(Eq)

///|
pub fn[Kind, Item] CompletionState::CompletionState() -> CompletionState[
  Kind,
  Item,
] {
  { current: None, debounce: Debounce() }
}

///|
pub fn[Kind, Item] CompletionState::current(
  self : CompletionState[Kind, Item],
) -> ControllerCompletion[Kind, Item]? {
  self.current
}

///|
/// Refresh provider rows only while a menu is still open. A file-index or
/// symbol reply may arrive after Escape; it may update its provider cache, but
/// it must not recreate the dismissed popup from the unchanged draft token.
pub fn[Kind, Item] CompletionState::refreshed(
  self : CompletionState[Kind, Item],
  current : ControllerCompletion[Kind, Item]?,
) -> CompletionState[Kind, Item] {
  if self.current is Some(_) {
    { ..self, current, }
  } else {
    self
  }
}

///|
/// Record a draft change. Every edit spends one generation even when it closes
/// the menu, so delayed work scheduled by an older draft becomes stale.
pub fn[Kind, Item] CompletionState::changed(
  self : CompletionState[Kind, Item],
  current : ControllerCompletion[Kind, Item]?,
) -> CompletionState[Kind, Item] {
  { current, debounce: self.debounce.advanced() }
}

///|
/// Close the menu and invalidate its delayed work. This is used for Escape,
/// submission, and conversation changes where the draft itself may survive.
pub fn[Kind, Item] CompletionState::dismissed(
  self : CompletionState[Kind, Item],
) -> CompletionState[Kind, Item] {
  { current: None, debounce: self.debounce.advanced() }
}

///|
/// Move the common keyboard selection while leaving a closed menu unchanged.
pub fn[Kind, Item] CompletionState::shifted(
  self : CompletionState[Kind, Item],
  delta : Int,
) -> CompletionState[Kind, Item] {
  match self.current {
    Some(current) =>
      {
        ..self,
        current: Some(
          ControllerCompletion(current.kind, current.menu.shifted(delta)),
        ),
      }
    None => self
  }
}

///|
pub fn[Kind, Item] CompletionState::generation(
  self : CompletionState[Kind, Item],
) -> Int {
  self.debounce.generation()
}

///|
pub fn[Kind, Item] CompletionState::accepts(
  self : CompletionState[Kind, Item],
  generation : Int,
) -> Bool {
  self.debounce.accepts(generation)
}

///|
pub fn[Kind, Item] CompletionState::delayed(
  self : CompletionState[Kind, Item],
  command : (Int) -> @cmd.Cmd,
) -> @cmd.Cmd {
  self.debounce.delayed(command)
}

///|
/// Input events owned by every conversation composer. Backend packages wrap
/// this one message type instead of maintaining parallel draft, completion,
/// mention, and submit variants.
pub(all) enum ControllerMsg {
  ControllerDraftChanged(String)
  ControllerCompletionMoved(Int)
  ControllerCompletionAccepted
  ControllerCompletionPicked(Int)
  ControllerCompletionDismissed
  ControllerMentionRemoved(Int)
  ControllerSubmitRequested
} derive(Eq)

///|
/// A request that the common input controller cannot interpret by itself.
/// Completion rows retain backend-specific payloads, and submission still has
/// to pass the selected conversation's own protocol and readiness gates.
pub(all) enum ControllerRequest[Kind, Item] {
  NoControllerRequest
  DraftUpdated(String)
  CompletionChosen(kind~ : Kind, item~ : Item, draft_without_token~ : String)
  SubmissionRequested
} derive(Eq)

///|
/// The complete editable input state consumed by the shared controller. The
/// owning application may store these fields together or project them from a
/// conversation record; either way, every input event crosses this one pure
/// transition before backend-specific work begins.
struct Controller[Kind, Item, Mention] {
  draft : String
  mentions : Array[Mention]
  completion : CompletionState[Kind, Item]
} derive(Eq)

///|
pub fn[Kind, Item, Mention] Controller::Controller(
  draft : String,
  mentions : Array[Mention],
  completion : CompletionState[Kind, Item],
) -> Controller[Kind, Item, Mention] {
  { draft, mentions, completion }
}

///|
pub fn[Kind, Item, Mention] Controller::draft(
  self : Controller[Kind, Item, Mention],
) -> String {
  self.draft
}

///|
pub fn[Kind, Item, Mention] Controller::mentions(
  self : Controller[Kind, Item, Mention],
) -> Array[Mention] {
  self.mentions
}

///|
pub fn[Kind, Item, Mention] Controller::completion(
  self : Controller[Kind, Item, Mention],
) -> CompletionState[Kind, Item] {
  self.completion
}

///|
/// Apply the backend-independent half of a composer event. `complete` is a
/// pure projection over the owning backend's current catalogs; it is supplied
/// per update and is never retained in model state. Selected rows and submits
/// return typed requests for the owner to interpret through its own protocol.
/// A draft update carries the accepted text so providers never recover it by
/// inspecting the original input message again; the controller retains the
/// matching debounce generation in its completion state.
pub fn[Kind, Item, Mention] Controller::update(
  self : Controller[Kind, Item, Mention],
  msg : ControllerMsg,
  complete : (String) -> ControllerCompletion[Kind, Item]?,
) -> (Controller[Kind, Item, Mention], ControllerRequest[Kind, Item]) {
  match msg {
    ControllerDraftChanged(value) => {
      let completion = self.completion.changed(complete(value))
      ({ ..self, draft: value, completion }, DraftUpdated(value))
    }
    ControllerCompletionMoved(delta) =>
      (
        { ..self, completion: self.completion.shifted(delta) },
        NoControllerRequest,
      )
    ControllerCompletionDismissed =>
      ({ ..self, completion: self.completion.dismissed() }, NoControllerRequest)
    ControllerMentionRemoved(index) => {
      guard self.mentions.get(index) is Some(_) else {
        return (self, NoControllerRequest)
      }
      let mentions = self.mentions.copy()
      ignore(mentions.remove(index))
      ({ ..self, mentions, }, NoControllerRequest)
    }
    ControllerCompletionAccepted => self.choose_completion(None)
    ControllerCompletionPicked(index) => self.choose_completion(Some(index))
    ControllerSubmitRequested => (self, SubmissionRequested)
  }
}

///|
/// Run the common transition, write its controller fields back to the parent
/// state, and only then interpret the resulting request. Keeping this order in
/// the composer package prevents OpenSeek and Codex from growing separate
/// upper-level controller paths. The callbacks are used only for this update;
/// they are never retained in application state.
pub fn[Parent, Result, Kind, Item, Mention] Controller::update_parent(
  self : Controller[Kind, Item, Mention],
  parent : Parent,
  msg : ControllerMsg,
  complete : (String) -> ControllerCompletion[Kind, Item]?,
  put : (Parent, Controller[Kind, Item, Mention]) -> Parent,
  respond : (Parent, ControllerRequest[Kind, Item]) -> Result,
) -> Result {
  let (controller, request) = self.update(msg, complete)
  respond(put(parent, controller), request)
}

///|
/// Resolve keyboard or pointer acceptance against the same live menu. The
/// menu closes here exactly once; the owner receives the provider kind, row,
/// and preserved draft prefix needed to turn the choice into a command or
/// mention without re-reading transient controller state.
fn[Kind, Item, Mention] Controller::choose_completion(
  self : Controller[Kind, Item, Mention],
  index : Int?,
) -> (Controller[Kind, Item, Mention], ControllerRequest[Kind, Item]) {
  guard self.completion.current() is Some(current) else {
    return (
      { ..self, completion: self.completion.dismissed() },
      NoControllerRequest,
    )
  }
  let item = match index {
    Some(index) => current.menu().get(index)
    None => current.menu().current()
  }
  guard item is Some(item) else {
    return (
      { ..self, completion: self.completion.dismissed() },
      NoControllerRequest,
    )
  }
  (
    { ..self, completion: self.completion.dismissed() },
    CompletionChosen(
      kind=current.kind(),
      item~,
      draft_without_token=current.menu().draft_without_token(),
    ),
  )
}
