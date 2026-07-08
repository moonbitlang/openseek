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
let transcript_scroll_watched : Ref[Bool] = Ref(false)

///|
/// Track whether the transcript is scrolled to its bottom, feeding changes
/// back as `TranscriptPinned` so update can decide when streaming output may
/// auto-scroll.
///
/// Scroll events do not bubble, but they do run the capture phase, so one
/// document-level listener keeps working even if the transcript element is
/// replaced by a render. The callback fires only when the at-bottom state
/// changes; the slack absorbs fractional scroll positions.
fn watch_transcript_scroll(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard !transcript_scroll_watched.val else { return }
    transcript_scroll_watched.val = true
    let mut pinned = true
    @interop.add_capture_listener(@js.Cast::from(@dom.document()), "scroll", event => {
      guard event.target().to_element() is Some(element) else { return }
      guard element.get_property("id").to_option() is Some("transcript") else {
        return
      }
      let client_height : Double = @js.Cast::from(element).get_with_string(
        "clientHeight",
      )
      let at_bottom = element.get_scroll_height() -
        element.get_scroll_top() -
        client_height <=
        4.0
      if at_bottom != pinned {
        pinned = at_bottom
        scheduler.add(dispatch(TranscriptPinned(at_bottom)))
      }
    })
  })
}

///|
/// The media-query list for the host's dark-mode preference, or `None` in a
/// webview without `matchMedia`.
fn color_scheme_query() -> @js.Value? {
  guard @interop.js_prop(@js.globalThis, "matchMedia") is Some(_) else {
    return None
  }
  Some(
    @js.globalThis.apply_with_string("matchMedia", [
      @js.Value::cast_from("(prefers-color-scheme: dark)"),
    ]),
  )
}

///|
/// Whether the host prefers a dark color scheme, read once at startup
/// (`initial_model`) and kept fresh by `watch_color_scheme`. The app's own
/// palette flips via the `prefers-color-scheme` media query in CSS; this
/// mirror of it drives the embedded viewer's `data-theme`, which CSS cannot
/// reach.
fn host_prefers_dark() -> Bool {
  guard color_scheme_query() is Some(query) else { return false }
  (@js.Cast::into(query.get_with_string("matches")) : Bool?) is Some(true)
}

///|
let color_scheme_watched : Ref[Bool] = Ref(false)

///|
/// Follow the host's dark-mode preference, feeding changes back as
/// `ColorSchemeChanged` so the viewer's theme flips together with the app's
/// palette instead of staying frozen at its startup value.
fn watch_color_scheme(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard !color_scheme_watched.val else { return }
    guard color_scheme_query() is Some(query) else { return }
    color_scheme_watched.val = true
    @interop.add_capture_listener(query, "change", event => {
      let matches : @js.Value = @js.Cast::from(event).get_with_string("matches")
      scheduler.add(
        dispatch(
          ColorSchemeChanged((@js.Cast::into(matches) : Bool?) is Some(true)),
        ),
      )
    })
  })
}

///|
/// Whether the webview runs on Windows, probed from the user agent (WebView2
/// always carries "Windows"). WSL engine mode is a Windows-only feature, so
/// the settings popup hides its section — and `start` omits the request —
/// everywhere else.
fn host_is_windows() -> Bool {
  guard @interop.js_prop(@js.globalThis, "navigator") is Some(navigator) else {
    return false
  }
  guard @interop.js_prop(navigator, "userAgent") is Some(value) else {
    return false
  }
  (@js.Cast::into(value) : String?) is Some(agent) && agent.contains("Windows")
}
