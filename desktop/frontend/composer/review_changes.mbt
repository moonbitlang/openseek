///|
fn Entry::review_changes(self : Entry) -> Array[@mention_context.ReviewChanges] {
  @mention_context.review_changes(
    self.draft.mentions.map(mention => mention.ref_),
  )
}

///|
fn Entry::changes_chip(
  locale? : @i18n.Locale = English,
  self : Entry,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @review_changes.Control::{
    id: "composer-review-changes",
    open: self.changes_open,
    collapsed: self.changes_collapsed,
    toggle: emit(ChangesToggled),
    dismiss: emit(ChangesDismissed(restore_focus=true)),
    toggle_file: emit.map(key => ChangesFileToggled(key)),
    open_review: emit.map(selection => ChangesOpened(selection)),
    remove: Some(emit.map(selections => ChangesRemoved(selections))),
  }.view(locale~, self.review_changes())
}

///|
fn changes_dismiss_subscription(
  entry : Entry,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  if !entry.changes_open || entry.review_changes().is_empty() {
    return @sub.none
  }
  @review_changes.dismiss_subscription(
    "composer-review-changes",
    emit.map(restore_focus => ChangesDismissed(restore_focus~)),
  )
}
