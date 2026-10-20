// Copy and reply actions beside a fresh text selection. "Reply" turns the bar into
// a small composer that keeps the quote in view while a comment is typed; the
// result is handed to the composer of the transcript the text was selected
// in, either to be sent at once or batched into the message being written
// there. The reply stays open until that composer takes it. Where the screen
// allows it, "Side chat" hands the selection on to start one instead.
// Pointer-only by design.

///|
/// A reply quoting the selected text, for the composer `target` names.
pub(all) struct QuoteReply[T] {
  target : T
  quote : String
  comment : String
  // Send the message now, rather than leave it to go out with the next one.
  send : Bool
  // The composer answers with one of these. Until it accepts, the reply stays
  // open here, so a declined reply loses nothing the reader typed.
  accepted : @cmd.Cmd
  declined : @cmd.Cmd
}

///|
/// What text selected in one quote source can be handed to: the composer a
/// reply goes to, and whether a side chat can start from it. `source` is the
/// source's `data-context-quote` value.
pub(all) struct SelectionTarget[T] {
  source : String
  target : T
  side_chat : Bool
} derive(Eq)

///|
fn[T] target_for(
  targets : Array[SelectionTarget[T]],
  source : String,
) -> SelectionTarget[T]? {
  targets.iter().find_first(candidate => candidate.source == source)
}

///|
/// A quotable selection and where its surface sits.
priv struct SelectionAnchor {
  // The quote source the selection is in, as its `data-context-quote` names it.
  source : String
  text : String
  // Viewport position of the surface's anchor edge: its bottom centre, or its
  // top centre when `below`.
  x : Int32
  y : Int32
  below : Bool
} derive(Eq)

///|
priv enum SelectionStage {
  Offered
  Copying
  Copied
  CopyFailed
  // `declined` shows that the composer would not take the last attempt.
  Replying(comment~ : String, declined~ : Bool)
} derive(Eq)

///|
priv struct SelectionOpen[T] {
  anchor : SelectionAnchor
  // The composer of the source the text was selected in. The surface shows,
  // and delivers, only while that is still that source's composer.
  target : T
  stage : SelectionStage
} derive(Eq)

///|
priv struct SelectionState[T] {
  open : SelectionOpen[T]?
  // Sticky for the page: a reader collecting quotes keeps collecting.
  batched : Bool
  // Fences clipboard completions and expiry against later selections.
  generation : Int32
} derive(Eq)

///|
priv enum SelectionMsg {
  Settled(SelectionAnchor)
  Closed
  CopyStarted
  CopyFinished(Int32, Result[Unit, String])
  CopyExpired(Int32)
  ReplyStarted
  SideChatStarted
  CommentChanged(String)
  BatchToggled
  Submitted
  Delivered
  Declined
}

///|
/// What the document listeners have to watch for, derived from the state
/// after every message so the two cannot drift apart.
priv enum SelectionWatch {
  Idle
  // An offer follows its selection: it goes when the selection changes or
  // moves.
  Offer(SelectionAnchor)
  // A reply being typed stays put: focusing its input is itself a selection
  // change, and a scroll must not cost the reader their text.
  Reply
}

///|
fn[T] SelectionState::watch(self : SelectionState[T]) -> SelectionWatch {
  match self.open {
    None => Idle
    Some({ stage: Offered | Copying | Copied | CopyFailed, anchor, .. }) =>
      Offer(anchor)
    Some({ stage: Replying(..), .. }) => Reply
  }
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
/// Room reserved for the surface, sized for the reply composer holding a short
/// comment so the bar does not jump when it opens. A longer comment grows into
/// whatever room the viewport has past that.
const SelectionSurfaceHeight : Double = 140

///|
const SelectionSurfaceHalfWidth : Double = 190

///|
const SelectionSurfaceGap : Double = 6

///|
/// The current selection, when it is one range of quotable text.
fn settled_anchor() -> SelectionAnchor? {
  guard browser_selection().to_option() is Some(selection) &&
    !selection.collapsed() &&
    selection.count() == 1 else {
    return None
  }
  let text = selection.text()
  let range = selection.range(0)
  guard !text.is_blank() &&
    range.container().to_option() is Some(container) &&
    container.closest(QuoteSource) is Some(quote_source) else {
    return None
  }
  let source = quote_source.get_attribute("data-context-quote").unwrap_or("")
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
    source,
    text,
    x: @math.round(x).to_int(),
    y: @math.round(y).to_int(),
    below,
  })
}

///|
priv struct SelectionListener {
  sync : (SelectionWatch) -> Unit
  unload : () -> Unit
}

///|
fn install_selection_listener(
  emit : (SelectionMsg) -> Unit,
) -> SelectionListener {
  let document = @dom.document()
  let window = @dom.window().as_event_target()
  // Set here the moment a message is sent, then overwritten by `sync` with
  // what the state made of it.
  let mut watch = Idle
  let mut unloaded = false
  let on_surface = (event : @dom.Event) => {
    event_element(event) is Some(element) &&
    element.closest(SelectionSurface) is Some(_)
  }
  let close = () => {
    if !(watch is Idle) {
      watch = Idle
      emit(Closed)
    }
  }
  let follow = () => {
    if watch is Offer(anchor) && settled_anchor() != Some(anchor) {
      watch = Idle
      emit(Closed)
    }
  }
  // Whether the press now held began in a quote source. A release anywhere
  // else — over a menu, say — must not offer a selection left from earlier.
  let mut selecting = false
  let on_mouse_down : @dom.Listener = event => {
    guard !on_surface(event) else { return }
    selecting = event.to_mouse_event() is Some(mouse) &&
      mouse.get_button() == 0 &&
      event_element(event) is Some(element) &&
      element.closest(QuoteSource) is Some(_)
    close()
  }
  let on_mouse_up : @dom.Listener = _ => {
    guard selecting else { return }
    selecting = false
    // A click inside an existing selection collapses it only after `mouseup`.
    let _ = @dom.window().set_timeout(
      () => {
        guard !unloaded && !(watch is Reply) else { return }
        match settled_anchor() {
          Some(anchor) => {
            watch = Offer(anchor)
            emit(Settled(anchor))
          }
          None => follow()
        }
      },
      0,
    )
  }
  let on_change : @dom.Listener = _ => follow()
  let on_key_down : @dom.Listener = event => {
    // Escape during composition belongs to the input method.
    guard event.to_keyboard_event() is Some(key) &&
      key.key() == "Escape" &&
      !key.is_composing() else {
      return
    }
    match watch {
      Idle => ()
      Offer(_) => close()
      // A reply holds typed text: only Escape typed into it closes it, and
      // then it closes nothing else. Escape meant for another overlay opened
      // over the reply is that overlay's.
      Reply =>
        if on_surface(event) {
          event.prevent_default()
          event.stop_propagation()
          close()
        }
    }
  }
  document.add_event_listener_with_options(
    "mousedown",
    on_mouse_down,
    capture=true,
  )
  document.add_event_listener_with_options("mouseup", on_mouse_up, capture=true)
  document.add_event_listener("selectionchange", on_change)
  document.add_event_listener_with_options("keydown", on_key_down, capture=true)
  // The surface is placed in viewport coordinates, so a scroll or resize that
  // moves the selection strands an offer.
  document.add_event_listener_with_options("scroll", on_change, capture=true)
  window.add_event_listener("resize", on_change)
  {
    sync: next => watch = next,
    unload: () => {
      unloaded = true
      document.remove_event_listener_with_options(
        "mousedown",
        on_mouse_down,
        capture=true,
      )
      document.remove_event_listener_with_options(
        "mouseup",
        on_mouse_up,
        capture=true,
      )
      document.remove_event_listener("selectionchange", on_change)
      document.remove_event_listener_with_options(
        "keydown",
        on_key_down,
        capture=true,
      )
      document.remove_event_listener_with_options(
        "scroll",
        on_change,
        capture=true,
      )
      window.remove_event_listener("resize", on_change)
    },
  }
}

///|
priv suberror SelectionSubscription {
  SelectionSubscription(@cmd.Emit[SelectionMsg], SelectionWatch)
}

///|
fn selection_subscription(
  emit : @cmd.Emit[SelectionMsg],
  watch : SelectionWatch,
) -> @sub.Sub {
  @sub.custom_sub(
    "app-selection-actions",
    Global,
    SelectionSubscription(emit, watch),
    (payload, scheduler) => {
      guard payload is SelectionSubscription(emit, watch) else { return None }
      let mut emit = emit
      let listener = install_selection_listener(msg => scheduler.add(emit(msg)))
      (listener.sync)(watch)
      Some({
        unload: _ => (listener.unload)(),
        update_tagger: payload => {
          guard payload is SelectionSubscription(next, watch) else { return }
          emit = next
          (listener.sync)(watch)
        },
      })
    },
  )
}

///|
fn[T : Eq] SelectionState::update(
  self : SelectionState[T],
  targets : Array[SelectionTarget[T]],
  msg : SelectionMsg,
  emit : @cmd.Emit[SelectionMsg],
  deliver : (QuoteReply[T]) -> @cmd.Cmd,
  side_chat? : (T, String) -> @cmd.Cmd,
) -> (SelectionState[T], @cmd.Cmd) {
  let unpin = @cmd.custom_cmd(_ => clear_selection_highlight(QuoteHighlight))
  // The composer the open surface's source names now. A surface whose source
  // has another composer, or none, by now is stale.
  let target = match self.open {
    Some(open) =>
      target_for(targets, open.anchor.source).map(found => found.target)
    None => None
  }
  match (msg, self.open) {
    (Settled(anchor), _) =>
      (
        {
          ..self,
          open: target_for(targets, anchor.source).map(found => {
            anchor,
            target: found.target,
            stage: Offered,
          }),
          generation: self.generation + 1,
        },
        unpin,
      )
    (
      SideChatStarted,
      Some({ stage: Offered | Copying | CopyFailed, .. } as open),
    ) => {
      guard side_chat is Some(start) &&
        target_for(targets, open.anchor.source) is Some(found) &&
        found.target == open.target &&
        found.side_chat else {
        return (self, @cmd.none)
      }
      (
        { ..self, open: None, },
        @cmd.batch([unpin, start(open.target, open.anchor.text)]),
      )
    }
    (Closed, Some(_)) | (Delivered, Some({ stage: Replying(..), .. })) =>
      ({ ..self, open: None, }, unpin)
    (CopyStarted, Some({ stage: Offered | CopyFailed, .. } as open)) => {
      guard target == Some(open.target) else { return (self, @cmd.none) }
      let generation = self.generation + 1
      (
        { ..self, generation, open: Some({ ..open, stage: Copying, }), },
        @clipboard.copy(
          Text(open.anchor.text),
          copied=emit(CopyFinished(generation, Ok(()))),
          failed=error => emit(CopyFinished(generation, Err(error))),
        ),
      )
    }
    (CopyFinished(generation, result), Some({ stage: Copying, .. } as open)) => {
      guard generation == self.generation && target == Some(open.target) else {
        return (self, @cmd.none)
      }
      match result {
        Ok(_) =>
          (
            { ..self, open: Some({ ..open, stage: Copied, }), },
            @cmd.delay(emit(CopyExpired(generation)), 1000),
          )
        Err(_) =>
          ({ ..self, open: Some({ ..open, stage: CopyFailed, }), }, @cmd.none)
      }
    }
    (CopyExpired(generation), Some({ stage: Copied, .. })) => {
      guard generation == self.generation else { return (self, @cmd.none) }
      ({ ..self, open: None, }, @cmd.none)
    }
    (ReplyStarted, Some({ stage: Offered | Copying | CopyFailed, .. } as open)) =>
      (
        {
          ..self,
          open: Some({ ..open, stage: Replying(comment="", declined=false), }),
        },
        @cmd.batch([
          // Pinned while the range is still selected; focusing the input
          // takes the native selection with it.
          @cmd.custom_cmd(_ => pin_selection_highlight(QuoteHighlight)),
          focus_element(SelectionReplyInput, true),
        ]),
      )
    (CommentChanged(comment), Some({ stage: Replying(..), .. } as open)) =>
      (
        {
          ..self,
          open: Some({ ..open, stage: Replying(comment~, declined=false), }),
        },
        @cmd.none,
      )
    (Declined, Some({ stage: Replying(comment~, ..), .. } as open)) =>
      (
        {
          ..self,
          open: Some({ ..open, stage: Replying(comment~, declined=true), }),
        },
        @cmd.none,
      )
    (BatchToggled, _) =>
      (
        { ..self, batched: !self.batched, },
        // The checkbox took the focus; Enter belongs to the comment.
        focus_element(SelectionReplyInput, true),
      )
    (
      Submitted,
      Some({ stage: Replying(comment~, ..), anchor, target: addressed, }),
    ) => {
      // A batched quote may wait for its comment; a message sent now is the
      // comment.
      guard target == Some(addressed) && (self.batched || !comment.is_blank()) else {
        return (self, @cmd.none)
      }
      (
        self,
        deliver({
          target: addressed,
          quote: anchor.text,
          comment,
          send: !self.batched,
          accepted: emit(Delivered),
          declined: emit(Declined),
        }),
      )
    }
    _ => (self, @cmd.none)
  }
}

///|
fn selection_surface_attrs(
  stage : SelectionStage,
  label : String,
) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .aria_label(label)
    .data_set("selection-actions", "")
  match stage {
    // Keep the selection and the focus where they are while the button is
    // pressed; `ReplyStarted` decides what moves.
    Offered | Copying | CopyFailed =>
      attrs
      .role("toolbar")
      .on_mousedown(event => {
        event.prevent_default()
        @cmd.none
      })
    Copied => attrs.role("status")
    Replying(..) => attrs.role("dialog")
  }
}

///|
/// Own the floating reply for text selected inside a quote source. `targets`
/// names, per quote source on screen, the composer a reply from it goes to;
/// `deliver` hands a finished reply to it. With `side_chat`, a source that
/// allows it also offers to start a side chat from the selected text.
pub fn[T : Eq] selection_component(
  locale : @rabbita.Val[@i18n.Locale],
  targets : @rabbita.Val[Array[SelectionTarget[T]]],
  deliver : (QuoteReply[T]) -> @cmd.Cmd,
  side_chat? : (T, String) -> @cmd.Cmd,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input=targets,
    init=(_, _) => {
      (
        SelectionState::{ open: None, batched: false, generation: 0, },
        @cmd.none,
      )
    },
    update=(state, targets, msg, emit) => {
      state.update(targets, msg, emit, deliver, side_chat?)
    },
    subscriptions=(state, _, emit) => {
      selection_subscription(emit, state.watch())
    },
  )
  state.map3(targets, locale, (state, targets, locale) => {
    // A surface opened over another conversation is not this one's to show.
    guard state.open is Some(open) &&
      target_for(targets, open.anchor.source) is Some(found) &&
      found.target == open.target else {
      return @html.nothing
    }
    let placement = if open.anchor.below { " below" } else { "" }
    // The surface grows away from the selection as a comment gains lines;
    // `room` is how far it can go before it would leave the viewport.
    let gap = SelectionSurfaceGap.to_int()
    let room = if open.anchor.below {
      "calc(100vh - \{open.anchor.y + gap}px)"
    } else {
      "\{open.anchor.y - gap}px"
    }
    let style = [
      "left: \{open.anchor.x}px",
      "top: \{open.anchor.y}px",
      "max-height: \{room}",
    ]
    match open.stage {
      Offered | Copying | CopyFailed =>
        @html.div(
          class="selection-actions\{placement}",
          style~,
          attrs=selection_surface_attrs(
            open.stage,
            ui(locale, SelectionActions),
          ),
          [
            @html.div(
              class="selection-actions-buttons",
              [
                @html.button(
                  class="action-menu-item",
                  type_="button",
                  title=ui(locale, CopySelected),
                  disabled=open.stage is Copying,
                  on_click=emit(CopyStarted),
                  ui(locale, CopyLabel),
                ),
                @html.div(
                  class="selection-actions-separator",
                  attrs=@html.Attrs::build().aria_hidden("true"),
                  @html.nothing,
                ),
                @html.button(
                  class="action-menu-item",
                  type_="button",
                  title=ui(locale, ReplyHint),
                  attrs=@html.Attrs::build().on_click(_ => emit(ReplyStarted)),
                  ui(locale, ReplyLabel),
                ),
                ..if side_chat is Some(_) && found.side_chat {
                  [
                    @html.div(
                      class="selection-actions-separator",
                      attrs=@html.Attrs::build().aria_hidden("true"),
                      @html.nothing,
                    ),
                    @html.button(
                      class="action-menu-item",
                      type_="button",
                      title=ui(locale, SideChatHint),
                      attrs=@html.Attrs::build().on_click(_ => {
                        emit(SideChatStarted)
                      }),
                      ui(locale, SideChatLabel),
                    ),
                  ]
                } else {
                  []
                },
              ],
            ),
            if open.stage is CopyFailed {
              @html.div(
                class="selection-copy-error",
                attrs=@html.Attrs::build().role("status"),
                ui(locale, CopyFailure),
              )
            } else {
              @html.nothing
            },
          ],
        )
      Copied =>
        @html.div(
          class="selection-actions selection-copy-feedback\{placement}",
          style~,
          attrs=selection_surface_attrs(open.stage, ui(locale, CopySuccess)),
          [@icons.icon(@icons.icon_check), @html.span(ui(locale, CopySuccess))],
        )
      Replying(comment~, declined~) => {
        let sendable = state.batched || !comment.is_blank()
        let submit_title = if state.batched {
          ui(locale, AddReply)
        } else {
          ui(locale, SendReply)
        }
        @html.div(
          class="selection-actions replying\{placement}",
          style~,
          attrs=selection_surface_attrs(open.stage, ui(locale, ReplyDialog)),
          [
            @html.blockquote(class="selection-reply-quote", open.anchor.text),
            @html.div(class="selection-reply-row", [
              // Enter sends; Shift+Enter starts a new line, and the input
              // grows to show it.
              @html.textarea(
                id=SelectionReplyInput,
                class="selection-reply-input",
                value=comment,
                rows=1,
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
                "",
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
            // Last, so its coming and going moves nothing the reader is
            // typing in.
            if declined {
              @html.div(
                class="selection-reply-note",
                attrs=@html.Attrs::build().role("status"),
                ui(locale, ReplyDeclined),
              )
            } else {
              @html.nothing
            },
          ],
        )
      }
    }
  })
}

///|
pub extend SelectionTarget with Eq::{equal, not_equal}
