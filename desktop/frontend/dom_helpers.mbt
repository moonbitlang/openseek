///|
fn is_submit_shortcut(event : @dom.KeyboardEvent) -> Bool {
  event.key() == "Enter" && !event.shift_key() && !event.is_composing()
}

///|
fn scroll_transcript_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => scroll_transcript(), kind=@cmd.after_render)
}

///|
fn scroll_transcript() -> Unit {
  match @dom.document().get_element_by_id("transcript").to_option() {
    Some(transcript) =>
      transcript.set_scroll_top(transcript.get_scroll_height())
    None => ()
  }
}
