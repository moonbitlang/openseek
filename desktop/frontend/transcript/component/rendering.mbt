///|
/// One renderer-private key for a direct child of `#stream`.
priv struct TranscriptRenderKey {
  value : String
}

///|
fn TranscriptRenderKey::wire(self : TranscriptRenderKey) -> String {
  self.value
}

///|
fn TranscriptRenderKey::row(identity : String) -> TranscriptRenderKey {
  { value: "row\u{0}\{identity}", }
}

///|
fn TranscriptRenderKey::turn_rule(identity : String) -> TranscriptRenderKey {
  { value: "rule\u{0}\{identity}", }
}

///|
/// The response still streaming, keyed by its run: a new run gets a fresh
/// node, and the durable commit that lands it replaces this one.
fn TranscriptRenderKey::live(identity : String) -> TranscriptRenderKey {
  { value: "live\u{0}\{identity}", }
}

///|
fn TranscriptRenderKey::empty() -> TranscriptRenderKey {
  { value: "empty", }
}

///|
/// One renderer-private key for a direct child of `#transcript`.
priv struct TranscriptSectionKey {
  value : String
}

///|
fn TranscriptSectionKey::wire(self : TranscriptSectionKey) -> String {
  self.value
}

///|
fn TranscriptSectionKey::overview() -> TranscriptSectionKey {
  { value: "overview", }
}

///|
/// A stream is scoped by both channel and session because separate devices
/// may legitimately use the same session id.
fn TranscriptSectionKey::stream(input : Input) -> TranscriptSectionKey {
  {
    value: "stream\u{0}\{input.source.wire()}\u{0}\{input.focused.uri_authority()}\u{0}\{input.active_session}",
  }
}

///|
fn TranscriptSectionKey::jump_latest() -> TranscriptSectionKey {
  { value: "jump-latest", }
}

///|
/// Pure rendering context for one transcript component. Its child-building
/// methods return `Map[String, Html]`, which is the Rabbita API that preserves
/// a child by key while moving, inserting, or removing its siblings.
priv struct TranscriptRenderer {
  input : Input
  on_open : (String) -> @cmd.Cmd
  on_jump : (@mention_context.Target) -> @cmd.Cmd
  on_open_session : (String) -> @cmd.Cmd
}

///|
/// The context a sub-run tool card needs to link to its child transcript, or
/// `None` when this transcript can hold no sub-run.
///
/// Only OpenSeek writes `<parent>-sr-N` child records; a Codex or legacy
/// transcript with a coincidentally-shaped brief must not be given a link to a
/// session that does not exist. An unsaved conversation has no parent id to
/// hang a child off, and `subrun_child_session` rejects the empty parent.
fn TranscriptRenderer::subrun_link(self : TranscriptRenderer) -> SubrunLink? {
  guard self.input.source is OpenSeek else { return None }
  Some({ parent: self.input.active_session, open: self.on_open_session, })
}

///|
fn TranscriptRenderer::assistant_name(self : TranscriptRenderer) -> String {
  match self.input.source {
    OpenSeek => "OpenSeek"
    Codex => "Codex"
  }
}

///|
/// Build the keyed direct children of `#stream` in display order: one node
/// per transcript item (a user turn also draws its closing rule), then the
/// response still streaming. Map insertion order determines visual order; the
/// strings only determine node identity.
fn TranscriptRenderer::stream_children(
  self : TranscriptRenderer,
) -> Map[String, @html.Html] {
  let visible = self.input.items
  let items : Map[String, @html.Html] = Map([])
  // The durable transcript plus client-local notices. Live semantic events
  // never synthesize durable-looking items here; their store commits populate
  // the transcript.
  if visible.is_empty() &&
    self.input.streaming_reasoning is None &&
    self.input.streaming_response is None {
    items.set(
      TranscriptRenderKey::empty().wire(),
      @html.div(class="empty", [
        @html.div(class="empty-badge", [
          @icons.icon(
            match self.input.source {
              OpenSeek => @icons.icon_logo
              Codex => @icons.icon_sparkle
            },
          ),
        ]),
        @html.div(class="empty-title", "What should we build?"),
        @html.div(
          class="empty-sub",
          match self.input.source {
            OpenSeek =>
              "SeekMoon plans the work, edits files across your workspace, runs your tests, and hands back a reviewable result."
            Codex =>
              "Codex inspects, edits, and runs this workspace with its own account, sandbox, and approvals."
          },
        ),
      ]),
    )
    return items
  }
  // OpenSeek numbers its model steps: every provider response that is not a
  // checkpoint replay is one. Codex and legacy items carry no ordinal.
  let mut steps = 0
  for index, row in visible {
    let item = row.item
    let step_label = if self.input.source is OpenSeek &&
      item.kind is Assistant(replay=false, ..) {
      steps += 1
      Some("#\{steps}")
    } else {
      None
    }
    let anchor = if item.kind is User(_) {
      Some(@transcript_overview.TurnKey::of(item, index~).anchor())
    } else {
      None
    }
    items.set(
      TranscriptRenderKey::row(row.identity).wire(),
      transcript_item_view(
        item,
        self.on_open,
        anchor?,
        on_jump=self.on_jump,
        assistant_name=self.assistant_name(),
        step_label?,
        subrun?=self.subrun_link(),
      ),
    )
    if item.kind is User(_) {
      items.set(
        TranscriptRenderKey::turn_rule(row.identity).wire(),
        turn_rule_view(ts?=item.ts),
      )
    }
  }
  // The response still streaming, through the same view a settled response
  // gets. Durable commits are untagged and cannot prove ownership of an
  // in-flight preview, so the preview stays visible as the provisional next
  // step; `Conversation::reasoning_for_render` suppresses only an exact,
  // completed duplicate after it has durably committed.
  if self.input.streaming_reasoning is Some(_) ||
    self.input.streaming_response is Some(_) {
    items.set(
      TranscriptRenderKey::live(self.input.streaming_identity).wire(),
      assistant_view(
        self.on_open,
        prose?=self.input.streaming_response,
        reasoning?=self.input.streaming_reasoning,
        step_label?=if self.input.source is OpenSeek {
          Some("#\{steps + 1}")
        } else {
          None
        },
        assistant_name=self.assistant_name(),
        live=true,
        reasoning_complete=self.input.reasoning_complete,
      ),
    )
  }
  items
}

///|
/// Build the keyed direct children of `#transcript`. The stream key includes
/// channel and session, so switching conversations replaces the entire stream
/// instead of reusing rows whose durable sequence numbers happen to match.
fn TranscriptRenderer::section_children(
  self : TranscriptRenderer,
  pinned : Bool,
  overview : @transcript_overview.State,
  overview_emit : @cmd.Emit[@transcript_overview.Msg],
  on_jump_latest : @cmd.Cmd,
) -> Map[String, @html.Html] {
  let visible_items = self.input.items.map(row => row.item)
  let children : Map[String, @html.Html] = Map([])
  // The overview rail leads the scroller: sticky-top only works from the
  // content's head, and rendering it unconditionally gives it a stable key (it
  // hides itself below two turns).
  children.set(
    TranscriptSectionKey::overview().wire(),
    @transcript_overview.rail(
      @transcript_overview.entries(visible_items, display=text => {
        match @mention_context.parse(text) {
          Some(message) => message.display_text()
          None => text
        }
      }),
      overview,
      overview_emit,
      clock=ms => clock_label(ms),
    ),
  )
  children.set(
    TranscriptSectionKey::stream(self.input).wire(),
    @html.div(id="stream", class="stream", self.stream_children()),
  )
  // Reading history unpins auto-follow (see `watch_transcript_scroll`); the
  // floating button is the way back to the live tail. Sticky inside the
  // scroller with zero height, so it never adds scroll length.
  if !pinned {
    children.set(
      TranscriptSectionKey::jump_latest().wire(),
      @html.div(class="jump-latest-wrap", [
        @html.button(
          class="jump-latest",
          type_="button",
          title="Jump to latest",
          on_click=on_jump_latest,
          @icons.icon(@icons.icon_arrow_down),
        ),
      ]),
    )
  }
  children
}
