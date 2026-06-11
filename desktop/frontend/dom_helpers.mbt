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

///|
/// Track whether the transcript is scrolled to its bottom, feeding changes
/// back as `TranscriptPinned` so update can decide when streaming output may
/// auto-scroll.
fn watch_transcript_scroll(dispatch : @cmd.Dispatch[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_watch_transcript_scroll(pinned => {
      scheduler.add(dispatch(TranscriptPinned(pinned)))
    })
  })
}

///|
/// Scroll events do not bubble, but they do run the capture phase, so one
/// document-level listener keeps working even if the transcript element is
/// replaced by a render. The callback fires only when the at-bottom state
/// changes; the slack absorbs fractional scroll positions.
extern "js" fn js_watch_transcript_scroll(on_change : (Bool) -> Unit) =
  #| (onChange) => {
  #|   if (globalThis.__openseekDesktopTranscriptScrollWatchInstalled) return;
  #|   globalThis.__openseekDesktopTranscriptScrollWatchInstalled = true;
  #|   let pinned = true;
  #|   document.addEventListener("scroll", (event) => {
  #|     const target = event.target;
  #|     if (!target || target.id !== "transcript") return;
  #|     const atBottom =
  #|       target.scrollHeight - target.scrollTop - target.clientHeight <= 4;
  #|     if (atBottom !== pinned) {
  #|       pinned = atBottom;
  #|       onChange(atBottom);
  #|     }
  #|   }, true);
  #| }
