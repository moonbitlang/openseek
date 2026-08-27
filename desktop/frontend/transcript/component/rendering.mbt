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
/// An activity card belongs to the stable non-activity row on its left. New
/// reasoning or tool rows can therefore extend either end of that card without
/// replacing its browser-owned `<details>` element.
fn TranscriptRenderKey::activity_after(
  boundary : String?,
) -> TranscriptRenderKey {
  match boundary {
    Some(identity) => { value: "activity\u{0}after\u{0}\{identity}", }
    None => { value: "activity\u{0}head", }
  }
}

///|
fn TranscriptRenderKey::streaming(identity : String) -> TranscriptRenderKey {
  { value: "streaming\u{0}\{identity}", }
}

///|
fn TranscriptRenderKey::empty() -> TranscriptRenderKey {
  { value: "empty", }
}

///|
/// Every current-format provider response is persisted as one Assistant event.
/// Its sequence is copied to the response's reasoning, prose, and tool rows, so
/// step numbering is a direct grouping operation rather than a reconstruction
/// from terminal or tool payloads. Checkpoint replays have their own item kind
/// and deliberately do not contribute evidence.
fn durable_step_ordinals(rows : Array[VisibleRow]) -> Map[Int, Int] {
  let ordinals : Map[Int, Int] = Map([])
  let mut next = 1
  for row in rows {
    guard row.item.sequence is Some(sequence) else { continue }
    let evidence = match row.item.kind {
      Reasoning | Tool(arguments=Some(_), ..) | Assistant(is_danger=false) =>
        true
      _ => false
    }
    if evidence && ordinals.get(sequence) is None {
      ordinals.set(sequence, next)
      next += 1
    }
  }
  ordinals
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
  // Present only while the component-owned reasoning stream is open. A
  // completed preview is deleted, so durable rows need no content matching.
  live_reasoning : String?
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
/// Insert one non-activity transcript row. Activity rows are handled by the
/// step-aware grouping pass below; keeping this path singular ensures user turn
/// anchors and assistant/error rendering cannot drift between durable steps
/// and rows from other transcript sources.
fn TranscriptRenderer::insert_row(
  self : TranscriptRenderer,
  items : Map[String, @html.Html],
  row : VisibleRow,
  index : Int,
) -> Unit {
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
}

///|
/// Build the keyed direct children of `#stream` in display order. Map insertion
/// order determines visual order; the strings only determine node identity.
fn TranscriptRenderer::stream_children(
  self : TranscriptRenderer,
) -> Map[String, @html.Html] {
  let visible = self.input.items
  let items : Map[String, @html.Html] = Map([])
  let mut left_boundary : String? = None
  let step_ordinals = if self.input.source is OpenSeek {
    durable_step_ordinals(visible)
  } else {
    Map([])
  }
  // The durable transcript plus client-local notices, rendered through one
  // grouping pass. Live semantic events never synthesize durable-looking
  // items here; their store commits populate the transcript.
  if visible.is_empty() &&
    self.live_reasoning is None &&
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
  } else {
    // OpenSeek's durable Assistant sequence is the model-step identity.
    // Group each step's reasoning and tools under its ordinal — reasoning
    // folded, every tool call on display — while keeping assistant prose
    // visible beside the group. Legacy/Codex rows have no OpenSeek step map
    // and retain the adjacent-activity behavior below.
    let mut index = 0
    while index < visible.length() {
      if visible[index].item.sequence is Some(sequence) &&
        step_ordinals.get(sequence) is Some(step_number) {
        let start = index
        let activity : Array[@transcript.TranscriptItem] = []
        while index < visible.length() &&
              visible[index].item.sequence == Some(sequence) {
          if visible[index].item.kind is (Tool(..) | Reasoning) {
            activity.push(visible[index].item)
          }
          index += 1
        }
        if !activity.is_empty() {
          items.set(
            TranscriptRenderKey::activity_after(left_boundary).wire(),
            activity_view(
              activity,
              self.on_open,
              step_label="#\{step_number}",
              subrun?=self.subrun_link(),
            ),
          )
        }
        // Assistant narration and final answers remain visible. The activity
        // is emitted first as the step's work disclosure; prose then becomes
        // the stable left boundary for the next provisional/durable step.
        let mut rendered_prose = false
        for row_index in start..<index {
          let row = visible[row_index]
          if !(row.item.kind is (Tool(..) | Reasoning)) {
            self.insert_row(items, row, row_index)
            left_boundary = Some(row.identity)
            rendered_prose = true
          }
        }
        if !rendered_prose {
          // A tool-only step has no prose row to become a boundary. Its final
          // durable row is still a stable predecessor: before the next commit
          // the live card keys after it, and after the commit the settled card
          // uses that same key.
          left_boundary = Some(visible[index - 1].identity)
        }
        continue
      }
      guard visible[index].item.kind is (Tool(..) | Reasoning) else {
        let row = visible[index]
        self.insert_row(items, row, index)
        left_boundary = Some(row.identity)
        index += 1
        continue
      }
      let run : Array[@transcript.TranscriptItem] = []
      while index < visible.length() &&
            visible[index].item.kind is (Tool(..) | Reasoning) {
        // An unnumbered runtime/goal card may sit immediately before a
        // durable model step. Leave that row for the step-aware branch above
        // instead of absorbing it into this fallback activity run.
        if visible[index].item.sequence is Some(sequence) &&
          step_ordinals.get(sequence) is Some(_) {
          break
        }
        run.push(visible[index].item)
        index += 1
      }
      items.set(
        TranscriptRenderKey::activity_after(left_boundary).wire(),
        activity_view(run, self.on_open, subrun?=self.subrun_link()),
      )
      left_boundary = Some(visible[index - 1].identity)
    }
  }
  // The preview exists only while its ordered `reasoning_delta` stream is
  // open. A commit may therefore make this temporarily duplicate a durable
  // card, or a semantic finish may remove it briefly before the commit lands;
  // either order converges to the durable transcript without correlation.
  if self.live_reasoning is Some(reasoning) {
    items.set(
      TranscriptRenderKey::activity_after(left_boundary).wire(),
      activity_view(
        [],
        self.on_open,
        live_reasoning=reasoning,
        step_label=if self.input.source is OpenSeek {
          "#\{step_ordinals.length() + 1}"
        } else {
          ""
        },
      ),
    )
  }
  if self.input.streaming_response is Some(streaming) {
    items.set(
      TranscriptRenderKey::streaming(self.input.streaming_identity).wire(),
      streaming_response_view(
        streaming,
        self.on_open,
        assistant_name=match self.input.source {
          OpenSeek => "OpenSeek"
          Codex => "Codex"
        },
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
