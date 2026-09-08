///|
/// One live reasoning stream's exact owner. Session ids are scoped by their
/// device channel, and separate runs of one session must never share text.
pub(all) struct Key {
  channel : @interop.ChannelId
  session : String
  run_id : String
} derive(Eq)

///|
fn Key::wire(self : Key) -> String {
  self.channel.uri_authority() + "\u{0}" + self.session + "\u{0}" + self.run_id
}

///|
priv struct LiveReasoningPreview {
  key : Key
  // Keep provider fragments separate instead of copying the accumulated
  // text on every delta. Join them when rehydrating the visible widget or
  // handing a completed thought back to the ordinary transcript.
  chunks : @vector.Vector[String]
  // Sealed by the run's full reasoning event: a delayed fragment must not
  // recreate the thought until the next step reopens the run.
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
/// The `switch_by` tag of a focus target.
pub fn Key::tag(self : Key) -> String {
  self.wire()
}

///|
/// Previews for concurrently running conversations. Connection subscriptions
/// filter retired callbacks before they reach this state; it only owns content
/// and the currently displayed conversation. `Eq` serves the whitebox tests,
/// which compare whole states.
#warnings("-unused_value")
priv struct LiveReasoningState {
  previews : @vector.Vector[LiveReasoningPreview]
  active : Key?
} derive(Eq)

///|
priv enum LiveReasoningMsg {
  Focused(Key?)
  ClearChannel(@interop.ChannelId)
  Delta(Key, String)
  Finished(Key)
  StepStarted(Key)
  RunFinished(@interop.ChannelId, String)
}

///|
/// The only effects allowed out of the live state machine. They update one
/// browser-owned text node and never produce a Rabbita `Val[Html]`. `Eq` and
/// `Debug` serve the whitebox tests, which assert on effects.
#warnings("-unused_value")
priv enum LiveReasoningEffect {
  NoChange
  // `content` is the stored preview to rehydrate; `None` means the target
  // has no open preview and the host is cleared.
  Sync(target~ : String, content~ : String?)
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
    Sync(target~, content~) => preview.sync(target, content)
    Append(target~, content~) => preview.append(target, content)
    Hide(target~) => preview.hide(target)
    Reset => preview.reset()
  }
}

///|
fn LiveReasoningState::preview_for(
  self : LiveReasoningState,
  key : Key,
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
  target : Key?,
) -> LiveReasoningEffect {
  match target {
    None => Reset
    Some(target) =>
      Sync(
        target=target.wire(),
        content=self.preview_for(target).map(preview => preview.content()),
      )
  }
}

///|
/// Hide the visible card when the displayed target matches.
fn LiveReasoningState::hide_when(
  self : LiveReasoningState,
  matches : (Key) -> Bool,
) -> LiveReasoningEffect {
  match self.active {
    Some(active) if matches(active) => Hide(target=active.wire())
    _ => NoChange
  }
}

///|
fn LiveReasoningState::update(
  self : LiveReasoningState,
  msg : LiveReasoningMsg,
) -> (LiveReasoningState, LiveReasoningEffect) {
  match msg {
    Focused(target) => {
      let next = { ..self, active: target, }
      (next, next.sync_effect(target))
    }
    ClearChannel(channel) =>
      (
        {
          ..self,
          previews: self.previews.filter(p => p.key.channel != channel),
        },
        self.hide_when(key => key.channel == channel),
      )
    Delta(key, content) => {
      if content.is_empty() {
        return (self, NoChange)
      }
      let mut existing : Int? = None
      for index in 0..<self.previews.length() {
        if self.previews[index].key == key {
          existing = Some(index)
          break
        }
      }
      let previews = match existing {
        Some(index) => {
          let preview = self.previews[index]
          if preview.complete {
            return (self, NoChange)
          }
          self.previews.set(index, {
            ..preview,
            chunks: preview.chunks.push(content),
          })
        }
        None =>
          self.previews.push({
            key,
            chunks: @vector.singleton(content),
            complete: false,
          })
      }
      (
        { ..self, previews, },
        if self.active is Some(active) && active == key {
          Append(target=key.wire(), content~)
        } else {
          NoChange
        },
      )
    }
    StepStarted(key) =>
      (
        {
          ..self,
          previews: self.previews.filter(preview => preview.key != key),
        },
        self.hide_when(active => active == key),
      )
    Finished(key) => {
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
        self.hide_when(active => active == key),
      )
    }
    // The run is over, so nothing can reopen it: drop its entries rather than
    // keeping one sealed tombstone per completed run for the session's life.
    RunFinished(channel, run_id) =>
      (
        {
          ..self,
          previews: self.previews.filter(preview => {
            preview.key.channel != channel || preview.key.run_id != run_id
          }),
        },
        self.hide_when(key => key.channel == channel && key.run_id == run_id),
      )
  }
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
  { state: { previews: @vector.new(), active: None, }, preview: LivePreview(), }
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
pub fn LiveReasoning::focus_while(
  self : LiveReasoning,
  target : Key,
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
/// Whether the reader follows the tail. The transcript component mirrors its
/// scroll model here after every message; the preview reads it in its own
/// layout callback.
pub fn LiveReasoning::set_pinned(self : LiveReasoning, pinned : Bool) -> Unit {
  self.preview.pinned = pinned
}

///|
/// Discard transient text when its source is restarted or retired. The
/// subscription guarantees that retired callbacks cannot repopulate it.
pub fn LiveReasoning::clear_channel(
  self : LiveReasoning,
  channel : @interop.ChannelId,
) -> Unit {
  self.apply(ClearChannel(channel))
}

///|
/// Clear an abnormally closed run even when no semantic finish was emitted.
pub fn LiveReasoning::finish_run(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  run_id~ : String,
) -> Unit {
  self.apply(RunFinished(channel, run_id))
}

///|
/// What the bridge should do with an engine event after the preview has seen
/// it.
pub enum LiveObservation {
  /// The preview consumed the event; the application never sees it.
  Consumed
  /// Forward the event to the application unchanged.
  Forward
  /// Forward the event after committing this finished thought to the
  /// application as a full reasoning event. Some engines start assistant
  /// deltas before sending one; the preview is retired at that point and the
  /// ordinary model shows the thought instead.
  ForwardAfterReasoning(String)
}

///|
/// Route one engine event through the preview. Fragments are consumed here so
/// they never schedule an application render; semantic boundaries seal or
/// reopen the run's preview and are forwarded.
pub fn LiveReasoning::observe(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  session~ : String,
  run_id~ : String?,
  event : @transcript.EngineEvent,
) -> LiveObservation {
  guard run_id is Some(run_id) else { return Forward }
  let key : Key = { channel, session, run_id, }
  match event {
    ReasoningDelta(content) => {
      self.apply(Delta(key, content))
      Consumed
    }
    // A retried provider stream starts the step over: the fragments of the
    // interrupted attempt are discarded so the replacement reopens cleanly.
    AgentStep(_) | StreamRetry(..) => {
      self.apply(StepStarted(key))
      Forward
    }
    AssistantDelta(content) | AssistantMessage(content) => {
      if content.is_empty() {
        return Forward
      }
      let thought = self.state
        .preview_for(key)
        .map(preview => preview.content())
      self.apply(Finished(key))
      match thought {
        Some(content) => ForwardAfterReasoning(content)
        None => Forward
      }
    }
    ReasoningMessage(_)
    | AgentFinished(_)
    | ContextYield(_)
    | AgentAborted(_)
    | AgentSetupFailed(_)
    | MaxStepsExhausted => {
      self.apply(Finished(key))
      Forward
    }
    _ => Forward
  }
}

///|
pub extend Key with Eq::{equal, not_equal}
