///|
fn Entry::review_changes(self : Entry) -> Array[@mention_context.ReviewChanges] {
  @mention_context.review_changes(
    self.draft.mentions.map(mention => mention.ref_),
  )
}

///|
/// The changes control's id on `surface`. Its popup and focus are found by
/// id across the document, where both surfaces' composers can show one.
fn changes_control_id(surface : @interop.ChatSurface) -> String {
  match surface {
    Column => "composer-review-changes"
    Dock => "side-chat-review-changes"
  }
}

///|
fn Entry::changes_chip(
  locale~ : @i18n.Locale = English,
  self : Entry,
  emit : @cmd.Emit[Msg],
  disabled~ : Bool,
  surface~ : @interop.ChatSurface,
) -> @html.Html {
  @review_changes.Control::{
    id: changes_control_id(surface),
    open: self.changes_open,
    collapsed: self.changes_collapsed,
    toggle: emit(ChangesToggled),
    dismiss: emit(ChangesDismissed(restore_focus=true)),
    toggle_file: emit.map(key => ChangesFileToggled(key)),
    open_review: emit.map(selection => ChangesOpened(selection)),
    remove: if disabled {
      None
    } else {
      Some(emit.map(selections => ChangesRemoved(selections)))
    },
  }.view(locale~, self.review_changes())
}

///|
fn changes_dismiss_subscription(
  entry : Entry,
  emit : @cmd.Emit[Msg],
  surface~ : @interop.ChatSurface,
) -> @sub.Sub {
  if !entry.changes_open || entry.review_changes().is_empty() {
    return @sub.none
  }
  @review_changes.dismiss_subscription(
    changes_control_id(surface),
    emit.map(restore_focus => ChangesDismissed(restore_focus~)),
  )
}
