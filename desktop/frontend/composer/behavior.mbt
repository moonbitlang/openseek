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
fn[T] Menu::loading(self : Menu[T]) -> Bool {
  self.loading
}

///|
fn[T] Menu::draft_without_token(self : Menu[T]) -> String {
  self.draft_without_token
}

///|
fn[T] Menu::length(self : Menu[T]) -> Int {
  self.items.length()
}

///|
fn[T] Menu::get(self : Menu[T], index : Int) -> T? {
  self.items.get(index)
}

///|
fn[T] Menu::iter2(self : Menu[T]) -> Iter2[Int, T] {
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
fn Debounce::delayed(self : Debounce, command : (Int) -> @cmd.Cmd) -> @cmd.Cmd {
  @cmd.delay(command(self.generation), 150)
}
