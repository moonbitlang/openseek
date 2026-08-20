///|
/// One item the UI can offer in the input-completion menu.
struct CompletionItem {
  label : String
  insert_text : String
  description : String
} derive(Eq, Debug)

///|
/// Build a completion item. `label` is shown in the menu, `insert_text` is the
/// semantic value submitted when the item is accepted.
pub fn CompletionItem::new(
  label~ : String,
  insert_text? : String,
  description? : String = "",
) -> CompletionItem {
  { label, insert_text: insert_text.unwrap_or(label), description }
}

///|
/// User-visible label shown in the completion menu.
pub fn CompletionItem::label(self : CompletionItem) -> String {
  self.label
}

///|
/// Text submitted or inserted when this item is accepted.
pub fn CompletionItem::insert_text(self : CompletionItem) -> String {
  self.insert_text
}

///|
/// User-visible description shown to the right of the label.
pub fn CompletionItem::description(self : CompletionItem) -> String {
  self.description
}

///|
/// Completion items whose label or inserted text starts with `filter`,
/// case-insensitively, with exact matches ranked ahead of broader prefix
/// matches (original order preserved within each group).
///
/// The exact-first ordering matters because Enter accepts the first item: when
/// candidates can be prefixes of one another and are not sorted by relevance —
/// `/resume`, whose session ids are arbitrary and listed by recency — typing a
/// complete id like `abc` must resume `abc`, not a longer, more recent `abcd`
/// that also prefix-matches and happens to sort first.
pub fn completion_item_matches(
  items : Array[CompletionItem],
  filter : String,
) -> Array[CompletionItem] {
  let lowered = filter.to_lower()
  let exact : Array[CompletionItem] = []
  let prefix : Array[CompletionItem] = []
  for item in items {
    let label = item.label.to_lower()
    let insert = item.insert_text.to_lower()
    if label == lowered || insert == lowered {
      exact.push(item)
    } else if label.has_prefix(lowered) || insert.has_prefix(lowered) {
      prefix.push(item)
    }
  }
  exact + prefix
}

///|
/// Open or closed state for the input-completion menu.
struct Model {
  open : Bool
  items : Array[CompletionItem]
  selected : Int
} derive(Eq, Debug)

///|
/// A closed completion menu.
pub fn Model::closed() -> Model {
  { open: false, items: [], selected: 0 }
}

///|
/// An open completion menu. `selected` is clamped to the available item range.
pub fn Model::open(
  items~ : Array[CompletionItem],
  selected? : Int = 0,
) -> Model {
  let selected = if items.length() == 0 {
    0
  } else {
    selected.clamp(min=0, max=items.length() - 1)
  }
  { open: true, items: items.copy(), selected }
}

///|
/// Whether the completion menu is open.
pub fn Model::is_open(self : Model) -> Bool {
  self.open
}

///|
/// Completion items currently shown in the menu.
pub fn Model::items(self : Model) -> Array[CompletionItem] {
  self.items.copy()
}

///|
/// Selected item index, clamped when the model is built.
pub fn Model::selected(self : Model) -> Int {
  self.selected
}

///|
#deprecated
pub extend CompletionItem with Debug::{to_repr}

///|
pub extend CompletionItem with Eq::{equal, not_equal}

///|
#deprecated
pub extend Model with Debug::{to_repr}

///|
pub extend Model with Eq::{equal, not_equal}
