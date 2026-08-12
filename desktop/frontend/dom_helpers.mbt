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
///
/// The click's handler unpins eagerly, but a transcript that still fits its
/// viewport clamps the write to the same scrollTop — no scroll event, so the
/// watcher would never restore the pin and streaming would silently stop
/// following. Report the definitive at-bottom state from the settled
/// position instead of trusting the eager guess.
fn scroll_turn_into_view(
  dispatch : @cmd.Emit[Msg],
  key : @transcript_overview.TurnKey,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
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
      let client_height : Double = @js.Cast::from(transcript).get_with_string(
        "clientHeight",
      )
      let at_bottom = transcript.get_scroll_height() -
        transcript.get_scroll_top() -
        client_height <=
        4.0
      transcript_pinned_watch.val = at_bottom
      scheduler.add(dispatch(TranscriptPinned(at_bottom)))
      // The same clamped write also fires no event for the highlight: the
      // click's eager `active` and the watcher's anchor cache would both
      // drift from the turn the viewport actually reads. Report the settled
      // truth for both — after a jump that did move, it simply confirms the
      // clicked turn.
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
/// Keep the overview rail's scrolled window on the active tick, on the
/// render that moved the highlight: a rail taller than its cap scrolls, and
/// the turn a stream append or a long jump activates can sit outside that
/// window. Hand-computed nearest-edge writes against the rail alone — a
/// scroll_into_view would walk the transcript scroller too and nudge the
/// conversation the watcher just settled. Never fires from the user's own
/// rail wheeling: that scrolls no transcript, so no ActiveChanged report.
fn reveal_active_overview_tick() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      guard @dom.document().query_selector(".overview-rail").to_option()
        is Some(rail) else {
        return
      }
      guard rail.query_selector(".overview-tick.active") is Some(tick) else {
        return
      }
      let rail_rect = rail.get_bounding_client_rect()
      let tick_rect = tick.get_bounding_client_rect()
      let above = tick_rect.get_top() - rail_rect.get_top()
      let below = tick_rect.get_bottom() - rail_rect.get_bottom()
      if above < 0 {
        rail.set_scroll_top(rail.get_scroll_top() + above)
      } else if below > 0 {
        rail.set_scroll_top(rail.get_scroll_top() + below)
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// The turn the transcript viewport currently reads: the last user bubble
/// whose top sits above the upper third of the scroller — the turn whose
/// answer flows under the reading line. `None` above the first bubble.
///
/// Bubbles come back in document order with ascending tops, so a binary
/// search keeps this at a handful of geometry reads per scroll event; a
/// linear walk would read nearly every bubble whenever the user is near the
/// tail of a long conversation.
fn visible_turn_anchor(transcript : @dom.Element) -> String? {
  let reference = transcript.get_bounding_client_rect().get_top() +
    transcript.get_client_height() * 0.35
  let bubbles = transcript.query_selector_all(".msg.user")
  let mut low = 0
  let mut high = bubbles.length() - 1
  let mut found : Int? = None
  while low <= high {
    let middle = low + (high - low) / 2
    if bubbles[middle].get_bounding_client_rect().get_top() <= reference {
      found = Some(middle)
      low = middle + 1
    } else {
      high = middle - 1
    }
  }
  guard found is Some(index) else { return None }
  bubbles[index].get_attribute("id")
}

///|
/// The last anchor the scroll watcher reported, shared with
/// `report_visible_turn_after_render` so a recompute keeps the watcher's
/// change guard honest — anchors are per-session strings, and two sessions'
/// turns can carry the same one.
let transcript_turn_anchor : Ref[String?] = Ref(None)

///|
/// Recompute the overview's active turn on the render that applied a
/// conversation switch or a viewport resize. Scroll events only fire when
/// scrollTop actually changes, so an opened conversation that fits its
/// viewport — or one whose visible anchor string happens to match the
/// previous session's — would otherwise keep an empty or stale highlight.
/// `skip_unchanged` suppresses the dispatch when the anchor is already what
/// the watcher last reported: right for a resize (state and cache are in
/// sync, only a moved reading line matters), wrong for a switch (the state
/// was just reset, so even an unchanged anchor must be re-reported).
fn report_visible_turn_after_render(
  dispatch : @cmd.Emit[Msg],
  skip_unchanged? : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      guard @dom.document().get_element_by_id("transcript").to_option()
        is Some(transcript) else {
        return
      }
      let anchor = visible_turn_anchor(transcript)
      if skip_unchanged && anchor == transcript_turn_anchor.val {
        return
      }
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
/// The watcher's last at-bottom state, shared with `scroll_turn_into_view`
/// for the same reason as `transcript_turn_anchor`: a clamped jump produces
/// no scroll event, so the correction it dispatches must also resync the
/// watcher's change guard or the next real scroll would be swallowed.
let transcript_pinned_watch : Ref[Bool] = Ref(true)

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
      if at_bottom != transcript_pinned_watch.val {
        transcript_pinned_watch.val = at_bottom
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
