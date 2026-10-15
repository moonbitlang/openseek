///|
/// Keep keyboard selection visible while leaving typing focus in the query.
fn reveal_result(index : Int32) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id("session-search-result-\{index}")
        .to_option()
        is Some(row) {
        row.scroll_into_view_with_options(block="nearest", inline="nearest")
      }
    },
    kind=@cmd.after_render,
  )
}
