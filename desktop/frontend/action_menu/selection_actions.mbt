// The floating reply beside a fresh text selection. "Reply" turns the bar into
// a small composer that keeps the quote in view while a comment is typed; the
// result goes to the screen's reply input, either sent at once or batched
// into the message being written there. Pointer-only by design.

///|
/// Quoting selected text, with a comment, into the screen's reply input.
pub(all) struct QuoteActions {
  // Whether the screen has a reply input right now. Asked each time a
  // selection is offered, never while rendering.
  available : () -> Bool
  // Quote and comment, sent as a message now.
  send : (String, String) -> @cmd.Cmd
  // Quote and comment, added to the message being written.
  batch : (String, String) -> @cmd.Cmd
}

///|
priv enum SelectionStage {
  Offered
  Replying(comment~ : String)
} derive(Eq)

///|
priv struct SelectionOpen {
  text : String
  // Viewport position of the surface's anchor edge: its bottom centre, or its
  // top centre when `below`.
  x : Int
  y : Int
  below : Bool
  stage : SelectionStage
} derive(Eq)

///|
priv struct SelectionState {
  open : SelectionOpen?
  // Sticky for the page: a reader collecting quotes keeps collecting.
  batched : Bool
} derive(Eq)

///|
priv enum SelectionMsg {
  Settled(SelectionOpen)
  // The selection moved or went away. That ends an offer, but not a reply
  // already being typed: focusing its input is itself a selection change.
  Abandoned
  Closed
  ReplyStarted
  CommentChanged(String)
  BatchToggled
  Submitted
}

///|
const SelectionSurface : String = "[data-selection-actions]"

///|
/// Selections inside an element carrying this attribute get the bar.
const QuoteSource : String = "[data-context-quote]"

///|
const SelectionReplyInput : String = "selection-reply-input"

///|
/// The CSS custom highlight that keeps the quoted range painted once focus
/// has moved into the reply input. `overlays.css` styles the same name.
const QuoteHighlight : String = "quote-reply"

///|
/// Room reserved for the surface, sized for the reply composer so the bar
/// does not jump when it opens.
const SelectionSurfaceHeight : Double = 116

///|
const SelectionSurfaceHalfWidth : Double = 190

///|
const SelectionSurfaceGap : Double = 6

///|
/// Where the surface sits for the current selection, when that selection is
/// quotable text.
fn settled_selection() -> SelectionOpen? {
  guard browser_selection().to_option() is Some(selection) &&
    !selection.collapsed() &&
    selection.count() > 0 else {
    return None
  }
  let text = selection.text()
  let range = selection.range(0)
  guard !text.is_blank() &&
    range.container().to_option() is Some(container) &&
    container.closest(QuoteSource) is Some(_) else {
    return None
  }
  let bounds = range.bounds()
  let width = viewport_width()
  let center = (bounds.get_left() + bounds.get_right()) / 2
  let x = if width < SelectionSurfaceHalfWidth * 2 {
    width / 2
  } else {
    center.max(SelectionSurfaceHalfWidth).min(width - SelectionSurfaceHalfWidth)
  }
  let below = bounds.get_top() < SelectionSurfaceHeight + SelectionSurfaceGap
  let y = if below {
    (bounds.get_bottom() + SelectionSurfaceGap)
    .min(viewport_height() - SelectionSurfaceHeight)
    .max(SelectionSurfaceGap)
  } else {
    bounds.get_top() - SelectionSurfaceGap
  }
  Some({
    text,
    x: @math.round(x).to_int(),
    y: @math.round(y).to_int(),
    below,
    stage: Offered,
  })
}

///|
fn install_selection_listener(
  available : () -> Bool,
  emit : (SelectionMsg) -> Unit,
) -> () -> Unit {
  let document = @dom.document()
  let window = @dom.window().as_event_target()
  // Only a shown surface needs telling; this keeps ordinary typing and
  // scrolling from sending a message per event.
  let mut shown = false
  let close = () => {
    if shown {
      shown = false
      emit(Closed)
    }
  }
  let abandon = () => if shown { emit(Abandoned) }
  let on_surface = (event : @dom.Event) => {
    event_element(event) is Some(element) &&
    element.closest(SelectionSurface) is Some(_)
  }
  let on_mouse_down : @dom.Listener = event => if !on_surface(event) { close() }
  let on_mouse_up : @dom.Listener = event => {
    guard event.to_mouse_event() is Some(mouse) &&
      mouse.get_button() == 0 &&
      !on_surface(event) else {
      return
    }
    // A click inside an existing selection collapses it only after `mouseup`.
    let _ = @dom.window().set_timeout(
      () => {
        match settled_selection() {
          Some(open) if available() => {
            shown = true
            emit(Settled(open))
          }
          _ => abandon()
        }
      },
      0,
    )
  }
  let on_selection_change : @dom.Listener = _ => {
    if browser_selection().to_option() is Some(selection) &&
      !selection.collapsed() {
      return
    }
    abandon()
  }
  let on_key_down : @dom.Listener = event => {
    if event.to_keyboard_event() is Some(key) && key.key() == "Escape" {
      close()
    }
  }
  let on_leave : @dom.Listener = _ => abandon()
  document.add_event_listener_with_options(
    "mousedown",
    on_mouse_down,
    capture=true,
  )
  document.add_event_listener("mouseup", on_mouse_up)
  document.add_event_listener("selectionchange", on_selection_change)
  document.add_event_listener_with_options("keydown", on_key_down, capture=true)
  // The surface is placed in viewport coordinates, so a scroll strands an
  // offer. A reply being typed stays put instead of losing its text.
  document.add_event_listener_with_options("scroll", on_leave, capture=true)
  window.add_event_listener("resize", on_leave)
  window.add_event_listener("blur", on_leave)
  () => {
    document.remove_event_listener_with_options(
      "mousedown",
      on_mouse_down,
      capture=true,
    )
    document.remove_event_listener("mouseup", on_mouse_up)
    document.remove_event_listener("selectionchange", on_selection_change)
    document.remove_event_listener_with_options(
      "keydown",
      on_key_down,
      capture=true,
    )
    document.remove_event_listener_with_options(
      "scroll",
      on_leave,
      capture=true,
    )
    window.remove_event_listener("resize", on_leave)
    window.remove_event_listener("blur", on_leave)
  }
}

///|
priv suberror SelectionSubscription {
  SelectionSubscription(@cmd.Emit[SelectionMsg])
}

///|
fn selection_subscription(
  emit : @cmd.Emit[SelectionMsg],
  available : () -> Bool,
) -> @sub.Sub {
  @sub.custom_sub(
    "app-selection-actions",
    Global,
    SelectionSubscription(emit),
    (payload, scheduler) => {
      guard payload is SelectionSubscription(emit) else { return None }
      let mut emit = emit
      let unload = install_selection_listener(available, msg => {
        scheduler.add(emit(msg))
      })
      Some({
        unload: _ => unload(),
        update_tagger: payload => {
          guard payload is SelectionSubscription(next) else { return }
          emit = next
        },
      })
    },
  )
}

///|
fn SelectionState::update(
  self : SelectionState,
  msg : SelectionMsg,
  actions : QuoteActions,
) -> (SelectionState, @cmd.Cmd) {
  let unpin = @cmd.custom_cmd(_ => clear_selection_highlight(QuoteHighlight))
  match (msg, self.open) {
    (Settled(open), _) => ({ ..self, open: Some(open), }, unpin)
    (Abandoned, Some({ stage: Offered, .. })) | (Closed, Some(_)) =>
      ({ ..self, open: None, }, unpin)
    (ReplyStarted, Some({ stage: Offered, .. } as open)) =>
      (
        { ..self, open: Some({ ..open, stage: Replying(comment=""), }), },
        @cmd.batch([
          // Pinned while the range is still selected; focusing the input
          // takes the native selection with it.
          @cmd.custom_cmd(_ => pin_selection_highlight(QuoteHighlight)),
          focus_element(SelectionReplyInput, true),
        ]),
      )
    (CommentChanged(comment), Some({ stage: Replying(_), .. } as open)) =>
      (
        { ..self, open: Some({ ..open, stage: Replying(comment~), }), },
        @cmd.none,
      )
    (BatchToggled, _) =>
      (
        { ..self, batched: !self.batched, },
        // The checkbox took the focus; Enter belongs to the comment.
        focus_element(SelectionReplyInput, true),
      )
    (Submitted, Some({ stage: Replying(comment~), text, .. })) => {
      // A batched quote may wait for its comment; a message sent now is the
      // comment.
      guard self.batched || !comment.is_blank() else {
        return (self, @cmd.none)
      }
      let deliver = if self.batched { actions.batch } else { actions.send }
      ({ ..self, open: None, }, @cmd.batch([unpin, deliver(text, comment)]))
    }
    _ => (self, @cmd.none)
  }
}

///|
fn selection_surface_attrs(open : SelectionOpen, label : String) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .aria_label(label)
    .data_set("selection-actions", "")
  match open.stage {
    // Keep the selection and the focus where they are while the button is
    // pressed; `ReplyStarted` decides what moves.
    Offered =>
      attrs
      .role("toolbar")
      .on_mousedown(event => {
        event.prevent_default()
        @cmd.none
      })
    Replying(_) => attrs.role("dialog")
  }
}

///|
/// Own the floating reply for text selected inside a quote source.
pub fn selection_component(
  locale : @rabbita.Val[@i18n.Locale],
  actions : QuoteActions,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state(
    SelectionState::{ open: None, batched: false, },
    update=(state, msg, _) => state.update(msg, actions),
    subscriptions=(_, emit) => selection_subscription(emit, actions.available),
  )
  state.map2(locale, (state, locale) => {
    guard state.open is Some(open) else { return @html.nothing }
    let placement = if open.below { " below" } else { "" }
    let style = ["left: \{open.x}px", "top: \{open.y}px"]
    match open.stage {
      Offered =>
        @html.div(
          class="selection-actions\{placement}",
          style~,
          attrs=selection_surface_attrs(open, ui(locale, SelectionActions)),
          [
            @html.button(
              class="action-menu-item",
              type_="button",
              title=ui(locale, ReplyHint),
              attrs=@html.Attrs::build().on_click(_ => emit(ReplyStarted)),
              [@icons.icon_reply(), @html.span(ui(locale, ReplyLabel))],
            ),
          ],
        )
      Replying(comment~) => {
        let sendable = state.batched || !comment.is_blank()
        let submit_title = if state.batched {
          ui(locale, AddReply)
        } else {
          ui(locale, SendReply)
        }
        @html.div(
          class="selection-actions replying\{placement}",
          style~,
          attrs=selection_surface_attrs(open, ui(locale, ReplyDialog)),
          [
            @html.blockquote(class="selection-reply-quote", open.text),
            @html.div(class="selection-reply-row", [
              @html.input(
                input_type=@html.InputType::Text,
                id=SelectionReplyInput,
                class="selection-reply-input",
                value=comment,
                placeholder=ui(locale, ReplyLabel),
                on_input=emit.map(value => CommentChanged(value)),
                attrs=@html.Attrs::build()
                  .aria_label(ui(locale, ReplyLabel))
                  .on_keydown(event => {
                    if event.key() == "Enter" &&
                      !event.shift_key() &&
                      !event.is_composing() {
                      event.prevent_default()
                      emit(Submitted)
                    } else {
                      @cmd.none
                    }
                  }),
              ),
              @html.label(
                class="selection-reply-batch",
                title=ui(locale, BatchHint),
                [
                  @html.input(
                    input_type=@html.InputType::Checkbox,
                    checked=state.batched,
                    on_change=emit.map(_ => BatchToggled),
                  ),
                  @html.span(ui(locale, BatchLabel)),
                ],
              ),
              @html.button(
                class="icon-button selection-reply-submit",
                type_="button",
                title=submit_title,
                disabled=!sendable,
                attrs=@html.Attrs::build()
                  .aria_label(submit_title)
                  .on_click(_ => emit(Submitted)),
                [
                  if state.batched {
                    @icons.icon_add()
                  } else {
                    @icons.icon_send()
                  },
                ],
              ),
            ]),
          ],
        )
      }
    }
  })
}
