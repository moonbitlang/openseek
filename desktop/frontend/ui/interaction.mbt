///|
#cfg(target="js")
fn ui_focus_id(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, _ => {
    if @dom.document().get_element_by_id(id).to_option() is Some(element) &&
      element.to_html_element() is Some(html_element) {
      html_element.focus()
    }
  })
}

///|
#cfg(not(target="js"))
fn ui_focus_id(id : String) -> @cmd.Cmd {
  ignore(id)
  @cmd.none
}
