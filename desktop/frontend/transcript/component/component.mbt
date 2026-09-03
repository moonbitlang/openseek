///|
/// Which conversation source supplied the normalized rows. The component uses
/// this for source-specific labels, empty-state copy, and renderer identity.
pub(all) enum Source {
  OpenSeek
  Codex
} derive(Eq)

///|
fn Source::wire(self : Source) -> String {
  match self {
    OpenSeek => "openseek"
    Codex => "codex"
  }
}

///|
/// One visible transcript item paired with the stable identity used by keyed
/// reconciliation. The identity is opaque to the component's callers and is
/// never emitted as a DOM id or attribute.
pub(all) struct VisibleRow {
  item : @transcript.TranscriptItem
  identity : String
} derive(Eq)

///|
/// Give app-server history stable identities without making its owning
/// package depend on the renderer's private key format.
pub fn VisibleRow::history(
  items : Array[@transcript.TranscriptItem],
) -> Array[VisibleRow] {
  let rows : Array[VisibleRow] = []
  for index, item in items {
    let identity = match item.sequence {
      Some(sequence) => "s\{sequence}"
      None => "l\{index}"
    }
    rows.push({ item, identity, })
  }
  rows
}

///|
/// The conversation data rendered by the component. The application computes
/// durable chronology and active-run ownership; this package owns only the
/// transcript subtree and its scroll behavior.
struct Input {
  source : Source
  focused : @interop.ChannelId
  active_session : String
  // The concrete project or worktree root sent alongside relative Markdown
  // image paths so the owning host, rather than the frontend, resolves them.
  root : @common.Uri?
  submission_generation : Int
  items : Array[VisibleRow]
  // The in-flight assistant text to show below the committed rows, or `None`
  // when nothing is streaming. It is deliberately not a `VisibleRow`: the
  // rows are the durable record and this is not durable yet.
  streaming_response : String?
  // Live reasoning is likewise provisional. It is plain text until complete;
  // the durable response replaces it and renders Markdown once.
  streaming_reasoning : String?
  reasoning_complete : Bool
  streaming_identity : String
} derive(Eq)

///|
pub fn Input::Input(
  source~ : Source,
  focused~ : @interop.ChannelId,
  active_session~ : String,
  root~ : @common.Uri?,
  submission_generation~ : Int,
  items~ : Array[VisibleRow],
  streaming_response~ : String?,
  streaming_reasoning? : String,
  reasoning_complete? : Bool = false,
  streaming_identity~ : String,
) -> Input {
  {
    source,
    focused,
    active_session,
    root,
    submission_generation,
    items,
    streaming_response,
    streaming_reasoning,
    reasoning_complete,
    streaming_identity,
  }
}

///|
/// Parent-owned actions used by links in the transcript. They are captured by
/// the component construction and never stored in its Model.
pub(all) struct Actions {
  open : @cmd.Emit[String]
  jump : @cmd.Emit[@mention_context.Target]
  /// Open another session's transcript. Used by a sub-run tool card to reach
  /// the child transcript it names.
  open_session : @cmd.Emit[String]
}

///|
priv struct Model {
  pinned : Bool
  overview : @transcript_overview.State
  source : Source
  focused : @interop.ChannelId
  active_session : String
  image_owner : ImageOwner
  images : ImageCache
  submission_generation : Int
  mounted : Bool
} derive(Eq)

///|
priv enum Msg {
  Pinned(Bool)
  JumpToLatest
  ContentRendered(mounted~ : Bool)
  ImageRequested(String)
  ImageResolved(ImageOwner, String, ImageReadResult)
  Overview(@transcript_overview.Msg)
}

///|
fn Model::update(
  self : Model,
  input : Input,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  // A conversation switch can reach the component through input before its
  // DOM mutation notification. Never project the previous owner's data URLs
  // into that intermediate render.
  let image_owner = input.image_owner()
  let self = if self.image_owner == image_owner {
    self
  } else {
    { ..self, image_owner, images: ImageCache::empty(), }
  }
  match msg {
    Pinned(pinned) => ({ ..self, pinned, }, @cmd.none)
    JumpToLatest =>
      (
        { ..self, pinned: true, },
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
        self.source != input.source ||
        self.focused != input.focused ||
        self.active_session != input.active_session
      // Submission generation changes synchronously when Send accepts either
      // a prompt or a steer, before its durable User item arrives. Re-pin on
      // that explicit signal so early streamed work is immediately visible;
      // another client's later User item must not impersonate a local send.
      let submitted = !navigated &&
        input.submission_generation != self.submission_generation
      let pinned = navigated || submitted || self.pinned
      let next = {
        pinned,
        overview: if navigated {
          @transcript_overview.State::empty()
        } else {
          self.overview
        },
        source: input.source,
        focused: input.focused,
        active_session: input.active_session,
        image_owner,
        images: self.images,
        submission_generation: input.submission_generation,
        mounted,
      }
      let commands : Array[@cmd.Cmd] = []
      if pinned {
        commands.push(scroll_after_render())
      }
      commands.push(
        report_visible_turn_after_render(emit, skip_unchanged=!navigated),
      )
      commands.push(self.images.apply_after_render())
      (next, @cmd.batch(commands))
    }
    ImageRequested(path) => {
      let (images, command) = self.images.begin_read(image_owner, path, emit)
      ({ ..self, images, }, @cmd.batch([command, images.apply_after_render()]))
    }
    ImageResolved(owner, path, result) => {
      guard owner == image_owner else { return (self, @cmd.none) }
      let images = self.images.settle(path, result)
      ({ ..self, images, }, images.apply_after_render())
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
          ({ ..next, pinned: false, }, scroll_turn_into_view(emit, key))
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
          source: input.source,
          focused: input.focused,
          active_session: input.active_session,
          image_owner: input.image_owner(),
          images: ImageCache::empty(),
          submission_generation: input.submission_generation,
          mounted: false,
        },
        @cmd.none,
      )
    },
    update=(state, input, msg, emit) => state.update(input, msg, emit),
    subscriptions=(_, _, emit) => transcript_subscription(emit),
  )
  // Every stream child renders in its own branch, keyed by the block within
  // its stream. A streaming delta then recomputes only the live block's Html;
  // each settled row keeps the Html it already has, so the cost of a delta no
  // longer grows with the length of the transcript.
  let blocks = input.map(stream_blocks)
  let rendered = blocks.assoc_by(
    (_, block) => block.map(block => (block.key.wire(), block.render(actions))),
    by=block => block.branch_key(),
  )
  state.view3(input, rendered, (state, input, rendered) => {
    transcript_view(
      input,
      pinned=state.pinned,
      overview=state.overview,
      overview_emit=emit.map(msg => Overview(msg)),
      stream=keyed_stream(rendered),
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
      let client_height = transcript.get_client_height()
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
        let client_height = element.get_client_height()
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
      let observers = TranscriptObservers::install(
        mounted => scheduler.add(emit(ContentRendered(mounted~))),
        path => scheduler.add(emit(ImageRequested(path))),
      )
      Some({
        unload: _ => {
          target.remove_event_listener_with_options(
            "scroll",
            listener,
            capture=true,
          )
          observers.disconnect()
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
/// Observe the transcript through Rabbita's typed DOM bindings. The document
/// observer only follows mount/replacement; content and identity changes are
/// observed directly on the current transcript, so unrelated page mutations
/// cannot feed back into component updates.
priv struct TranscriptObservers {
  document : @dom.MutationObserver
  content : @dom.MutationObserver
  resize : @dom.ResizeObserver
  mount : TranscriptDomMount
}

///|
/// Owns the browser state borrowed from the currently mounted transcript DOM
/// element. Diagram controls and local-image observation stay outside the
/// Rabbita Model and are disposed before replacement or subscription unload.
priv struct TranscriptDomMount {
  mut element : @dom.Element?
  mut diagrams : @diagram_viewport.DiagramViewports?
  images : TranscriptImageObserver
  on_size_changed : () -> Unit
}

///|
fn TranscriptDomMount::TranscriptDomMount(
  on_size_changed : () -> Unit,
  on_image : (String) -> Unit,
) -> Self {
  {
    element: None,
    diagrams: None,
    images: TranscriptImageObserver::install(on_image),
    on_size_changed,
  }
}

///|
fn TranscriptDomMount::is_same_element(
  self : Self,
  next : @dom.Element?,
) -> Bool {
  match (self.element, next) {
    (None, None) => true
    (Some(previous), Some(element)) => previous.is_same_node(element.as_node())
    _ => false
  }
}

///|
/// Replace the borrowed transcript root. Mount the shared controller before
/// observation resumes so its initial toolbar DOM does not feed back as a
/// transcript content change. The image observer scans only this mounted root
/// and requests a bounded host read once an image enters the viewport.
fn TranscriptDomMount::replace(self : Self, next : @dom.Element?) -> Unit {
  self.images.disconnect()
  if self.diagrams is Some(diagrams) {
    diagrams.dispose()
  }
  self.diagrams = None
  self.element = next
  if next is Some(element) {
    self.diagrams = Some(
      @diagram_viewport.DiagramViewports(element, self.on_size_changed),
    )
    self.images.scan(element)
  }
}

///|
fn TranscriptDomMount::refresh_content(self : Self) -> Unit {
  if self.diagrams is Some(diagrams) {
    diagrams.refresh()
  }
  if self.element is Some(element) {
    self.images.scan(element)
  }
}

///|
fn TranscriptDomMount::observe_content(
  self : Self,
  observer : @dom.MutationObserver,
) -> Unit {
  if self.element is Some(element) {
    observer.observe(
      element.as_node(),
      attributes=true,
      child_list=true,
      character_data=true,
      subtree=true,
      attribute_filter=[
        "data-transcript-source", "data-transcript-channel", "data-transcript-session",
        "data-transcript-root", "data-transcript-submission",
      ],
    )
  }
}

///|
fn TranscriptDomMount::observe_resize(
  self : Self,
  observer : @dom.ResizeObserver,
) -> Unit {
  if self.element is Some(element) {
    observer.observe(element)
  }
}

///|
fn TranscriptDomMount::dispose(self : Self) -> Unit {
  self.replace(None)
}

///|
fn TranscriptObservers::install(
  on_change : (Bool) -> Unit,
  on_image : (String) -> Unit,
) -> Self {
  let mount = TranscriptDomMount(() => on_change(true), on_image)
  let resize = @dom.ResizeObserver::new((_, _) => on_change(true))
  let content = @dom.MutationObserver::new((_, observer) => {
    // Reconciliation itself moves the SVG and installs toolbar nodes. Pause
    // this same observer while doing that so those owned mutations cannot
    // schedule a second component render.
    observer.disconnect()
    mount.refresh_content()
    mount.observe_content(observer)
    on_change(true)
  })
  let attach = () => {
    let next = @dom.document().get_element_by_id("transcript").to_option()
    guard !mount.is_same_element(next) else { return }
    content.disconnect()
    resize.disconnect()
    mount.replace(next)
    mount.observe_content(content)
    mount.observe_resize(resize)
    on_change(next is Some(_))
  }
  let document = @dom.MutationObserver::new((_, _) => attach())
  if @dom.document().get_document_element() is Some(root) {
    document.observe(root.as_node(), child_list=true, subtree=true)
  }
  // The component may already be mounted when its subscription starts.
  attach()
  { document, content, resize, mount, }
}

///|
fn TranscriptObservers::disconnect(self : Self) -> Unit {
  self.document.disconnect()
  self.content.disconnect()
  self.resize.disconnect()
  self.mount.dispose()
}

///|
test "local pinned transitions are pure" {
  let input = Input(
    source=OpenSeek,
    focused=Local,
    active_session="desktop-test",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="idle",
  )
  let state : Model = {
    pinned: true,
    overview: @transcript_overview.State::empty(),
    source: OpenSeek,
    focused: Local,
    active_session: "desktop-test",
    image_owner: input.image_owner(),
    images: ImageCache::empty(),
    submission_generation: 0,
    mounted: true,
  }
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (first, _) = state.update(input, Pinned(false), emit)
  let (second, _) = state.update(input, Pinned(false), emit)
  assert_false(first.pinned)
  assert_false(second.pinned)
  let (grown, _) = first.update(input, ContentRendered(mounted=true), emit)
  assert_false(grown.pinned)
  let (received, _) = first.update(
    {
      ..input,
      items: [
        {
          item: { kind: User("new turn"), ts: None, sequence: None, },
          identity: "l0",
        },
      ],
    },
    ContentRendered(mounted=true),
    emit,
  )
  assert_false(received.pinned)
  let (submitted, _) = first.update(
    { ..input, submission_generation: 1, },
    ContentRendered(mounted=true),
    emit,
  )
  assert_true(submitted.pinned)
  let (jumped, _) = grown.update(input, JumpToLatest, emit)
  assert_true(jumped.pinned)
  let (navigated, _) = grown.update(
    { ..input, active_session: "another-session", },
    ContentRendered(mounted=true),
    emit,
  )
  assert_true(navigated.pinned)
}

///|
test "an overview click unpins and highlights inside the component" {
  let key = @transcript_overview.Durable(3)
  let input = Input(
    source=OpenSeek,
    focused=Local,
    active_session="desktop-test",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="idle",
  )
  let state : Model = {
    pinned: true,
    overview: @transcript_overview.State::empty(),
    source: OpenSeek,
    focused: Local,
    active_session: "desktop-test",
    image_owner: input.image_owner(),
    images: ImageCache::empty(),
    submission_generation: 0,
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
    source=OpenSeek,
    focused=Local,
    active_session="desktop-test",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="idle",
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
    source: OpenSeek,
    focused: Local,
    active_session: "desktop-test",
    image_owner: input.image_owner(),
    images: ImageCache::empty(),
    submission_generation: 0,
    mounted: true,
  }
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (next, _) = state.update(
    { ..input, active_session: "desktop-other", },
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

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend VisibleRow with Eq::{equal, not_equal}
