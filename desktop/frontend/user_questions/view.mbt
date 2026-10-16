///|
pub fn Model::view(
  self : Model,
  session : String,
  locale : @i18n.Locale,
  connected : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  // Keep one stable sibling slot and show one request at a time.
  let children = if self.cards
    .iter()
    .find_first(card => card.request.session == session)
    is Some(card) {
    [
      card.draft.view(
        card.questions(),
        card.request.id,
        locale,
        disabled=!connected,
        emit.map(action => Interact(request=card.request.id, action)),
      ),
    ]
  } else {
    []
  }
  @html.div(class="user-question-region", children)
}
