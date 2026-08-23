// The rail's render: a vertical strip of ticks in the transcript's left
// gutter, one per user turn. Sticky inside the scroller with zero height —
// the same trick as the jump-latest button — so it never adds scroll length.

///|
/// One tick per entry, the active turn highlighted, the hovered tick showing
/// a preview of the prompt and its answer. Always rendered as the scroller's
/// first child (a stable position keeps the vdom from rebuilding the stream
/// when it appears); below two turns it hides itself — a rail with one stop
/// is noise. `clock` formats an entry's send stamp; the caller owns the
/// locale format, and an empty label drops the time row.
pub fn rail(
  entries : Array[Entry],
  state : State,
  emit : @cmd.Emit[Msg],
  clock~ : (Double) -> String,
) -> @html.Html {
  let ticks : Array[@html.Html] = []
  for entry in entries {
    let mut tick_class = "overview-tick"
    if state.active == Some(entry.key) {
      tick_class += " active"
    }
    if state.hover is Some(hover) && hover.key == entry.key {
      tick_class += " hovered"
    }
    if entry.failed {
      tick_class += " failed"
    }
    // The mark is a color, so the label carries the same fact in words: a
    // reader who cannot see the difference between two 7px dashes still hears
    // which turns hit errors while arrowing the rail.
    let label = if entry.failed {
      "\{entry.text} (had errors)"
    } else {
      entry.text
    }
    ticks.push(
      @html.div(class=tick_class, [
        @html.button(
          class="overview-tick-button",
          type_="button",
          on_click=emit(Clicked(entry.key)),
          attrs=@html.Attrs::build()
            .aria_label(label)
            .on_mouseenter(event => {
              let (flip, anchor) = preview_measure(event)
              emit(Entered(entry.key, flip~, anchor~))
            }),
          "",
        ),
      ]),
    )
  }
  // The popover is the nav's child, not the hovered tick's: the rail is a
  // scroll container, and a scroll container clips everything inside it.
  // The hover's enter-time anchor replaces the tick position it can no
  // longer inherit.
  let children : Array[@html.Html] = [@html.div(class="overview-rail", ticks)]
  if state.hover is Some(hover) {
    for entry in entries {
      if entry.key == hover.key {
        children.push(
          preview(entry, clock, flip=hover.flip, anchor=hover.anchor),
        )
        break
      }
    }
  }
  @html.nav(
    class="transcript-overview",
    hidden=entries.length() < 2,
    attrs=@html.Attrs::build()
      .aria_label("Conversation overview")
      .on_mouseleave(_ => emit(Left)),
    children,
  )
}

///|
/// Vertical room a full downward preview needs below its tick: three
/// clamped prompt lines, the time row, four clamped reply lines, padding,
/// and a breathing margin.
const PREVIEW_RESERVE : Double = 170

///|
/// Whether this tick's preview must open upward, and the tick edge it hangs
/// from, measured where the answer lives — the tick's real position against
/// its scroller at enter time. A turn count cannot answer the flip:
/// available room depends on the viewport and the rail's position, not on
/// how many turns there are. Flip only when a downward preview cannot fit
/// AND up has more room than down, so a pane too short in both directions
/// keeps the default. The anchor is the flip's hanging edge — top down,
/// bottom up — relative to the nav the popover renders in.
fn preview_measure(event : @dom.MouseEvent) -> (Bool, Double) {
  guard event.target().to_element() is Some(tick) else { return (false, 0) }
  guard tick.closest(".transcript") is Some(scroller) else { return (false, 0) }
  guard tick.closest(".transcript-overview") is Some(nav) else {
    return (false, 0)
  }
  let tick_rect = tick.get_bounding_client_rect()
  let scroller_rect = scroller.get_bounding_client_rect()
  let nav_top = nav.get_bounding_client_rect().get_top()
  let below = scroller_rect.get_bottom() - tick_rect.get_bottom()
  let above = tick_rect.get_top() - scroller_rect.get_top()
  let flip = below < PREVIEW_RESERVE && above > below
  let anchor = if flip {
    tick_rect.get_bottom() - nav_top
  } else {
    tick_rect.get_top() - nav_top
  }
  (flip, anchor)
}

///|
fn preview(
  entry : Entry,
  clock : (Double) -> String,
  flip~ : Bool,
  anchor~ : Double,
) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.div(class="overview-preview-prompt", clamp_preview(entry.text)),
  ]
  if entry.ts is Some(ts) {
    let label = clock(ts)
    if !label.is_empty() {
      children.push(@html.div(class="overview-preview-time", label))
    }
  }
  if entry.failed {
    // The popover is where a reader checks what a mark meant, so it carries
    // the fact in words rather than leaving the tick's color to be decoded.
    children.push(@html.div(class="overview-preview-failed", "had errors"))
  }
  if entry.reply is Some(reply) {
    children.push(
      @html.div(class="overview-preview-reply", clamp_preview(reply)),
    )
  }
  @html.div(
    class=if flip { "overview-preview flip" } else { "overview-preview" },
    style=["--overview-preview-anchor: \{anchor}px"],
    attrs=@html.Attrs::build().role("tooltip"),
    children,
  )
}

///|
/// Keep the popover's DOM light: the CSS line clamp trims what is shown;
/// this trims what a huge prompt or answer would still force the layout to
/// measure. Cut by characters, so a surrogate pair is never split.
fn clamp_preview(text : String) -> String {
  if text.length() <= 400 {
    return text
  }
  let cut = String::from_iter(text.iter().take(400))
  if cut.length() == text.length() {
    text
  } else {
    cut + "…"
  }
}
