///|
/// One live reasoning stream's exact owner. Session ids are scoped by their
/// device channel, and separate runs of one session must never share text.
priv struct LiveReasoningKey {
  channel : @interop.ChannelId
  session : String
  run_id : String
} derive(Eq)

///|
fn LiveReasoningKey::matches_input(
  self : LiveReasoningKey,
  input : Input,
) -> Bool {
  input.source is OpenSeek &&
  self.channel == input.focused &&
  self.session == input.active_session &&
  Some(self.run_id) == input.active_run_id
}

///|
/// The `switch_by` tag of a focus target: run identity plus the step label,
/// so a new step re-targets the preview with its own heading.
fn LiveReasoningTarget::key(self : LiveReasoningTarget) -> String {
  self.key.wire() + "\u{0}" + self.step_label
}

///|
fn LiveReasoningKey::wire(self : LiveReasoningKey) -> String {
  self.channel.uri_authority() + "\u{0}" + self.session + "\u{0}" + self.run_id
}

///|
priv struct LiveReasoningPreview {
  key : LiveReasoningKey
  // Keep provider fragments separate instead of copying the accumulated
  // text on every delta. Join them when rehydrating the visible widget or
  // handing a completed thought back to the ordinary transcript.
  chunks : @vector.Vector[String]
  complete : Bool
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
  guard self.source is OpenSeek && self.active_run_id is Some(run_id) else {
    return None
  }
  Some({
    key: { channel: self.focused, session: self.active_session, run_id, },
    step_label: "#\{self.items.filter(row => row.item.kind is Assistant(replay=false, ..)).length() + 1}",
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
  StepStarted(LiveReasoningKey, websocket_epoch~ : Int)
  RunFinished(@interop.ChannelId, websocket_epoch~ : Int, String)
  ConnectionClosed(@interop.ChannelId, websocket_epoch~ : Int)
}

///|
/// The only effects allowed out of the live state machine. They update one
/// browser-owned text node and never produce a Rabbita `Val[Html]`.
priv enum LiveReasoningEffect {
  NoChange
  Sync(target~ : String, step_label~ : String, content~ : String)
  Append(target~ : String, content~ : String)
  Hide(target~ : String)
  Reset
} derive(Eq, Debug)

///|
fn LiveReasoningEffect::apply(
  self : LiveReasoningEffect,
  preview : LivePreview,
) -> Unit {
  match self {
    NoChange => ()
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
    if preview.key == key && !preview.complete {
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
      let next = { ..self, active: target, }
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
            return (self, NoChange)
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
              NoChange
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
          NoChange
        },
      )
    }
    Delta(key, websocket_epoch~, content) => {
      if !self.accepts(key.channel, websocket_epoch) || content.is_empty() {
        return (self, NoChange)
      }
      for index in 0..<self.previews.length() {
        if self.previews[index].key == key {
          if self.previews[index].complete {
            return (self, NoChange)
          }
          let next = {
            ..self,
            previews: self.previews.set(index, {
              key,
              chunks: self.previews[index].chunks.push(content),
              complete: false,
            }),
          }
          return (
            next,
            if self.active is Some(active) && active.key == key {
              Append(target=key.wire(), content~)
            } else {
              NoChange
            },
          )
        }
      }
      let next = {
        ..self,
        previews: self.previews.push({
          key,
          chunks: @vector.new().push(content),
          complete: false,
        }),
      }
      (
        next,
        if self.active is Some(active) && active.key == key {
          Append(target=key.wire(), content~)
        } else {
          NoChange
        },
      )
    }
    StepStarted(key, websocket_epoch~) => {
      guard self.accepts(key.channel, websocket_epoch) else {
        return (self, NoChange)
      }
      (
        {
          ..self,
          previews: self.previews.filter(preview => preview.key != key),
        },
        if self.active is Some(active) && active.key == key {
          Hide(target=key.wire())
        } else {
          NoChange
        },
      )
    }
    Finished(key, websocket_epoch~) => {
      guard self.accepts(key.channel, websocket_epoch) else {
        return (self, NoChange)
      }
      for preview in self.previews {
        if preview.key == key && preview.complete {
          return (self, NoChange)
        }
      }
      // Retain a sealed entry until the next step. A delayed fragment must
      // not recreate a thought after its complete semantic event.
      (
        {
          ..self,
          previews: self.previews
          .filter(preview => preview.key != key)
          .push({ key, chunks: @vector.new(), complete: true, }),
        },
        if self.active is Some(active) && active.key == key {
          Hide(target=key.wire())
        } else {
          NoChange
        },
      )
    }
    RunFinished(channel, websocket_epoch~, run_id) =>
      if self.accepts(channel, websocket_epoch) {
        let next = {
          ..self,
          previews: self.previews.map(preview => {
            if preview.key.channel == channel && preview.key.run_id == run_id {
              { ..preview, chunks: @vector.new(), complete: true, }
            } else {
              preview
            }
          }),
        }
        (
          next,
          if self.active is Some(active) &&
            active.key.channel == channel &&
            active.key.run_id == run_id {
            Hide(target=active.key.wire())
          } else {
            NoChange
          },
        )
      } else {
        (self, NoChange)
      }
    ConnectionClosed(channel, websocket_epoch~) => {
      for index in 0..<self.connections.length() {
        let current = self.connections[index]
        if current.channel == channel &&
          current.websocket_epoch == websocket_epoch {
          if current.phase is Closed {
            return (self, NoChange)
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
              NoChange
            },
          )
        }
      }
      (self, NoChange)
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
    if preview.key.matches_input(input) && !preview.complete {
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
  preview : LivePreview
}

///|
pub fn LiveReasoning::LiveReasoning() -> LiveReasoning {
  {
    state: {
      connections: @vector.new(),
      previews: @vector.new(),
      active: None,
    },
    preview: LivePreview(),
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
priv suberror LiveFocusSubscription {
  LiveFocusSubscription
}

///|
/// The branch body for one focus target (see `component`). Its `init`
/// focuses the preview once the host has rendered; its only subscription
/// exists for `unload`, which releases the host when the target changes or
/// the conversation leaves the screen. It renders nothing.
fn LiveReasoning::focus_while(
  self : LiveReasoning,
  target : LiveReasoningTarget,
) -> @rabbita.Val[@html.Html] {
  let (state, _) = @rabbita.create_state_with_init(
    init=_ => {
      (
        (),
        @cmd.custom_cmd(
          _ => self.apply(Focused(Some(target))),
          kind=@cmd.after_render,
        ),
      )
    },
    update=(state : Unit, _ : Unit, _) => (state, @cmd.none),
    subscriptions=(_, _) => {
      @sub.custom_sub(
        "live-reasoning-focus",
        @sub.Local,
        LiveFocusSubscription,
        (payload, _) => {
          guard payload is LiveFocusSubscription else { return None }
          Some({
            unload: _ => self.apply(Focused(None)),
            update_tagger: _ => (),
          })
        },
      )
    },
  )
  state.map(_ => @html.nothing)
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
  guard run_id is Some(run_id) else { return }
  self.apply(Delta({ channel, session, run_id, }, websocket_epoch~, content))
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
  guard run_id is Some(run_id) else { return }
  self.apply(Finished({ channel, session, run_id, }, websocket_epoch~))
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
/// A new model step, unlike a late delta, can reopen the run's preview.
pub fn LiveReasoning::start_step(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  websocket_epoch~ : Int,
  session~ : String,
  run_id~ : String?,
) -> Unit {
  guard run_id is Some(run_id) else { return }
  self.apply(StepStarted({ channel, session, run_id, }, websocket_epoch~))
}

///|
/// Some engines start assistant deltas before sending a full reasoning event.
/// Preserve that finished thought in the ordinary model once, then retire the
/// imperative preview. Called only at the transport callback boundary.
pub fn LiveReasoning::complete_before_answer(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  websocket_epoch~ : Int,
  session~ : String,
  run_id~ : String?,
) -> String? {
  guard run_id is Some(run_id) && self.state.accepts(channel, websocket_epoch) else {
    return None
  }
  let key : LiveReasoningKey = { channel, session, run_id, }
  let content = self.state.preview_for(key).map(preview => preview.content())
  self.apply(Finished(key, websocket_epoch~))
  content
}
