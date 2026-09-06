///|
/// One renderer-private key for a direct child of `#stream`.
priv struct TranscriptRenderKey {
  value : String
} derive(Eq)

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
/// Give an unstarted conversation enough location context to distinguish two
/// otherwise identical new-chat pages. A scratch or onboarding transcript has
/// no registered project and keeps the generic question.
fn empty_title(project_label : String?) -> String {
  match project_label {
    Some(project) => "What should we build in \{project}?"
    None => "What should we build?"
  }
}

///|
const EmptyProjectControlId : String = "empty-project-control"

///|
const EmptyProjectTriggerId : String = "empty-project-trigger"

///|
const EmptyProjectMenuId : String = "empty-project-menu"

///|
const EmptyProjectSearchId : String = "empty-project-search"

///|
/// Parent-owned presentation state and effects for the empty page's project
/// switcher. Keeping the open flag in the shell lets native views yield while
/// the popover is visible; the transcript owns only its DOM and interactions.
priv struct EmptyProjectControl {
  open : Bool
  query : String
  toggle : @cmd.Cmd
  dismiss : @cmd.Cmd
  query_changed : @cmd.Emit[String]
  choose : @cmd.Emit[@common.Uri]
  new_project : @cmd.Cmd
}

///|
fn ProjectChoice::matches(self : ProjectChoice, query : String) -> Bool {
  let query = query.trim().to_owned().to_lower()
  query.is_empty() ||
  self.label.to_lower().contains(query) ||
  self.root.path.to_lower().contains(query)
}

///|
/// A focus move within the top-layer popover is still inside its logical
/// control. Only a move outside (including the document losing focus) closes
/// it. The root subscription handles pointer click-away through the same
/// control boundary.
fn EmptyProjectControl::dismiss_on_blur(
  self : EmptyProjectControl,
  event : @dom.FocusEvent,
) -> @cmd.Cmd {
  if !self.open {
    return @cmd.none
  }
  if event.related_target() is Some(target) &&
    target.to_node() is Some(next) &&
    @dom.document().get_element_by_id(EmptyProjectControlId).to_option()
    is Some(root) &&
    root.contains(next) {
    @cmd.none
  } else {
    self.dismiss
  }
}

///|
fn EmptyProjectControl::keydown(
  self : EmptyProjectControl,
  event : @dom.KeyboardEvent,
) -> @cmd.Cmd {
  if event.key() == "Escape" && self.open {
    event.prevent_default()
    @cmd.batch([self.dismiss, focus_empty_project_trigger_after_render()])
  } else {
    @cmd.none
  }
}

///|
fn EmptyProjectControl::render(
  self : EmptyProjectControl,
  current : @common.Uri,
  label : String,
  projects : Array[ProjectChoice],
) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.button(
      class=if self.open {
        "empty-project-trigger open"
      } else {
        "empty-project-trigger"
      },
      type_="button",
      title="Choose a project",
      on_click=self.toggle,
      attrs=@html.Attrs::build()
        .id(EmptyProjectTriggerId)
        .aria_label("Choose project, current project \{label}")
        .aria_haspopup("dialog")
        .aria_controls(EmptyProjectMenuId)
        .aria_expanded(self.open.to_string())
        .on_blur(event => self.dismiss_on_blur(event))
        .on_keydown(event => self.keydown(event)),
      label,
    ),
  ]
  if self.open {
    let visible = projects.filter(project => project.matches(self.query))
    let rows : Array[@html.Html] = []
    for project in visible {
      let selected = project.root == current
      rows.push(
        @html.button(
          class=if selected {
            "empty-project-option selected"
          } else {
            "empty-project-option"
          },
          type_="button",
          title=project.root.path,
          on_click=if selected {
            @cmd.batch([
              self.dismiss,
              focus_empty_project_trigger_after_render(),
            ])
          } else {
            @cmd.batch([
              (self.choose)(project.root),
              focus_empty_project_trigger_after_render(),
            ])
          },
          attrs=@html.Attrs::build()
            .aria_label(
              if selected {
                "\{project.label}, current project — \{project.root.path}"
              } else {
                "\{project.label} — \{project.root.path}"
              },
            )
            .aria_current(if selected { "true" } else { "false" })
            .on_blur(event => self.dismiss_on_blur(event))
            .on_keydown(event => self.keydown(event)),
          [
            @html.span(
              class="empty-project-option-icon",
              @icons.icon(@icons.icon_folder),
            ),
            @html.span(class="empty-project-option-label", project.label),
            @html.span(
              class="empty-project-option-check",
              attrs=@html.Attrs::build().aria_hidden("true"),
              if selected {
                "✓"
              } else {
                ""
              },
            ),
          ],
        ),
      )
    }
    if rows.is_empty() {
      rows.push(
        @html.div(
          class="empty-project-no-results",
          attrs=@html.Attrs::build().role("status"),
          "No projects found",
        ),
      )
    }
    children.push(
      @html.div(
        class="empty-project-menu",
        attrs=@html.Attrs::build()
          .id(EmptyProjectMenuId)
          .role("dialog")
          .aria_label("Choose a project")
          .popover("manual"),
        [
          @html.div(
            class="empty-project-search",
            attrs=@html.Attrs::build().data_set("focus-owner", ""),
            [
              @html.span(
                class="empty-project-search-icon",
                @icons.icon(@icons.icon_search),
              ),
              @html.input(
                input_type=@html.InputType::Text,
                value=self.query,
                autofocus=true,
                placeholder="Search projects",
                on_input=self.query_changed,
                attrs=@html.Attrs::build()
                  .id(EmptyProjectSearchId)
                  .aria_label("Search projects")
                  .data_set("focus-target", "")
                  .on_blur(event => self.dismiss_on_blur(event))
                  .on_keydown(event => self.keydown(event)),
              ),
            ],
          ),
          @html.div(
            class="empty-project-options",
            attrs=@html.Attrs::build().role("group").aria_label("Projects"),
            rows,
          ),
          @html.button(
            class="empty-project-new",
            type_="button",
            on_click=@cmd.batch([self.dismiss, self.new_project]),
            attrs=@html.Attrs::build()
              .on_blur(event => self.dismiss_on_blur(event))
              .on_keydown(event => self.keydown(event)),
            [@icons.icon(@icons.icon_add), @html.span("New project")],
          ),
        ],
      ),
    )
  }
  @html.div(
    class="empty-project-control",
    attrs=@html.Attrs::build().id(EmptyProjectControlId),
    children,
  )
}

///|
fn empty_transcript_view(
  input : EmptyContent,
  project_menu : EmptyProjectControl,
) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.div(class="empty-badge", [
      @icons.icon(
        match input.source {
          OpenSeek => @icons.icon_logo
          Codex => @icons.icon_sparkle
        },
      ),
    ]),
  ]
  let title = match (input.project_label, input.current_project) {
    (Some(label), Some(project)) if input.can_choose_project &&
      !input.projects.is_empty() =>
      @html.div(class="empty-title", [
        @html.span("What should we build in "),
        @html.div(class="empty-title-project", [
          project_menu.render(project, label, input.projects),
          @html.span("?"),
        ]),
      ])
    _ => @html.div(class="empty-title", empty_title(input.project_label))
  }
  children.push(title)
  // OpenSeek's explanatory sentence duplicated what the composer and product
  // already make clear. Codex retains its source-specific account/sandbox
  // context because that distinguishes the alternate backend.
  if input.source is Codex {
    children.push(
      @html.div(
        class="empty-sub",
        "Codex inspects, edits, and runs this workspace with its own account, sandbox, and approvals.",
      ),
    )
  }
  @html.div(class="empty", children)
}

///|
/// Bind the parent-owned effects only while rendering. The empty block itself
/// remains pure and comparable, so changing the picker state updates this one
/// stable branch without remounting its input.
fn EmptyContent::render(self : EmptyContent, actions : Actions) -> @html.Html {
  let project_menu : EmptyProjectControl = {
    open: self.project_menu_open,
    query: self.project_query,
    toggle: if self.project_menu_open {
      actions.toggle_project_menu
    } else {
      @cmd.batch([
        actions.toggle_project_menu,
        show_empty_project_menu_after_render(),
      ])
    },
    dismiss: actions.dismiss_project_menu,
    query_changed: actions.project_query_changed,
    choose: actions.choose_project,
    new_project: actions.new_project,
  }
  empty_transcript_view(self, project_menu)
}

///|
/// One renderer-private key for a direct child of `#transcript`.
priv struct TranscriptSectionKey {
  value : String
} derive(Eq)

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
fn Source::assistant_name(self : Source) -> String {
  match self {
    OpenSeek => "OpenSeek"
    Codex => "Codex"
  }
}

///|
/// The session a sub-run tool card links its child transcript under, or
/// `None` when this transcript can hold no sub-run.
///
/// Only OpenSeek writes `<parent>-sr-N` child records; a Codex or legacy
/// transcript with a coincidentally-shaped brief must not be given a link to a
/// session that does not exist. An unsaved conversation has no parent id to
/// hang a child off, and `subrun_child_session` rejects the empty parent.
fn Input::subrun_parent(self : Input) -> String? {
  guard self.source is OpenSeek else { return None }
  Some(self.active_session)
}

///|
/// One direct child of `#stream`, as the data its Html is a function of. The
/// callbacks a rendered block needs are supplied at render time rather than
/// stored, so blocks compare by value: the component recomputes a block's
/// Html only when the block itself changed, and a streaming delta leaves every
/// settled row's Html untouched.
priv struct Block {
  /// The stream the block belongs to. It is part of the block's branch
  /// identity so a conversation switch never continues another conversation's
  /// branch, even where durable sequence numbers coincide.
  stream : TranscriptSectionKey
  key : TranscriptRenderKey
  content : BlockContent
} derive(Eq)

///|
/// The empty block's pure rendering inputs. Keeping these values in the block
/// lets `assoc_by` update only this branch when the menu opens or its query
/// changes, while the stable branch key preserves its DOM and input focus.
priv struct EmptyContent {
  source : Source
  project_label : String?
  current_project : @common.Uri?
  projects : Array[ProjectChoice]
  can_choose_project : Bool
  project_menu_open : Bool
  project_query : String
} derive(Eq)

///|
fn Input::empty_content(self : Input) -> EmptyContent {
  {
    source: self.source,
    project_label: self.project_label,
    current_project: self.current_project,
    projects: self.projects,
    can_choose_project: self.can_choose_project,
    project_menu_open: self.project_menu_open,
    project_query: self.project_query,
  }
}

///|
priv enum BlockContent {
  /// Nothing to show: no durable items and nothing streaming.
  Empty(EmptyContent)
  /// One transcript item. `step_label` is the ordinal an OpenSeek provider
  /// response carries ("#3"); `anchor` is a user turn's overview anchor;
  /// `subrun_parent` is the session a sub-run tool card links its child
  /// transcript under, when this transcript can hold one.
  Item(
    item~ : @transcript.TranscriptItem,
    anchor~ : String?,
    step_label~ : String?,
    assistant_name~ : String,
    subrun_parent~ : String?
  )
  /// The rule closing a user turn.
  TurnRule(ts~ : Double?)
  /// The response still streaming, shown through the same view a settled
  /// response gets. Durable commits are untagged and cannot prove ownership
  /// of an in-flight preview, so the preview stays visible as the provisional
  /// next step; `Conversation::reasoning_for_render` suppresses only an
  /// exact, completed duplicate after it has durably committed.
  Live(
    prose~ : String?,
    reasoning~ : String?,
    reasoning_complete~ : Bool,
    step_label~ : String?,
    assistant_name~ : String
  )
} derive(Eq)

///|
/// The direct children of `#stream` in display order: one block per
/// transcript item (a user turn also draws its closing rule), then the
/// response still streaming; or the empty state alone. Vector order determines
/// visual order; the keys only determine node identity.
fn stream_blocks(input : Input) -> @vector.Vector[Block] {
  let stream = TranscriptSectionKey::stream(input)
  // The durable transcript plus client-local notices. Live semantic events
  // never synthesize durable-looking items here; their store commits populate
  // the transcript.
  guard !input.items.is_empty() ||
    input.streaming_reasoning is Some(_) ||
    input.streaming_response is Some(_) else {
    return @vector.singleton({
      stream,
      key: TranscriptRenderKey::empty(),
      content: Empty(input.empty_content()),
    })
  }
  let assistant_name = input.source.assistant_name()
  let subrun_parent = input.subrun_parent()
  let blocks : Array[Block] = []
  // OpenSeek numbers its model steps: every provider response that is not a
  // checkpoint replay is one. Codex and legacy items carry no ordinal.
  let mut steps = 0
  for index, row in input.items {
    let item = row.item
    let step_label = if input.source is OpenSeek &&
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
    blocks.push({
      stream,
      key: TranscriptRenderKey::row(row.identity),
      content: Item(
        item~,
        anchor~,
        step_label~,
        assistant_name~,
        subrun_parent~,
      ),
    })
    if item.kind is User(_) {
      blocks.push({
        stream,
        key: TranscriptRenderKey::turn_rule(row.identity),
        content: TurnRule(ts=item.ts),
      })
    }
  }
  if input.streaming_reasoning is Some(_) || input.streaming_response is Some(_) {
    blocks.push({
      stream,
      key: TranscriptRenderKey::live(input.streaming_identity),
      content: Live(
        prose=input.streaming_response,
        reasoning=input.streaming_reasoning,
        reasoning_complete=input.reasoning_complete,
        step_label=if input.source is OpenSeek {
          Some("#\{steps + 1}")
        } else {
          None
        },
        assistant_name~,
      ),
    })
  }
  @vector.from_array(blocks)
}

///|
/// The identity of the block's memoized branch: its stream, then its key.
fn Block::branch_key(self : Block) -> String {
  "\{self.stream.wire()}\u{0}\{self.key.wire()}"
}

///|
/// The block's Html. The parent's actions are captured by the component and
/// passed through here; a block never stores them.
fn Block::render(self : Block, actions : Actions) -> @html.Html {
  let on_open = path => (actions.open)(path)
  match self.content {
    Empty(empty) => empty.render(actions)
    Item(item~, anchor~, step_label~, assistant_name~, subrun_parent~) =>
      transcript_item_view(
        item,
        on_open,
        anchor?,
        on_jump=target => (actions.jump)(target),
        assistant_name~,
        step_label?,
        subrun?=subrun_parent.map(parent => SubrunLink::{
          parent,
          open: session => (actions.open_session)(session),
        }),
      )
    TurnRule(ts~) => turn_rule_view(ts?)
    Live(prose~, reasoning~, reasoning_complete~, step_label~, assistant_name~) =>
      assistant_view(
        on_open,
        prose?,
        reasoning?,
        step_label?,
        assistant_name~,
        live=true,
        reasoning_complete~,
      )
  }
}

///|
/// The rendered blocks as Rabbita's keyed children of `#stream`: map
/// insertion order is the display order, and a key pairs a block's node with
/// its own element while its siblings move, appear, or leave.
fn keyed_stream(
  rendered : @vector.Vector[(String, @html.Html)],
) -> Map[String, @html.Html] {
  let children : Map[String, @html.Html] = Map([])
  for pair in rendered {
    children[pair.0] = pair.1
  }
  children
}

///|
/// The keyed direct children of `#transcript`. The stream key includes channel
/// and session, so switching conversations replaces the entire stream instead
/// of reusing rows whose durable sequence numbers happen to match.
fn section_children(
  input : Input,
  stream~ : Map[String, @html.Html],
  pinned~ : Bool,
  overview~ : @transcript_overview.State,
  overview_emit~ : @cmd.Emit[@transcript_overview.Msg],
  on_jump_latest~ : @cmd.Cmd,
) -> Map[String, @html.Html] {
  let visible_items = input.items.map(row => row.item)
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
    TranscriptSectionKey::stream(input).wire(),
    @html.div(id="stream", class="stream", stream),
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
