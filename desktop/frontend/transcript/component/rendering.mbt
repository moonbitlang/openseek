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
/// Pure rendering context for one transcript component. `blocks` builds the
/// stream's children as data; `stream_children` renders them eagerly into the
/// keyed map Rabbita uses to preserve a child by key while moving, inserting,
/// or removing its siblings.
priv struct TranscriptRenderer {
  input : Input
  on_open : (String) -> @cmd.Cmd
  on_jump : (@mention_context.Target) -> @cmd.Cmd
  on_open_session : (String) -> @cmd.Cmd
}

///|
/// One direct child of `#stream` as pure data: the wire key plus every input
/// its views read, with no callbacks and no Html. A `Block` is `Eq`, so an
/// unchanged block can skip re-rendering — and the Markdown parse its row
/// owns — while a sibling streams. The callback-carrying context
/// (`SubrunLink`) is rebuilt inside `Block::render` from `subrun_parent`.
priv struct Block {
  key : String
  kind : BlockKind
  // The OpenSeek step ordinal this row carries ("#3"), `None` for every other
  // source and kind.
  step_label : String?
  // The user bubble's turn anchor, present only on user rows.
  anchor : String?
  source : Source
  // The session a sub-run result card links back to, present only under an
  // OpenSeek transcript that can hold sub-runs.
  subrun_parent : String?
} derive(Eq)

///|
/// What one block shows. Each kind carries only the data its own view reads.
priv enum BlockKind {
  /// A durable transcript item, rendered by `transcript_item_view`.
  Item(@transcript.TranscriptItem)
  /// The hairline closing a user turn, dated by the prompt's send time.
  Rule(ts~ : Double?)
  /// The in-flight response under `live\0<run>`, still arriving.
  Live(prose~ : String?, reasoning~ : String?, reasoning_complete~ : Bool)
  /// The transcript's empty state.
  Empty
} derive(Eq)

///|
/// The direct children of `#stream` in display order as data: one block per
/// visible row (a user turn also contributes its closing rule), then the
/// response still streaming, or the single empty-state block when the
/// transcript holds nothing at all. Building blocks never parses Markdown or
/// constructs Html; that cost stays in `Block::render`.
fn TranscriptRenderer::blocks(
  self : TranscriptRenderer,
) -> @vector.Vector[Block] {
  let visible = self.input.items
  let live = self.input.streaming_reasoning is Some(_) ||
    self.input.streaming_response is Some(_)
  if visible.is_empty() && !live {
    return @vector.singleton({
      key: TranscriptRenderKey::empty().wire(),
      kind: Empty,
      step_label: None,
      anchor: None,
      source: self.input.source,
      subrun_parent: None,
    })
  }
  let subrun_parent = if self.input.source is OpenSeek {
    Some(self.input.active_session)
  } else {
    None
  }
  // OpenSeek numbers its model steps: every provider response that is not a
  // checkpoint replay is one. Codex and legacy items carry no ordinal. A
  // durable transcript is append-only, so the label an item already carries
  // never changes and its block stays Eq-stable between streaming deltas.
  let mut steps = 0
  let mut blocks = @vector.new()
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
    blocks = blocks.push({
      key: TranscriptRenderKey::row(row.identity).wire(),
      kind: Item(item),
      step_label,
      anchor,
      source: self.input.source,
      subrun_parent,
    })
    if item.kind is User(_) {
      blocks = blocks.push({
        key: TranscriptRenderKey::turn_rule(row.identity).wire(),
        kind: Rule(ts=item.ts),
        step_label: None,
        anchor: None,
        source: self.input.source,
        subrun_parent: None,
      })
    }
  }
  // The response still streaming, through the same view a settled response
  // gets. Durable commits are untagged and cannot prove ownership of an
  // in-flight preview, so the preview stays visible as the provisional next
  // step; `Conversation::reasoning_for_render` suppresses only an exact,
  // completed duplicate after it has durably committed.
  if live {
    blocks = blocks.push({
      key: TranscriptRenderKey::live(self.input.streaming_identity).wire(),
      kind: Live(
        prose=self.input.streaming_response,
        reasoning=self.input.streaming_reasoning,
        reasoning_complete=self.input.reasoning_complete,
      ),
      step_label: if self.input.source is OpenSeek {
        Some("#\{steps + 1}")
      } else {
        None
      },
      anchor: None,
      source: self.input.source,
      subrun_parent: None,
    })
  }
  blocks
}

///|
/// The keyed direct children of `#stream` in display order, composed eagerly
/// from `blocks`. Map insertion order determines visual order; the strings
/// only determine node identity. The live component instead renders each
/// block behind Rabbita's `assoc_by`, so an unchanged block's Html — and its
/// Markdown parse — is reused across streaming deltas.
fn TranscriptRenderer::stream_children(
  self : TranscriptRenderer,
) -> Map[String, @html.Html] {
  let items : Map[String, @html.Html] = Map([])
  for block in self.blocks() {
    items.set(
      block.key,
      block.render(self.on_open, self.on_jump, self.on_open_session),
    )
  }
  items
}

///|
/// Build the keyed direct children of `#transcript`. The stream key includes
/// channel and session, so switching conversations replaces the entire stream
/// instead of reusing rows whose durable sequence numbers happen to match.
/// `stream_children` is the already-rendered stream map (the component's
/// memoized rows, or an eager `stream_children()` call when none is supplied).
fn TranscriptRenderer::section_children(
  self : TranscriptRenderer,
  pinned : Bool,
  overview : @transcript_overview.State,
  overview_emit : @cmd.Emit[@transcript_overview.Msg],
  on_jump_latest : @cmd.Cmd,
  stream_children~ : Map[String, @html.Html],
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
    @html.div(id="stream", class="stream", stream_children),
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
