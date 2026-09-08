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
/// Previews for concurrently running conversations. Connection subscriptions
/// filter retired callbacks before they reach this state; it only owns content
/// and the currently displayed conversation.
priv struct LiveReasoningState {
  previews : @vector.Vector[LiveReasoningPreview]
  active : LiveReasoningTarget?
} derive(Eq)

///|
priv enum LiveReasoningMsg {
  Focused(LiveReasoningTarget?)
  ClearChannel(@interop.ChannelId)
  Delta(LiveReasoningKey, String)
  Finished(LiveReasoningKey)
  StepStarted(LiveReasoningKey)
  RunFinished(@interop.ChannelId, String)
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
    ClearChannel(channel) =>
      (
        {
          ..self,
          previews: self.previews.filter(p => p.key.channel != channel),
        },
        if self.active is Some(active) && active.key.channel == channel {
          Hide(target=active.key.wire())
        } else {
          NoChange
        },
      )
    Delta(key, content) => {
      if content.is_empty() {
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
    StepStarted(key) =>
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
        if self.active is Some(active) && active.key == key {
          Hide(target=key.wire())
        } else {
          NoChange
        },
      )
    }
    RunFinished(channel, run_id) => {
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
/// Discard transient text when its source is restarted or retired. The
/// subscription guarantees that retired callbacks cannot repopulate it.
pub fn LiveReasoning::clear_channel(
  self : LiveReasoning,
  channel : @interop.ChannelId,
) -> Unit {
  self.apply(ClearChannel(channel))
}

///|
/// Append one ordered provider fragment to its conversation's preview.
pub fn LiveReasoning::delta(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  session~ : String,
  run_id~ : String?,
  content~ : String,
) -> Unit {
  guard run_id is Some(run_id) else { return }
  self.apply(Delta({ channel, session, run_id, }, content))
}

///|
/// The full semantic reasoning event closes the preview unconditionally.
/// Its durable Assistant commit, whenever observed, is the only history row.
pub fn LiveReasoning::finish(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  session~ : String,
  run_id~ : String?,
) -> Unit {
  guard run_id is Some(run_id) else { return }
  self.apply(Finished({ channel, session, run_id, }))
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
/// A new model step, unlike a late delta, can reopen the run's preview.
pub fn LiveReasoning::start_step(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  session~ : String,
  run_id~ : String?,
) -> Unit {
  guard run_id is Some(run_id) else { return }
  self.apply(StepStarted({ channel, session, run_id, }))
}

///|
/// Some engines start assistant deltas before sending a full reasoning event.
/// Preserve that finished thought in the ordinary model once, then retire the
/// imperative preview. Called only at the transport callback boundary.
pub fn LiveReasoning::complete_before_answer(
  self : LiveReasoning,
  channel~ : @interop.ChannelId,
  session~ : String,
  run_id~ : String?,
) -> String? {
  guard run_id is Some(run_id) else { return None }
  let key : LiveReasoningKey = { channel, session, run_id, }
  let content = self.state.preview_for(key).map(preview => preview.content())
  self.apply(Finished(key))
  content
}
