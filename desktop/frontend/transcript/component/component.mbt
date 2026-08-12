///|
/// The conversation data rendered by the component. The application computes
/// durable chronology and active-run ownership; this package owns only the
/// transcript subtree and its scroll behavior.
struct Input {
  focused : @interop.ChannelId
  active_session : String
  items : Array[@transcript.TranscriptItem]
  streaming_response : String
  subruns : Array[@transcript.SubrunLane]
} derive(Eq)

///|
pub fn Input::Input(
  focused~ : @interop.ChannelId,
  active_session~ : String,
  items~ : Array[@transcript.TranscriptItem],
  streaming_response~ : String,
  subruns~ : Array[@transcript.SubrunLane],
) -> Input {
  { focused, active_session, items, streaming_response, subruns }
}

///|
/// Parent-owned actions used by links in the transcript. They are captured by
/// the component construction and never stored in its Model.
pub(all) struct Actions {
  open : @cmd.Emit[String]
  jump : @cmd.Emit[@mention_context.Target]
}

///|
priv struct Model {
  pinned : Bool
  overview : @transcript_overview.State
  focused : @interop.ChannelId
  active_session : String
  item_count : Int
  mounted : Bool
} derive(Eq)

///|
priv enum Msg {
  Pinned(Bool)
  JumpToLatest
  ContentRendered(mounted~ : Bool)
  Overview(@transcript_overview.Msg)
}

///|
fn Model::update(
  self : Model,
  input : Input,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    Pinned(pinned) => ({ ..self, pinned, }, @cmd.none)
    JumpToLatest =>
      (
        { ..self, pinned: true },
        @cmd.batch([
          scroll_after_render(),
          report_visible_turn_after_render(emit, skip_unchanged=true),
        ]),
      )
    ContentRendered(mounted~) => {
      // The component outlives the Chat DOM while Skills, Settings, or the
      // signed-out console gate is shown. A newly mounted scroller therefore
      // resets scroll and overview state even when the conversation identity
      // itself did not change.
      let remounted = mounted && !self.mounted
      let navigated = remounted ||
        self.focused != input.focused ||
        self.active_session != input.active_session
      // A newly appended user item is the local equivalent of React's
      // "sent a message" state transition: even a reader who had scrolled up
      // follows their own new turn. Other growth follows only while pinned.
      let sent = !navigated &&
        input.items.length() > self.item_count &&
        input.items[self.item_count:].any(item => item.kind is User)
      let pinned = navigated || sent || self.pinned
      let next = {
        pinned,
        overview: if navigated {
          @transcript_overview.State::empty()
        } else {
          self.overview
        },
        focused: input.focused,
        active_session: input.active_session,
        item_count: input.items.length(),
        mounted,
      }
      let commands : Array[@cmd.Cmd] = []
      if pinned {
        commands.push(scroll_after_render())
      }
      commands.push(
        report_visible_turn_after_render(emit, skip_unchanged=!navigated),
      )
      (next, @cmd.batch(commands))
    }
    Overview(msg) => {
      let previous_active = self.overview.active
      let next = {
        ..self,
        overview: @transcript_overview.update(msg, self.overview),
      }
      match msg {
        // The clicked tick is already under the pointer. Revealing it could
        // move the rail beneath the pointer and transfer hover to a neighbor.
        Clicked(key) =>
          ({ ..next, pinned: false }, scroll_turn_into_view(emit, key))
        // A transcript scroll may activate a tick outside the rail's visible
        // window. Reveal only an actual active-turn change so rail scrolling
        // itself cannot feed back into another write.
        ActiveChanged(_) =>
          if next.overview.active == previous_active {
            (next, @cmd.none)
          } else {
            (next, reveal_active_overview_tick())
          }
        _ => (next, @cmd.none)
      }
    }
  }
}

///|
/// Build the transcript state and return its independently updating Html.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, input) => {
      (
        {
          pinned: true,
          overview: @transcript_overview.State::empty(),
          focused: input.focused,
          active_session: input.active_session,
          item_count: input.items.length(),
          mounted: false,
        },
        @cmd.none,
      )
    },
    update=(state, input, msg, emit) => state.update(input, msg, emit),
    subscriptions=(_, _, emit) => transcript_subscription(emit),
  )
  state.view2(input, (state, input) => {
    transcript_view(
      input,
      pinned=state.pinned,
      overview=state.overview,
      overview_emit=emit.map(msg => Overview(msg)),
      path => (actions.open)(path),
      target => (actions.jump)(target),
      on_jump_latest=emit(JumpToLatest),
    )
  })
}

///|
fn scroll_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      // A forced tail jump must also reset the subscription's DOM cache. A
      // remounted short transcript may clamp without emitting a scroll event.
      transcript_pinned_watch.val = true
      if @dom.document().get_element_by_id("transcript").to_option()
        is Some(transcript) {
        transcript.set_scroll_top(transcript.get_scroll_height())
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Keep the overview rail's own scrolled window on the active tick. This
/// writes only the rail: scroll_into_view would also move the transcript
/// scroller whose position selected the active turn.
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
/// The last DOM state reported by the scroll subscription. The overview jump
/// commands update the same cache because a clamped scroll emits no event.
let transcript_pinned_watch : Ref[Bool] = Ref(true)

///|
let transcript_turn_anchor : Ref[String?] = Ref(None)

///|
/// The user turn under the reading line, expressed through the same anchor
/// attached to its bubble and overview tick.
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
/// Jump one overview tick inside the transcript without moving any ancestor
/// scroller, then report the settled pin and active turn even when the write
/// was clamped and produced no scroll event.
fn scroll_turn_into_view(
  emit : @cmd.Emit[Msg],
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
      let pinned = transcript.get_scroll_height() -
        transcript.get_scroll_top() -
        client_height <=
        4.0
      transcript_pinned_watch.val = pinned
      scheduler.add(emit(Pinned(pinned)))
      let anchor = visible_turn_anchor(transcript)
      transcript_turn_anchor.val = anchor
      let active = anchor.bind(@transcript_overview.TurnKey::from_anchor)
      scheduler.add(emit(Overview(ActiveChanged(active))))
    },
    kind=@cmd.after_render,
  )
}

///|
/// Re-read the overview highlight after content or geometry changed. Session
/// switches force a report even when two sessions happen to reuse an anchor.
fn report_visible_turn_after_render(
  emit : @cmd.Emit[Msg],
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
      let active = anchor.bind(@transcript_overview.TurnKey::from_anchor)
      scheduler.add(emit(Overview(ActiveChanged(active))))
    },
    kind=@cmd.after_render,
  )
}

///|
priv suberror TranscriptSubscription {
  TranscriptSubscription(@cmd.Emit[Msg])
}

///|
/// Scroll position and rendered-content growth are DOM signals owned by the
/// transcript. Keeping both in this component means the application no longer
/// forwards a synthetic "content changed" message into child state.
fn transcript_subscription(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "transcript-dom",
    @sub.Local,
    TranscriptSubscription(emit),
    transcript_sub_loader,
  )
}

///|
fn transcript_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    TranscriptSubscription(emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let listener : @dom.Listener = event => {
        guard event.target().to_element() is Some(element) &&
          element.get_property("id").to_option() == Some("transcript") else {
          return
        }
        let client_height : Double = @js.Cast::from(element).get_with_string(
          "clientHeight",
        )
        let pinned = element.get_scroll_height() -
          element.get_scroll_top() -
          client_height <=
          4.0
        if pinned != transcript_pinned_watch.val {
          transcript_pinned_watch.val = pinned
          scheduler.add(emit(Pinned(pinned)))
        }
        let anchor = visible_turn_anchor(element)
        if anchor != transcript_turn_anchor.val {
          transcript_turn_anchor.val = anchor
          let active = anchor.bind(@transcript_overview.TurnKey::from_anchor)
          scheduler.add(emit(Overview(ActiveChanged(active))))
        }
      }
      target.add_event_listener_with_options("scroll", listener, capture=true)
      let observer = install_transcript_observer(mounted => {
        scheduler.add(emit(ContentRendered(mounted~)))
      })
      Some({
        unload: _ => {
          target.remove_event_listener_with_options(
            "scroll",
            listener,
            capture=true,
          )
          remove_transcript_observer(observer)
        },
        update_tagger: payload => {
          guard payload is TranscriptSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
/// Observe content, identity, and geometry owned by `#transcript`. The
/// identity attributes change even when two conversations have identical
/// markup; the document observer also follows Rabbita replacements, while the
/// resize observer covers geometry changes that do not mutate children.
extern "js" fn install_transcript_observer(
  on_change : (Bool) -> Unit,
) -> @js.Value =
  #| (onChange) => {
  #|   let current = null;
  #|   const resize = new ResizeObserver(() => onChange(true));
  #|   const attach = () => {
  #|     const transcript = document.getElementById("transcript");
  #|     if (transcript === current) return transcript;
  #|     resize.disconnect();
  #|     current = transcript;
  #|     if (current) resize.observe(current);
  #|     return transcript;
  #|   };
  #|   const mutation = new MutationObserver((records) => {
  #|     const previous = current;
  #|     const transcript = attach();
  #|     if (transcript !== previous) {
  #|       onChange(Boolean(transcript));
  #|       return;
  #|     }
  #|     if (!transcript) return;
  #|     const changed = records.some((record) =>
  #|       record.target === transcript ||
  #|       transcript.contains(record.target) ||
  #|       [...record.addedNodes].some((node) =>
  #|         node === transcript || (node.nodeType === 1 && node.contains(transcript))
  #|       )
  #|     );
  #|     if (changed) onChange(true);
  #|   });
  #|   attach();
  #|   mutation.observe(document.documentElement, {
  #|     attributes: true,
  #|     childList: true,
  #|     characterData: true,
  #|     subtree: true,
  #|     attributeFilter: ["data-transcript-channel", "data-transcript-session"],
  #|   });
  #|   return { mutation, resize };
  #| }

///|
extern "js" fn remove_transcript_observer(observer : @js.Value) -> Unit = "(observer) => { observer.mutation.disconnect(); observer.resize.disconnect(); }"

///|
test "local pinned transitions are pure" {
  let input = Input(
    focused=Local,
    active_session="desktop-test",
    items=[],
    streaming_response="",
    subruns=[],
  )
  let state : Model = {
    pinned: true,
    overview: @transcript_overview.State::empty(),
    focused: Local,
    active_session: "desktop-test",
    item_count: 0,
    mounted: true,
  }
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (first, _) = state.update(input, Pinned(false), emit)
  let (second, _) = state.update(input, Pinned(false), emit)
  assert_false(first.pinned)
  assert_false(second.pinned)
  let (grown, _) = first.update(input, ContentRendered(mounted=true), emit)
  assert_false(grown.pinned)
  let (sent, _) = first.update(
    {
      ..input,
      items: [{ kind: User, content: "new turn", ts: None, sequence: None }],
    },
    ContentRendered(mounted=true),
    emit,
  )
  assert_true(sent.pinned)
  let (jumped, _) = grown.update(input, JumpToLatest, emit)
  assert_true(jumped.pinned)
  let (navigated, _) = grown.update(
    { ..input, active_session: "another-session" },
    ContentRendered(mounted=true),
    emit,
  )
  assert_true(navigated.pinned)
}

///|
test "an overview click unpins and highlights inside the component" {
  let key = @transcript_overview.Durable(3)
  let input = Input(
    focused=Local,
    active_session="desktop-test",
    items=[],
    streaming_response="",
    subruns=[],
  )
  let state : Model = {
    pinned: true,
    overview: @transcript_overview.State::empty(),
    focused: Local,
    active_session: "desktop-test",
    item_count: 0,
    mounted: true,
  }
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (next, _) = state.update(input, Overview(Clicked(key)), emit)
  assert_false(next.pinned)
  @debug.assert_eq(next.overview.active, Some(key))
}

///|
test "a conversation switch clears component-owned overview state" {
  let input = Input(
    focused=Local,
    active_session="desktop-test",
    items=[],
    streaming_response="",
    subruns=[],
  )
  let state : Model = {
    pinned: false,
    overview: {
      hover: Some({
        key: @transcript_overview.Durable(2),
        flip: false,
        anchor: 0,
      }),
      active: Some(@transcript_overview.Durable(3)),
    },
    focused: Local,
    active_session: "desktop-test",
    item_count: 0,
    mounted: true,
  }
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (next, _) = state.update(
    { ..input, active_session: "desktop-other" },
    ContentRendered(mounted=true),
    emit,
  )
  assert_true(next.pinned)
  @debug.assert_eq(next.overview.hover, None)
  @debug.assert_eq(next.overview.active, None)
  let (removed, _) = state.update(input, ContentRendered(mounted=false), emit)
  let (remounted, _) = removed.update(
    input,
    ContentRendered(mounted=true),
    emit,
  )
  assert_false(removed.mounted)
  assert_true(remounted.mounted)
  assert_true(remounted.pinned)
  @debug.assert_eq(remounted.overview.hover, None)
  @debug.assert_eq(remounted.overview.active, None)
}
