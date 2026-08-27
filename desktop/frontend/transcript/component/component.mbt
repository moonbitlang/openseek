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
  let ordinals : Map[Int, Int] = Map([])
  for index, item in items {
    let identity = match item.sequence {
      Some(sequence) => {
        let ordinal = ordinals.get(sequence).unwrap_or(0)
        ordinals.set(sequence, ordinal + 1)
        "s\{sequence}\u{0}o\{ordinal}"
      }
      None => "l\{index}"
    }
    rows.push({ item, identity, })
  }
  rows
}

///|
/// The conversation data rendered by the component. The application computes
/// durable chronology and active-run ownership; this package owns the live
/// reasoning preview, transcript subtree, and scroll behavior.
struct Input {
  source : Source
  focused : @interop.ChannelId
  active_session : String
  // The open engine run whose live reasoning this transcript may render.
  // Durable rows need no run id; this identity only keeps concurrent live
  // previews on separate conversations from replacing one another.
  active_run_id : String?
  // The concrete project or worktree root sent alongside relative Markdown
  // image paths so the owning host, rather than the frontend, resolves them.
  root : @common.Uri?
  submission_generation : Int
  items : Array[VisibleRow]
  // The in-flight assistant text to show below the committed rows, or `None`
  // when nothing is streaming. It is deliberately not a `VisibleRow`: the
  // rows are the durable record and this is not durable yet.
  streaming_response : String?
  streaming_identity : String
} derive(Eq)

///|
pub fn Input::Input(
  source~ : Source,
  focused~ : @interop.ChannelId,
  active_session~ : String,
  active_run_id? : String,
  root~ : @common.Uri?,
  submission_generation~ : Int,
  items~ : Array[VisibleRow],
  streaming_response~ : String?,
  streaming_identity~ : String,
) -> Input {
  {
    source,
    focused,
    active_session,
    active_run_id,
    root,
    submission_generation,
    items,
    streaming_response,
    streaming_identity,
  }
}

///|
/// One live reasoning stream's exact owner. Session ids are scoped by their
/// device channel, and separate runs of one session must never share text.
priv struct LiveReasoningKey {
  channel : @interop.ChannelId
  session : String
  run_id : String?
} derive(Eq)

///|
fn LiveReasoningKey::matches_input(
  self : LiveReasoningKey,
  input : Input,
) -> Bool {
  input.source is OpenSeek &&
  self.channel == input.focused &&
  self.session == input.active_session &&
  self.run_id == input.active_run_id
}

///|
fn LiveReasoningKey::wire(self : LiveReasoningKey) -> String {
  self.channel.uri_authority() +
  "\u{0}" +
  self.session +
  "\u{0}" +
  self.run_id.unwrap_or("")
}

///|
priv struct LiveReasoningPreview {
  key : LiveReasoningKey
  // Keep provider fragments separate. Appending is O(1); the full string is
  // materialized only when a durable render or remount asks to hydrate the
  // visible DOM widget.
  chunks : @vector.Vector[String]
} derive(Eq)

///|
fn LiveReasoningPreview::content(self : LiveReasoningPreview) -> String {
  let out = StringBuilder()
  for chunk in self.chunks {
    out.write_string(chunk)
  }
  out.to_string()
}

///|
/// The OpenSeek conversation currently allowed to use the one visible host.
/// `step_label` is presentation data derived from durable transcript rows; it
/// does not participate in routing provider fragments.
priv struct LiveReasoningTarget {
  key : LiveReasoningKey
  step_label : String
} derive(Eq)

///|
fn Input::live_reasoning_target(self : Input) -> LiveReasoningTarget? {
  guard self.source is OpenSeek else { return None }
  Some({
    key: {
      channel: self.focused,
      session: self.active_session,
      run_id: self.active_run_id,
    },
    step_label: "#\{durable_step_ordinals(self.items).length() + 1}",
  })
}

///|
/// Whether this component may still accept transient events from one concrete
/// bridge connection. Keeping the last epoch after a close prevents callbacks
/// already queued by that connection from recreating a cleared preview.
priv enum LiveReasoningConnectionPhase {
  Receiving
  Closed
} derive(Eq)

///|
/// The latest bridge connection observed for one device channel. Epochs are
/// monotonic within a channel; a replacement connection therefore fences both
/// late reasoning fragments and a late close callback from its predecessor.
priv struct LiveReasoningConnection {
  channel : @interop.ChannelId
  websocket_epoch : Int
  phase : LiveReasoningConnectionPhase
} derive(Eq)

///|
/// Component-owned previews for every concurrently running conversation.
/// Both vectors are persistent, so a background connection or run cannot
/// mutate a state snapshot currently being rendered for the foreground.
priv struct LiveReasoningState {
  connections : @vector.Vector[LiveReasoningConnection]
  previews : @vector.Vector[LiveReasoningPreview]
  active : LiveReasoningTarget?
} derive(Eq)

///|
priv enum LiveReasoningMsg {
  Focused(LiveReasoningTarget?)
  ConnectionOpened(@interop.ChannelId, websocket_epoch~ : Int)
  Delta(LiveReasoningKey, websocket_epoch~ : Int, String)
  Finished(LiveReasoningKey, websocket_epoch~ : Int)
  RunFinished(@interop.ChannelId, websocket_epoch~ : Int, String)
  ConnectionClosed(@interop.ChannelId, websocket_epoch~ : Int)
}

///|
/// The only effects allowed out of the live state machine. They update one
/// browser-owned text node and never produce a Rabbita `Val[Html]`.
priv enum LiveReasoningEffect {
  None
  Sync(target~ : String, step_label~ : String, content~ : String)
  Append(target~ : String, content~ : String)
  Hide(target~ : String)
  Reset
} derive(Eq, Debug)

///|
fn LiveReasoningEffect::apply(
  self : LiveReasoningEffect,
  preview : @live_preview.LivePreview,
) -> Unit {
  match self {
    None => ()
    Sync(target~, step_label~, content~) =>
      preview.sync(target, step_label, content)
    Append(target~, content~) => preview.append(target, content)
    Hide(target~) => preview.hide(target)
    Reset => preview.reset()
  }
}

///|
fn LiveReasoningState::preview_for(
  self : LiveReasoningState,
  key : LiveReasoningKey,
) -> LiveReasoningPreview? {
  for preview in self.previews {
    if preview.key == key {
      return Some(preview)
    }
  }
  None
}

///|
fn LiveReasoningState::sync_effect(
  self : LiveReasoningState,
  target : LiveReasoningTarget?,
) -> LiveReasoningEffect {
  match target {
    None => Reset
    Some(target) =>
      Sync(
        target=target.key.wire(),
        step_label=target.step_label,
        content=self
          .preview_for(target.key)
          .map(preview => preview.content())
          .unwrap_or(""),
      )
  }
}

///|
fn LiveReasoningState::accepts(
  self : LiveReasoningState,
  channel : @interop.ChannelId,
  websocket_epoch : Int,
) -> Bool {
  for connection in self.connections {
    if connection.channel == channel {
      return connection.websocket_epoch == websocket_epoch &&
        connection.phase is Receiving
    }
  }
  false
}

///|
fn LiveReasoningState::update(
  self : LiveReasoningState,
  msg : LiveReasoningMsg,
) -> (LiveReasoningState, LiveReasoningEffect) {
  match msg {
    Focused(target) => {
      let next = { ..self, active: target }
      // Always re-sync, even when the logical target is unchanged: the host
      // may have been remounted while another application screen was visible.
      (next, next.sync_effect(target))
    }
    ConnectionOpened(channel, websocket_epoch~) => {
      for index in 0..<self.connections.length() {
        let current = self.connections[index]
        if current.channel == channel {
          // A connection command can finish after its replacement was
          // installed. Never move this component's fence backwards.
          if websocket_epoch < current.websocket_epoch {
            return (self, None)
          }
          let next = {
            ..self,
            connections: self.connections.set(index, {
              channel,
              websocket_epoch,
              phase: Receiving,
            }),
            // `agent.connected` can repeat without a WebSocket replacement
            // when the engine pump restarts. Its transient fragments are no
            // more replayable than fragments across a transport reconnect.
            previews: self.previews.filter(preview => {
              preview.key.channel != channel
            }),
          }
          return (
            next,
            if self.active is Some(active) && active.key.channel == channel {
              Hide(target=active.key.wire())
            } else {
              None
            },
          )
        }
      }
      let next = {
        ..self,
        connections: self.connections.push({
          channel,
          websocket_epoch,
          phase: Receiving,
        }),
        previews: self.previews.filter(preview => preview.key.channel != channel),
      }
      (
        next,
        if self.active is Some(active) && active.key.channel == channel {
          Hide(target=active.key.wire())
        } else {
          None
        },
      )
    }
    Delta(key, websocket_epoch~, content) => {
      if !self.accepts(key.channel, websocket_epoch) || content.is_empty() {
        return (self, None)
      }
      for index in 0..<self.previews.length() {
        if self.previews[index].key == key {
          let next = {
            ..self,
            previews: self.previews.set(index, {
              key,
              chunks: self.previews[index].chunks.push(content),
            }),
          }
          return (
            next,
            if self.active is Some(active) && active.key == key {
              Append(target=key.wire(), content~)
            } else {
              None
            },
          )
        }
      }
      let next = {
        ..self,
        previews: self.previews.push({
          key,
          chunks: @vector.new().push(content),
        }),
      }
      (
        next,
        if self.active is Some(active) && active.key == key {
          Append(target=key.wire(), content~)
        } else {
          None
        },
      )
    }
    Finished(key, websocket_epoch~) =>
      if self.accepts(key.channel, websocket_epoch) {
        (
          {
            ..self,
            previews: self.previews.filter(preview => preview.key != key),
          },
          if self.active is Some(active) && active.key == key {
            Hide(target=key.wire())
          } else {
            None
          },
        )
      } else {
        (self, None)
      }
    RunFinished(channel, websocket_epoch~, run_id) =>
      if self.accepts(channel, websocket_epoch) {
        let next = {
          ..self,
          previews: self.previews.filter(preview => {
            preview.key.channel != channel || preview.key.run_id != Some(run_id)
          }),
        }
        (
          next,
          if self.active is Some(active) &&
            active.key.channel == channel &&
            active.key.run_id == Some(run_id) {
            Hide(target=active.key.wire())
          } else {
            None
          },
        )
      } else {
        (self, None)
      }
    ConnectionClosed(channel, websocket_epoch~) => {
      for index in 0..<self.connections.length() {
        let current = self.connections[index]
        if current.channel == channel &&
          current.websocket_epoch == websocket_epoch {
          if current.phase is Closed {
            return (self, None)
          }
          let next = {
            ..self,
            connections: self.connections.set(index, {
              ..current,
              phase: Closed,
            }),
            previews: self.previews.filter(preview => {
              preview.key.channel != channel
            }),
          }
          return (
            next,
            if self.active is Some(active) && active.key.channel == channel {
              Hide(target=active.key.wire())
            } else {
              None
            },
          )
        }
      }
      (self, None)
    }
  }
}

///|
/// State-only projection used by reducer tests that are not inspecting the DOM
/// effect of a transition.
fn LiveReasoningState::transition(
  self : LiveReasoningState,
  msg : LiveReasoningMsg,
) -> LiveReasoningState {
  self.update(msg).0
}

///|
fn LiveReasoningState::content_for(
  self : LiveReasoningState,
  input : Input,
) -> String? {
  for preview in self.previews {
    if preview.key.matches_input(input) {
      return Some(preview.content())
    }
  }
  None
}

///|
/// The transcript component's live-reasoning controller. It deliberately is
/// not a Rabbita state: Rabbita flushes the root VDOM after every scheduled
/// command, even when no rendered value depends on that state. Bridge callbacks
/// mutate this controller directly so a delta cannot schedule a root diff.
struct LiveReasoning {
  mut state : LiveReasoningState
  preview : @live_preview.LivePreview
}

///|
pub fn LiveReasoning::LiveReasoning() -> LiveReasoning {
  {
    state: { connections: @vector.new(), previews: @vector.new(), active: None },
    preview: @live_preview.LivePreview(),
  }
}

///|
/// Apply one bridge event synchronously on the browser main thread. WebSocket,
/// Proton, and animation-frame callbacks are all serialized by that thread, so
/// this mutable controller needs no second queue or Rabbita emitter.
fn LiveReasoning::apply(self : LiveReasoning, msg : LiveReasoningMsg) -> Unit {
  let (state, effect) = self.state.update(msg)
  self.state = state
  effect.apply(self.preview)
}

///|
/// Select the conversation allowed to occupy the stable preview host. The
/// command also rehydrates a newly mounted host from stored fragments and
/// synchronizes the transcript's current scroll ownership before observing
/// that content.
pub fn LiveReasoning::focus(
  self : LiveReasoning,
  input : Input,
  pinned : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      self.preview.set_pinned(pinned)
      self.apply(Focused(input.live_reasoning_target()))
    },
    kind=@cmd.after_render,
  )
}

///|
/// Cache a real transcript scroll transition without scheduling a Rabbita
/// render. This is called by the transcript's capture-phase scroll listener.
pub fn LiveReasoning::set_pinned(self : LiveReasoning, pinned : Bool) -> Unit {
  self.preview.set_pinned(pinned)
}

///|
/// Start accepting transient events from this concrete bridge connection.
/// Repeating the same epoch is also the engine-pump restart boundary, so its
/// pre-restart preview is discarded before new fragments arrive.
pub fn LiveReasoning::connection_opened(
  self : LiveReasoning,
  channel : @interop.ChannelId,
  websocket_epoch : Int,
) -> Unit {
  self.apply(ConnectionOpened(channel, websocket_epoch~))
}

///|
/// Append one ordered provider fragment to its conversation's preview.
pub fn LiveReasoning::delta(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  websocket_epoch~ : Int,
  session~ : String,
  run_id~ : String?,
  content~ : String,
) -> Unit {
  self.apply(Delta({ channel, session, run_id }, websocket_epoch~, content))
}

///|
/// The full semantic reasoning event closes the preview unconditionally.
/// Its durable Assistant commit, whenever observed, is the only history row.
pub fn LiveReasoning::finish(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  websocket_epoch~ : Int,
  session~ : String,
  run_id~ : String?,
) -> Unit {
  self.apply(Finished({ channel, session, run_id }, websocket_epoch~))
}

///|
/// Clear an abnormally closed run even when no semantic finish was emitted.
pub fn LiveReasoning::finish_run(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  websocket_epoch~ : Int,
  run_id~ : String,
) -> Unit {
  self.apply(RunFinished(channel, websocket_epoch~, run_id))
}

///|
/// Stop accepting events from this exact connection and discard its previews.
/// A stale close is ignored after a newer epoch has taken ownership.
pub fn LiveReasoning::connection_closed(
  self : LiveReasoning,
  channel : @interop.ChannelId,
  websocket_epoch : Int,
) -> Unit {
  self.apply(ConnectionClosed(channel, websocket_epoch~))
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
  // Reconcile the browser-owned preview only after the transcript reports its
  // durable DOM. The callback computes a small target before creating a Cmd;
  // the full `Input` is never stored in live state.
  focus_live_reasoning : (Input, Bool) -> @cmd.Cmd
  // Scroll events are already browser effects. Feed their settled state to
  // the browser-owned preview directly so delta frames only append text.
  live_reasoning_pinned : (Bool) -> Unit
}

///|
/// Apply an explicit component pin transition after its Html has settled.
/// Scroll events use the direct callback above; buttons and remounts use this
/// command so Model::update remains pure.
fn Actions::pin_live_reasoning_after_render(
  self : Actions,
  pinned : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => (self.live_reasoning_pinned)(pinned),
    kind=@cmd.after_render,
  )
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
  focus_live_reasoning? : (Input, Bool) -> @cmd.Cmd = (_, _) => @cmd.none,
  pin_live_reasoning? : (Bool) -> @cmd.Cmd = _ => @cmd.none,
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
          pin_live_reasoning(true),
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
      if mounted {
        // Durable rows, target identity, and host remounts all arrive through
        // this one notification. Live DOM mutations are excluded from the
        // observer below, so a reasoning delta cannot feed back into update.
        commands.push(focus_live_reasoning(input, next.pinned))
      }
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
          (
            { ..next, pinned: false },
            @cmd.batch([
              pin_live_reasoning(false),
              scroll_turn_into_view(emit, key),
            ]),
          )
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
    update=(state, input, msg, emit) => {
      state.update(
        input,
        msg,
        emit,
        focus_live_reasoning=actions.focus_live_reasoning,
        pin_live_reasoning=pinned => {
          actions.pin_live_reasoning_after_render(pinned)
        },
      )
    },
    subscriptions=(_, _, emit) => {
      transcript_subscription(emit, actions.live_reasoning_pinned)
    },
  )
  state.view2(input, (state, input) => {
    transcript_view(
      input,
      pinned=state.pinned,
      overview=state.overview,
      overview_emit=emit.map(msg => Overview(msg)),
      path => (actions.open)(path),
      target => (actions.jump)(target),
      session => (actions.open_session)(session),
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
  TranscriptSubscription(@cmd.Emit[Msg], (Bool) -> Unit)
}

///|
/// Scroll position and rendered-content growth are DOM signals owned by the
/// transcript. Keeping both in this component means the application no longer
/// forwards a synthetic "content changed" message into child state.
fn transcript_subscription(
  emit : @cmd.Emit[Msg],
  live_reasoning_pinned : (Bool) -> Unit,
) -> @sub.Sub {
  @sub.custom_sub(
    "transcript-dom",
    @sub.Local,
    TranscriptSubscription(emit, live_reasoning_pinned),
    transcript_sub_loader,
  )
}

///|
fn transcript_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    TranscriptSubscription(emit, live_reasoning_pinned) => {
      let mut emit = emit
      let mut live_reasoning_pinned = live_reasoning_pinned
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
        // This callback updates only the browser-owned preview controller. It
        // must run before any Rabbita message so a queued delta observes the
        // user's latest decision to follow or read history.
        live_reasoning_pinned(pinned)
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
          guard payload is TranscriptSubscription(next, next_pinned) else {
            return
          }
          emit = next
          live_reasoning_pinned = next_pinned
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
    // Observe identity on the transcript root, but observe content only below
    // the durable `#stream`. The sibling live-preview host is mutated for each
    // delta and must never emit `ContentRendered` back into this component.
    observer.observe(element.as_node(), attributes=true, attribute_filter=[
      "data-transcript-source", "data-transcript-channel", "data-transcript-session",
      "data-transcript-run", "data-transcript-root", "data-transcript-submission",
    ])
    if element.query_selector("#stream") is Some(stream) {
      observer.observe(
        stream.as_node(),
        child_list=true,
        character_data=true,
        subtree=true,
      )
    }
  }
}

///|
fn TranscriptDomMount::observe_resize(
  self : Self,
  observer : @dom.ResizeObserver,
) -> Unit {
  if self.element is Some(element) {
    // The live-reasoning host is a sibling of `#stream`. Observing the whole
    // transcript would turn each preview line wrap into `ContentRendered`,
    // feeding transient DOM growth back through the component render loop.
    // Durable rows, images, and diagrams all live under `#stream`, so it is
    // the resize boundary this component actually owns.
    if element.query_selector("#stream") is Some(stream) {
      observer.observe(stream)
    }
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
          item: { kind: User, content: "new turn", ts: None, sequence: None, },
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
test "live reasoning appends by owner and semantic finish deletes it" {
  let epoch = 7
  let key : LiveReasoningKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
    run_id: Some("r7"),
  }
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    active_run_id="r7",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="r7",
  )
  let empty = LiveReasoningState::{
    connections: @vector.new(),
    previews: @vector.new(),
    active: None,
  }
  let connected = empty.transition(
    ConnectionOpened(@interop.ChannelId::Local, websocket_epoch=epoch),
  )
  let target = input.live_reasoning_target()
  let (focused, focus_effect) = connected.update(Focused(target))
  assert_eq(focus_effect, Sync(target=key.wire(), step_label="#1", content=""))
  let (first, first_effect) = focused.update(
    Delta(key, websocket_epoch=epoch, "think"),
  )
  assert_eq(first_effect, Append(target=key.wire(), content="think"))
  let (live, second_effect) = first.update(
    Delta(key, websocket_epoch=epoch, "ing"),
  )
  assert_eq(second_effect, Append(target=key.wire(), content="ing"))
  assert_eq(live.content_for(input), Some("thinking"))
  let (_, hydrate_effect) = live.update(Focused(target))
  assert_eq(
    hydrate_effect,
    Sync(target=key.wire(), step_label="#1", content="thinking"),
  )

  // The full reasoning event is a semantic boundary, not a durable commit.
  // Removing the preview here makes both commit-first and finish-first delivery
  // converge without comparing the reasoning text with transcript history.
  let (finished, finish_effect) = live.update(
    Finished(key, websocket_epoch=epoch),
  )
  assert_eq(finished.content_for(input), None)
  assert_eq(finish_effect, Hide(target=key.wire()))

  // Updating the same immutable snapshot twice must produce the same result;
  // an emitter may replay a state transition while scheduling a render.
  assert_true(
    focused.update(Delta(key, websocket_epoch=epoch, "think")) ==
    focused.update(Delta(key, websocket_epoch=epoch, "think")),
  )
}

///|
test "live reasoning keeps concurrent conversations and runs isolated" {
  let epoch = 7
  let local_r7 : LiveReasoningKey = {
    channel: @interop.ChannelId::Local,
    session: "shared",
    run_id: Some("r7"),
  }
  let local_r8 : LiveReasoningKey = {
    channel: @interop.ChannelId::Local,
    session: "shared",
    run_id: Some("r8"),
  }
  let remote_r7 : LiveReasoningKey = {
    channel: @interop.ChannelId::Remote("device-b"),
    session: "shared",
    run_id: Some("r7"),
  }
  let state = LiveReasoningState::{
      connections: @vector.new(),
      previews: @vector.new(),
      active: None,
    }
    .transition(
      ConnectionOpened(@interop.ChannelId::Local, websocket_epoch=epoch),
    )
    .transition(
      ConnectionOpened(
        @interop.ChannelId::Remote("device-b"),
        websocket_epoch=epoch,
      ),
    )
    .transition(Delta(local_r7, websocket_epoch=epoch, "local-old"))
    .transition(Delta(local_r8, websocket_epoch=epoch, "local-current"))
    .transition(Delta(remote_r7, websocket_epoch=epoch, "remote"))
  let local_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="shared",
    active_run_id="r8",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="r8",
  )
  let remote_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Remote("device-b"),
    active_session="shared",
    active_run_id="r7",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="r7",
  )
  assert_eq(state.content_for(local_input), Some("local-current"))
  assert_eq(state.content_for(remote_input), Some("remote"))

  let (focused, focus_effect) = state.update(
    Focused(local_input.live_reasoning_target()),
  )
  assert_eq(
    focus_effect,
    Sync(target=local_r8.wire(), step_label="#1", content="local-current"),
  )
  let (with_background, background_effect) = focused.update(
    Delta(remote_r7, websocket_epoch=epoch, "-more"),
  )
  assert_eq(background_effect, None)
  assert_eq(with_background.content_for(remote_input), Some("remote-more"))

  let after_run = with_background.transition(
    RunFinished(@interop.ChannelId::Local, websocket_epoch=epoch, "r7"),
  )
  assert_eq(after_run.content_for(local_input), Some("local-current"))
  assert_eq(after_run.content_for(remote_input), Some("remote-more"))

  let after_channel = after_run.transition(
    ConnectionClosed(
      @interop.ChannelId::Remote("device-b"),
      websocket_epoch=epoch,
    ),
  )
  assert_eq(after_channel.content_for(local_input), Some("local-current"))
  assert_eq(after_channel.content_for(remote_input), None)
}

///|
test "live reasoning rejects stale connection callbacks" {
  let channel = @interop.ChannelId::Remote("device-b")
  let key : LiveReasoningKey = {
    channel,
    session: "desktop-test",
    run_id: Some("r7"),
  }
  let input = Input(
    source=OpenSeek,
    focused=channel,
    active_session="desktop-test",
    active_run_id="r7",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="r7",
  )
  let empty = LiveReasoningState::{
    connections: @vector.new(),
    previews: @vector.new(),
    active: None,
  }
  let current = empty
    .transition(ConnectionOpened(channel, websocket_epoch=1))
    .transition(Delta(key, websocket_epoch=1, "old"))
    .transition(ConnectionOpened(channel, websocket_epoch=2))
    .transition(Delta(key, websocket_epoch=2, "current"))

  // Both callbacks belong to the replaced socket. Neither may change the
  // current preview, even if JavaScript queued them before the replacement.
  let after_stale = current
    .transition(ConnectionOpened(channel, websocket_epoch=1))
    .transition(Delta(key, websocket_epoch=1, "-stale"))
    .transition(ConnectionClosed(channel, websocket_epoch=1))
  assert_eq(after_stale.content_for(input), Some("current"))

  // The current close clears once and keeps the epoch fenced, so a delta
  // already queued by the closed socket cannot recreate the preview.
  let closed = after_stale
    .transition(ConnectionClosed(channel, websocket_epoch=2))
    .transition(Delta(key, websocket_epoch=2, "late"))
  assert_eq(closed.content_for(input), None)
  assert_true(
    after_stale.transition(ConnectionClosed(channel, websocket_epoch=2)) ==
    after_stale.transition(ConnectionClosed(channel, websocket_epoch=2)),
  )

  // `agent.connected` can reopen the engine pump without replacing the
  // WebSocket. The same epoch becomes receiving again, starting from empty.
  let reopened = closed
    .transition(ConnectionOpened(channel, websocket_epoch=2))
    .transition(Delta(key, websocket_epoch=2, "fresh"))
  assert_eq(reopened.content_for(input), Some("fresh"))
}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend VisibleRow with Eq::{equal, not_equal}
