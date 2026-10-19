///|
pub fn clear_input(focus~ : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id("session-search-input").to_option()
        is Some(input) &&
        input.to_html_input_element() is Some(input) {
        // Typing and clearing can share one render, leaving the old and new
        // virtual values equal while the native input still holds typed text.
        input.set_value("")
        if focus {
          input.focus()
        }
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Keep keyboard selection visible while leaving typing focus in the query.
fn reveal_result(id : @conversation.Id) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id(@conversation.open_id(id))
        .to_option()
        is Some(row) {
        row.scroll_into_view_with_options(block="nearest", inline="nearest")
      }
    },
    kind=@cmd.after_render,
  )
}
