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
  { value: "row\u{0}\{identity}" }
}

///|
fn TranscriptRenderKey::turn_rule(identity : String) -> TranscriptRenderKey {
  { value: "rule\u{0}\{identity}" }
}

///|
/// An activity card belongs to the stable non-activity row on its left. New
/// reasoning or tool rows can therefore extend either end of that card without
/// replacing its browser-owned `<details>` element.
fn TranscriptRenderKey::activity_after(
  boundary : String?,
) -> TranscriptRenderKey {
  match boundary {
    Some(identity) => { value: "activity\u{0}after\u{0}\{identity}" }
    None => { value: "activity\u{0}head" }
  }
}

///|
fn TranscriptRenderKey::streaming_reasoning(
  identity : String,
) -> TranscriptRenderKey {
  { value: "streaming-reasoning\u{0}\{identity}" }
}

///|
fn TranscriptRenderKey::streaming_response(
  identity : String,
) -> TranscriptRenderKey {
  { value: "streaming-response\u{0}\{identity}" }
}

///|
fn TranscriptRenderKey::subrun(
  lane : @transcript.SubrunLane,
) -> TranscriptRenderKey {
  match lane.run {
    Some(run_id) => { value: "subrun\u{0}\{run_id}\u{0}\{lane.id}" }
    None => { value: "subrun\u{0}unowned\u{0}\{lane.id}" }
  }
}

///|
fn TranscriptRenderKey::empty() -> TranscriptRenderKey {
  { value: "empty" }
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
  { value: "overview" }
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
  { value: "jump-latest" }
}

///|
/// Pure rendering context for one transcript component. Its child-building
/// methods return `Map[String, Html]`, which is the Rabbita API that preserves
/// a child by key while moving, inserting, or removing its siblings.
priv struct TranscriptRenderer {
  input : Input
  on_open : (String) -> @cmd.Cmd
  on_jump : (@mention_context.Target) -> @cmd.Cmd
}

///|
/// Build the keyed direct children of `#stream` in display order. Map insertion
/// order determines visual order; the strings only determine node identity.
fn TranscriptRenderer::stream_children(
  self : TranscriptRenderer,
) -> Map[String, @html.Html] {
  let visible = self.input.items
  let items : Map[String, @html.Html] = Map([])
  // The durable transcript plus client-local notices, rendered through one
  // folding pass. Live semantic events never synthesize durable-looking
  // items here; their store commits populate the transcript.
  if visible.is_empty() {
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
              "OpenSeek plans the work, edits files across your workspace, runs your tests, and hands back a reviewable result."
            Codex =>
              "Codex inspects, edits, and runs this workspace with its own account, sandbox, and approvals."
          },
        ),
      ]),
    )
  } else {
    // Reasoning and tool results fold behind collapsed activity cards;
    // everything the agent says stays out. Assistant messages break the run
    // like user messages and error bubbles do, so a turn reads as narration,
    // work, narration, work, answer rather than hiding the interim narration
    // inside the fold above the final answer. The same fold renders whether
    // the turn is still streaming or long settled, so nothing shown live
    // vanishes or restyles when the turn lands.
    let mut index = 0
    let mut left_boundary : String? = None
    while index < visible.length() {
      guard visible[index].item.kind is (Tool(..) | Reasoning) else {
        let row = visible[index]
        let item = row.item
        let anchor = if item.kind is User {
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
            assistant_name=match self.input.source {
              OpenSeek => "OpenSeek"
              Codex => "Codex"
            },
          ),
        )
        if item.kind is User {
          items.set(
            TranscriptRenderKey::turn_rule(row.identity).wire(),
            turn_rule_view(ts?=item.ts),
          )
        }
        left_boundary = Some(row.identity)
        index = index + 1
        continue
      }
      let run : Array[@transcript.TranscriptItem] = []
      while index < visible.length() &&
            visible[index].item.kind is (Tool(..) | Reasoning) {
        run.push(visible[index].item)
        index = index + 1
      }
      items.set(
        TranscriptRenderKey::activity_after(left_boundary).wire(),
        activity_view(run, self.on_open),
      )
    }
  }
  // Reasoning and answer can briefly coexist after the first answer delta.
  // Separate keys preserve the reasoning block (and its local scroll
  // position) while the answer is inserted after it.
  if !self.input.streaming_reasoning.is_empty() {
    items.set(
      TranscriptRenderKey::streaming_reasoning(self.input.streaming_identity).wire(),
      streaming_reasoning_view(
        self.input.streaming_reasoning,
        streaming=self.input.streaming_response.is_empty(),
        self.on_open,
      ),
    )
  }
  if !self.input.streaming_response.is_empty() {
    items.set(
      TranscriptRenderKey::streaming_response(self.input.streaming_identity).wire(),
      streaming_response_view(
        self.input.streaming_response,
        self.on_open,
        assistant_name=match self.input.source {
          OpenSeek => "OpenSeek"
          Codex => "Codex"
        },
      ),
    )
  }
  // Sub-runs in flight sit at the tail, where the turn currently is: their
  // tool call is what the conversation is blocked on, and it can block for
  // forty-five minutes.
  for lane in self.input.subruns {
    items.set(TranscriptRenderKey::subrun(lane).wire(), subrun_lane_view(lane))
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
