///|
fn is_submit_shortcut(event : @dom.KeyboardEvent) -> Bool {
  event.key() == "Enter" && !event.shift_key() && !event.is_composing()
}

///|
fn scroll_transcript_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      match @dom.document().get_element_by_id("transcript").to_option() {
        Some(transcript) =>
          transcript.set_scroll_top(transcript.get_scroll_height())
        None => ()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Bring the sidebar's active project row into view on the render that
/// applies it: the row a fresh add just activated can sit below the fold
/// of a long sidebar. `nearest` keeps everything still when the row is
/// already visible.
fn reveal_active_project() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().query_selector(".workspace-row.active").to_option()
        is Some(row) {
        row.scroll_into_view_with_options(block="nearest")
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Scroll one user turn's bubble to the top of the transcript on the render
/// that applied the overview click. Hand-computed against the transcript's
/// own scrollTop rather than `scroll_into_view`: that walks every scrollable
/// ancestor, and the app shell above the transcript must not move.
fn scroll_turn_into_view(key : @transcript_overview.TurnKey) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      guard @dom.document().get_element_by_id("transcript").to_option()
        is Some(transcript) else {
        return
      }
      guard @dom.document().get_element_by_id(key.anchor()).to_option()
        is Some(bubble) else {
        return
      }
      let offset = bubble.get_bounding_client_rect().get_top() -
        transcript.get_bounding_client_rect().get_top()
      transcript.set_scroll_top(transcript.get_scroll_top() + offset - 10.0)
    },
    kind=@cmd.after_render,
  )
}

///|
/// The turn the transcript viewport currently reads: the last user bubble
/// whose top sits above the upper third of the scroller — the turn whose
/// answer flows under the reading line. `None` above the first bubble.
fn visible_turn_anchor(transcript : @dom.Element) -> String? {
  let reference = transcript.get_bounding_client_rect().get_top() +
    transcript.get_client_height() * 0.35
  let mut current : String? = None
  for bubble in transcript.query_selector_all(".msg.user") {
    if bubble.get_bounding_client_rect().get_top() <= reference {
      current = bubble.get_attribute("id")
    } else {
      break
    }
  }
  current
}

///|
/// The last anchor the scroll watcher reported, shared with
/// `report_visible_turn_after_render` so a recompute keeps the watcher's
/// change guard honest — anchors are per-session strings, and two sessions'
/// turns can carry the same one.
let transcript_turn_anchor : Ref[String?] = Ref(None)

///|
/// Recompute the overview's active turn on the render that applied a
/// conversation switch. Scroll events only fire when scrollTop actually
/// changes, so an opened conversation that fits its viewport — or one whose
/// visible anchor string happens to match the previous session's — would
/// otherwise keep an empty or stale highlight.
fn report_visible_turn_after_render(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      guard @dom.document().get_element_by_id("transcript").to_option()
        is Some(transcript) else {
        return
      }
      let anchor = visible_turn_anchor(transcript)
      transcript_turn_anchor.val = anchor
      let key = if anchor is Some(id) {
        @transcript_overview.TurnKey::from_anchor(id)
      } else {
        None
      }
      scheduler.add(
        dispatch(TranscriptOverview(@transcript_overview.ActiveChanged(key))),
      )
    },
    kind=@cmd.after_render,
  )
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
      // The overview rail's active-turn highlight, reported the same
      // change-guarded way as the pin.
      let anchor = visible_turn_anchor(element)
      if anchor != transcript_turn_anchor.val {
        transcript_turn_anchor.val = anchor
        let key = if anchor is Some(id) {
          @transcript_overview.TurnKey::from_anchor(id)
        } else {
          None
        }
        scheduler.add(
          dispatch(TranscriptOverview(@transcript_overview.ActiveChanged(key))),
        )
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
/// Mirror the effective model theme onto the document root after update. CSS
/// owns the palette; the command keeps the DOM write out of the pure handler.
fn Theme::apply(self : Theme, system_dark : Bool) -> @cmd.Cmd {
  let value = if self.is_dark(system_dark) { "dark" } else { "light" }
  @cmd.custom_cmd(_ => {
    if @dom.document().get_document_element() is Some(root) {
      root.set_attribute("data-theme", value)
    }
  })
}

///|
let color_scheme_watched : Ref[Bool] = Ref(false)

///|
/// Follow the host's dark-mode preference, feeding changes back as
/// `ColorSchemeChanged`. Update retains every report and applies it immediately
/// only while Settings remains on System.
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
