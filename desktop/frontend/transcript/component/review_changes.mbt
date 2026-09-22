///|
/// Each keyed message owns its disclosure state. Streaming another row never
/// resets it or applies its state to a different message's saved snapshot.
priv struct MessageChanges {
  open : Bool
  collapsed : Array[String]
} derive(Eq)

///|
priv enum MessageChangesMsg {
  Toggle
  Dismiss(restore_focus~ : Bool)
  ToggleFile(String)
  OpenReview(@mention_context.ReviewChanges)
}

///|
fn Block::changes_id(self : Block) -> String? {
  if self.content is Item(item~, anchor=Some(anchor), ..) &&
    item.kind is User(content~) &&
    @mention_context.parse(content.text()) is Some(parsed) &&
    parsed.mentions.any(mention => mention is @mention_context.ReviewChanges(_)) {
    Some(anchor + "-changes")
  } else {
    None
  }
}

///|
fn message_changes_state(
  block : @rabbita.Val[Block],
  actions : Actions,
) -> (@rabbita.Val[MessageChanges], @cmd.Emit[MessageChangesMsg]) {
  @rabbita.create_state_with_input(
    input=block,
    init=(_, _) => ({ open: false, collapsed: [], }, @cmd.none),
    update=(state, block, msg, _) => {
      guard block.changes_id() is Some(id) else { return (state, @cmd.none) }
      match msg {
        Toggle => {
          let open = !state.open
          (
            { ..state, open, },
            if open {
              @review_changes.show_popup(id)
            } else {
              @cmd.none
            },
          )
        }
        Dismiss(restore_focus~) =>
          (
            { ..state, open: false, },
            if restore_focus {
              @review_changes.focus_trigger(id)
            } else {
              @cmd.none
            },
          )
        ToggleFile(key) => {
          let collapsed = if state.collapsed.contains(key) {
            state.collapsed.filter(existing => existing != key)
          } else {
            state.collapsed + [key]
          }
          ({ ..state, collapsed, }, @cmd.none)
        }
        OpenReview(selection) =>
          ({ ..state, open: false, }, (actions.open_review_changes)(selection))
      }
    },
    subscriptions=(state, block, emit) => {
      if state.open && block.changes_id() is Some(id) {
        @review_changes.dismiss_subscription(
          id,
          emit.map(restore_focus => Dismiss(restore_focus~)),
        )
      } else {
        @sub.none
      }
    },
  )
}

///|
fn MessageChanges::control(
  self : MessageChanges,
  block : Block,
  emit : @cmd.Emit[MessageChangesMsg],
) -> @review_changes.Control? {
  block
  .changes_id()
  .map(id => {
    id,
    open: self.open,
    collapsed: self.collapsed,
    toggle: emit(Toggle),
    dismiss: emit(Dismiss(restore_focus=true)),
    toggle_file: emit.map(key => ToggleFile(key)),
    open_review: emit.map(selection => OpenReview(selection)),
    remove: None,
  })
}
