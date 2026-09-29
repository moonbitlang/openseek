///|
/// Which conversation source supplied the normalized rows. The component uses
/// this for source-specific labels, empty-state copy, and renderer identity.
pub(all) enum Source {
  OpenSeek
  Codex
} derive(Eq)

///|
pub fn Source::wire(self : Source) -> String {
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
/// One registered project offered by the empty transcript's project switcher.
/// The resource keeps its device identity while `label` is the compact final
/// path component shown in the title and menu.
pub(all) struct ProjectChoice {
  root : @common.Uri
  label : String
} derive(Eq)

///|
pub extend ProjectChoice with Eq::{equal, not_equal}

///|
/// Where the reader is in a transcript. `Pinned` follows the tail as content
/// grows; `Unpinned` records the history page and its scroll offset. The component
/// reports it when its conversation leaves the screen and receives it back
/// through `Input::scroll` when the conversation returns.
pub(all) enum ScrollPosition {
  Pinned
  Unpinned(top~ : Double, page~ : Int, overlap~ : Int?)
} derive(Eq)

///|
/// The conversation data rendered by the component. The application computes
/// durable chronology and active-run ownership; this package owns only the
/// transcript subtree and its scroll behavior.
struct Input {
  locale : @i18n.Locale
  dark_mode : Bool
  minimal : Bool
  source : Source
  focused : @interop.ChannelId
  active_session : String
  // Where the reader left this conversation last time, read once by `init`.
  scroll : ScrollPosition
  // Unique local send identity, observed once by the mounted component.
  follow_request : String?
  // The registered project that owns this conversation, kept separate from
  // `root`: a managed worktree resolves files from its checkout while the
  // empty-state question should still name the project the user selected.
  project_label : String?
  // The registered project behind `project_label`. Kept separate from `root`,
  // which may be a managed worktree checkout instead of the main project.
  current_project : @common.Uri?
  // Every registered project on the focused device, in sidebar order.
  projects : Array[ProjectChoice]
  // Only an unsent, unpersisted OpenSeek draft may change its project here.
  can_choose_project : Bool
  // Root-owned menu state participates in the shell's native-view occlusion.
  project_menu_open : Bool
  project_query : String
  // The concrete project or worktree root sent alongside relative Markdown
  // image paths so the owning host, rather than the frontend, resolves them.
  root : @common.Uri?
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
  locale? : @i18n.Locale = English,
  dark_mode? : Bool = false,
  minimal? : Bool = false,
  source~ : Source,
  focused~ : @interop.ChannelId,
  active_session~ : String,
  scroll? : ScrollPosition = Pinned,
  follow_request? : String,
  project_label? : String,
  current_project~ : @common.Uri?,
  projects~ : Array[ProjectChoice],
  can_choose_project~ : Bool,
  project_menu_open~ : Bool,
  project_query~ : String,
  root~ : @common.Uri?,
  items~ : Array[VisibleRow],
  streaming_response~ : String?,
  streaming_reasoning? : String,
  reasoning_complete? : Bool = false,
  streaming_identity~ : String,
) -> Input {
  {
    locale,
    dark_mode,
    minimal,
    source,
    focused,
    active_session,
    scroll,
    follow_request,
    project_label,
    current_project,
    projects,
    can_choose_project,
    project_menu_open,
    project_query,
    root,
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
  open_review_changes : @cmd.Emit[@mention_context.ReviewChanges]
  /// Open another session's transcript. Used by a sub-run tool card to reach
  /// the child transcript it names.
  open_session : @cmd.Emit[String]
  /// Start a fresh draft in another registered project.
  choose_project : @cmd.Emit[@common.Uri]
  /// Open the shell-owned folder picker to register another project.
  new_project : @cmd.Cmd
  toggle_project_menu : @cmd.Cmd
  dismiss_project_menu : @cmd.Cmd
  project_query_changed : @cmd.Emit[String]
  /// Where the reader was when this conversation left the screen. The root
  /// keeps it per conversation and hands it back through `Input::scroll`.
  departed : @cmd.Emit[ScrollPosition]
}

///|
/// Scroll ownership and overview state for one mounted conversation. The
/// component lives exactly as long as its conversation is on screen (the
/// root keys it by conversation), so `init` alone decides where a fresh
/// component starts: at the tail, or where the reader left this conversation.
priv struct Model {
  // None follows the latest page; an explicit index stays on that history page.
  page : Int?
  navigation : PageNavigation?
  navigation_generation : Int
  overlap : Int?
  pinned : Bool
  overview : @transcript_overview.State
  image_owner : ImageOwner
  images : ImageCache
} derive(Eq)

///|
priv enum Msg {
  Pinned(Bool)
  JumpToLatest
  CrossPage(Bool)
  MountPage(Int)
  PageReady(Int)
  ContentRendered
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
  turns? : TurnIndex = TurnIndex::new(input.items),
) -> (Model, @cmd.Cmd) {
  // The conversation is fixed for this component's lifetime, but its image
  // root can move (a worktree gets bound after the first send). Never project
  // the previous root's data URLs into a render for the new one.
  let image_owner = input.image_owner()
  let self = if self.image_owner == image_owner {
    self
  } else {
    { ..self, image_owner, images: ImageCache::empty(), }
  }
  match msg {
    MountPage(generation) => self.mount_page(turns, generation, emit)
    PageReady(generation) => {
      guard self.navigation
        is Some({ generation: current, rendering: true, .. }) &&
        current == generation else {
        return (self, @cmd.none)
      }
      (
        { ..self, navigation: None, },
        @cmd.batch([
          report_visible_turn_after_render(emit, current=self.overview.active),
          self.images.apply_after_render(),
        ]),
      )
    }
    Pinned(pinned) => {
      guard self.navigation is None else { return (self, @cmd.none) }
      let page = turns.page_rows(self.page).page
      let pinned = pinned && page.is_latest()
      (
        { ..self, pinned, page: if pinned { None } else { Some(page.index) }, },
        @cmd.none,
      )
    }
    CrossPage(forward) =>
      if self.navigation is None {
        self.cross_page(turns, forward, emit)
      } else {
        (self, @cmd.none)
      }
    JumpToLatest =>
      (
        { ..self, pinned: true, page: None, overlap: None, navigation: None, },
        @cmd.batch([
          measure_page_after_render(),
          scroll_after_render(),
          report_visible_turn_after_render(emit, current=self.overview.active),
        ]),
      )
    ContentRendered => {
      guard self.navigation is None else { return (self, @cmd.none) }
      // Rendered content grew or changed size. A pinned reader follows the
      // tail; the overview re-reads which turn sits under the reading line.
      let commands : Array[@cmd.Cmd] = []
      if self.pinned {
        commands.push(scroll_after_render())
      }
      commands.push(
        report_visible_turn_after_render(
          emit,
          current=self.overview.active,
          unpinned=!self.pinned,
        ),
      )
      commands.push(self.images.apply_after_render())
      (self, @cmd.batch(commands))
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
      if self.navigation is Some(_) && msg is ActiveChanged(_) {
        return (self, @cmd.none)
      }
      let previous_active = self.overview.active
      let next = {
        ..self,
        overview: @transcript_overview.update(msg, self.overview),
      }
      match msg {
        // The clicked tick is already under the pointer. Revealing it could
        // move the rail beneath the pointer and transfer hover to a neighbor.
        Clicked(key) => {
          guard turns.page_for_turn(key) is Some(page) else {
            return (self, @cmd.none)
          }
          if page != turns.page_rows(self.page).page.index ||
            self.navigation is Some(_) {
            return self.select_page(turns, page, emit, anchor=key)
          }
          (
            {
              ..next,
              pinned: false,
              page: Some(page),
              overlap: None,
              navigation: None,
            },
            @cmd.batch([
              measure_page_after_render(),
              scroll_turn_into_view(emit, key),
            ]),
          )
        }
        PreviousPage =>
          self.select_page(turns, self.navigation_page(turns).index - 1, emit)
        NextPage =>
          self.select_page(turns, self.navigation_page(turns).index + 1, emit)
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
///
/// Create one component per conversation on screen and dispose it when that
/// conversation leaves the screen (`Val::switch_by` keyed by conversation at
/// the root). Conversation identity therefore never changes inside a
/// component: `init` places the fresh scroller where the reader left this
/// conversation (or at its tail) and reports the first visible turn once its
/// DOM exists.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let turns = input.map(input => input.items).map(TurnIndex::new)
  let indexed_input = input.map2(turns, (input, turns) => (input, turns))
  let (state, emit) = @rabbita.create_state_with_input(
    input=indexed_input,
    init=(emit, indexed) => {
      let (input, _) = indexed
      (
        {
          navigation: None,
          navigation_generation: 0,
          pinned: input.scroll is Pinned,
          page: match input.scroll {
            Pinned => None
            Unpinned(page~, ..) => Some(page)
          },
          overlap: match input.scroll {
            Pinned => None
            Unpinned(overlap~, ..) => overlap
          },
          overview: @transcript_overview.State::empty(),
          image_owner: input.image_owner(),
          images: ImageCache::empty(),
        },
        @cmd.batch([
          measure_page_after_render(),
          match input.scroll {
            Pinned => scroll_after_render()
            Unpinned(top~, ..) => restore_scroll_after_render(top)
          },
          report_visible_turn_after_render(emit, current=None),
        ]),
      )
    },
    update=(state, indexed, msg, emit) => {
      state.update(indexed.0, msg, emit, turns=indexed.1)
    },
    subscriptions=(model, indexed, emit) => {
      let (input, turns) = indexed
      transcript_subscription(
        model,
        turns.page_rows(model.page).page,
        input.follow_request,
        emit,
        actions.departed,
      )
    },
  )
  // Every stream child renders in its own branch, keyed by the block within
  // its stream. A streaming delta then recomputes only the live block's Html;
  // each settled row keeps the Html it already has.
  //
  // Keeping the Html is not enough on its own: Rabbita's diff still walks a
  // node's subtree whenever the node is reached, so a delta would still cost
  // a comparison of every settled row's DOM. Each branch therefore wraps its
  // Html in `memo_by`, keyed by how many times the branch has rendered. The
  // branch renders only when its block changes (blocks compare by value), so
  // an unchanged key means an unchanged subtree, and the diff skips it. Stream
  // children are keyed, so a counter never meets another branch's counter.
  let selected_page = state.map(state => (state.page, state.overlap))
  let page_rows = turns.map2(selected_page, (turns, page) => {
    turns.page_rows(page.0, overlap=page.1)
  })
  let blocks = input.map2(page_rows, (input, bounds) => {
    stream_blocks(input, bounds~).map(block => (input.locale, block))
  })
  let rendered = blocks.assoc_by(
    (_, block) => {
      let renders = Ref(0)
      let (changes, changes_emit) = message_changes_state(
        block.map(pair => pair.1),
        actions,
      )
      changes.map2(block, (changes, pair) => {
        let (locale, block) = pair
        renders.val += 1
        let html = @html.memo_by(
          block,
          block => {
            block.render(
              locale~,
              actions,
              changes?=changes.control(block, changes_emit),
            )
          },
          by=_ => renders.val,
        )
        (block.key.wire(), html)
      })
    },
    by=pair => pair.1.branch_key(),
  )
  let navigation_page = turns.map2(
    state.map(state => state.navigation.map(n => n.page)),
    (turns, pending) => pending.map(page => turns.page_rows(Some(page)).page),
  )
  let pages = page_rows.map2(navigation_page, (bounds, pending) => {
    (bounds, pending)
  })
  state.view4(input, rendered, pages, (state, input, rendered, pages) => {
    let (bounds, pending) = pages
    transcript_view(
      locale=input.locale,
      input,
      pinned=state.pinned,
      overview=state.overview,
      page=pending.unwrap_or(bounds.page),
      loading=state.navigation is Some(_),
      overview_emit=emit.map(msg => Overview(msg)),
      stream=keyed_stream(rendered),
      on_jump_latest=emit(JumpToLatest),
    )
  })
}

///|
/// Manual popovers need an explicit top-layer transition after Rabbita has
/// committed their node. Focus the search field in the same command so typing
/// can begin immediately and blur provides click-away dismissal.
fn show_empty_project_menu_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(EmptyProjectMenuId).to_option()
        is Some(element) &&
        element.to_html_element() is Some(menu) {
        menu.show_popover()
      }
      if @dom.document().get_element_by_id(EmptyProjectSearchId).to_option()
        is Some(search) {
        let _ : @js.Value = @js.Value::cast_from(search).apply_with_string(
          "focus",
          ([] : FixedArray[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn focus_empty_project_trigger_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(EmptyProjectTriggerId).to_option()
        is Some(trigger) {
        let _ : @js.Value = @js.Value::cast_from(trigger).apply_with_string(
          "focus",
          ([] : FixedArray[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn scroll_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id("transcript").to_option()
        is Some(transcript) {
        transcript.set_scroll_top(transcript.get_scroll_height())
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Lay out the mounted page before restoring an offset or locating a turn.
/// Afterwards, content-visibility may skip offscreen rows using their measured
/// heights. Run on initial mount and page/turn navigation, not on each delta.
fn measure_page_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      guard @dom.document().get_element_by_id("stream").to_option()
        is Some(stream) &&
        stream.to_html_element() is Some(stream) else {
        return
      }
      let style = stream.get_style()
      style.set(STREAM_ROWS_VISIBILITY, "visible")
      @dom.window().request_animation_frame(_ => {
        style.remove_property(STREAM_ROWS_VISIBILITY) |> ignore
      })
      |> ignore
    },
    kind=@cmd.after_render,
  )
}

///|
/// The custom property `transcript.css` reads for the rows' content
/// visibility; `visible` on `#stream` renders every row.
const STREAM_ROWS_VISIBILITY = "--stream-rows-visibility"

///|
/// Put a returning conversation back where its reader left it. Lazily loaded
/// images may still shift the content afterwards; the offset is the best
/// available approximation of the same reading position.
fn restore_scroll_after_render(top : Double) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id("transcript").to_option()
        is Some(transcript) {
        transcript.set_scroll_top(top)
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// The viewport has reached this page's bottom. Only the latest page's
/// bottom may pin the conversation; reaching an older page's end must not.
fn at_bottom(transcript : @dom.Element) -> Bool {
  transcript.get_scroll_height() -
  transcript.get_scroll_top() -
  transcript.get_client_height() <=
  4.0
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
/// The user turn under the reading line, as the overview names it.
fn visible_turn(transcript : @dom.Element) -> @transcript_overview.TurnKey? {
  visible_turn_anchor(transcript).bind(
    @transcript_overview.TurnKey::from_anchor,
  )
}

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
    if bubbles
      .item(middle.to_double())
      .unwrap()
      .get_bounding_client_rect()
      .get_top() <=
      reference {
      found = Some(middle)
      low = middle + 1
    } else {
      high = middle - 1
    }
  }
  guard found is Some(index) else { return None }
  bubbles.item(index.to_double()).unwrap().get_attribute("id")
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
      guard turn_layout_top(bubble, transcript) is Some(top) else { return }
      transcript.set_scroll_top(top - 10.0)
      scheduler.add(emit(Pinned(at_bottom(transcript))))
      scheduler.add(emit(Overview(ActiveChanged(visible_turn(transcript)))))
    },
    kind=@cmd.after_render,
  )
}

///|
/// Re-read the overview highlight after content or geometry changed. `current`
/// is the Model's active turn; an unchanged reading is not re-reported.
/// Folding content can put an unpinned reader at the bottom without changing
/// scrollTop, so no scroll event arrives to clear the jump-to-latest button.
fn report_visible_turn_after_render(
  emit : @cmd.Emit[Msg],
  current~ : @transcript_overview.TurnKey?,
  unpinned? : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      guard @dom.document().get_element_by_id("transcript").to_option()
        is Some(transcript) else {
        return
      }
      let active = visible_turn(transcript)
      if unpinned && at_bottom(transcript) {
        scheduler.add(emit(Pinned(true)))
      }
      if active != current {
        scheduler.add(emit(Overview(ActiveChanged(active))))
      }
    },
    kind=@cmd.after_render,
  )
}

///|
priv suberror TranscriptSubscription {
  TranscriptSubscription(
    emit~ : @cmd.Emit[Msg],
    departed~ : @cmd.Emit[ScrollPosition],
    // The Model's current reading, refreshed after every message. The scroll
    // listener reports only readings that differ from it, so the Model is the
    // single source of truth and no cache can drift from it.
    pinned~ : Bool,
    active~ : @transcript_overview.TurnKey?,
    page~ : @transcript_overview.Page,
    follow_request~ : String?,
    overlap~ : Int?
  )
}

///|
/// Scroll position and rendered-content growth are DOM signals owned by the
/// transcript. Keeping both in this component means the application no longer
/// forwards a synthetic "content changed" message into child state.
fn transcript_subscription(
  model : Model,
  page : @transcript_overview.Page,
  follow_request : String?,
  emit : @cmd.Emit[Msg],
  departed : @cmd.Emit[ScrollPosition],
) -> @sub.Sub {
  @sub.custom_sub(
    "transcript-dom",
    @sub.Local,
    TranscriptSubscription(
      emit~,
      departed~,
      pinned=model.pinned,
      active=model.overview.active,
      page~,
      follow_request~,
      overlap=model.overlap,
    ),
    transcript_sub_loader,
  )
}

///|
fn transcript_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    TranscriptSubscription(
      emit~,
      departed~,
      pinned~,
      active~,
      page~,
      follow_request~,
      overlap~
    ) => {
      let mut emit = emit
      let mut departed = departed
      let mut pinned = pinned
      let mut active = active
      let mut page = page
      let mut overlap = overlap
      let gesture = PageGesture::new()
      let mut follow_request = follow_request
      let target = @dom.document().as_event_target()
      let listener : @dom.Listener = event => {
        guard event.target().to_element() is Some(element) &&
          element.get_property("id").to_option() is Some("transcript") else {
          return
        }
        // Report only what differs from the Model. Its next message brings
        // the same value back through `update_tagger`; assigning here just
        // keeps a burst of scroll events from repeating the report meanwhile.
        let position_pinned = page.is_latest() && at_bottom(element)
        if position_pinned != pinned {
          pinned = position_pinned
          scheduler.add(emit(Pinned(position_pinned)))
        }
        let visible = visible_turn(element)
        if visible != active {
          active = visible
          scheduler.add(emit(Overview(ActiveChanged(visible))))
        }
      }
      target.add_event_listener_with_options("scroll", listener, capture=true)
      let wheel_listener : @dom.Listener = event => {
        guard event.to_wheel_event() is Some(wheel) &&
          !wheel.get_ctrl_key() &&
          !wheel.get_shift_key() &&
          wheel.get_delta_y().abs() > wheel.get_delta_x().abs() &&
          event.target().to_element() is Some(element) &&
          element.closest("#transcript") is Some(_) &&
          element.closest(".transcript-overview") is None &&
          @dom.document().get_element_by_id("transcript").to_option()
          is Some(transcript) else {
          return
        }
        let forward = wheel.get_delta_y() > 0
        // A nested editor/code scroller owns its wheel input.
        if nested_scrollable(element, transcript, forward) {
          return
        }
        let boundary = if forward {
          !page.is_latest() && at_page_bottom(transcript)
        } else {
          page.index > 0 && transcript.get_scroll_top() <= 1
        }
        if gesture.wheel(wheel.get_time_stamp(), boundary, forward) {
          event.prevent_default()
          scheduler.add(emit(CrossPage(forward)))
        }
      }
      target.add_event_listener_with_options(
        "wheel",
        wheel_listener,
        passive=false,
      )
      let observers = TranscriptObservers::install(
        () => scheduler.add(emit(ContentRendered)),
        path => scheduler.add(emit(ImageRequested(path))),
      )
      Some({
        unload: scheduler => {
          target.remove_event_listener_with_options(
            "scroll",
            listener,
            capture=true,
          )
          target.remove_event_listener("wheel", wheel_listener)
          observers.disconnect()
          // The branch is disposed while the incremental graph is read, one
          // step before Rabbita replaces the DOM, so the scroller still shows
          // this conversation. Report where the reader was so a return can
          // put them back there.
          if @dom.document().get_element_by_id("transcript").to_option()
            is Some(transcript) {
            scheduler.add(
              departed(
                if pinned && page.is_latest() {
                  Pinned
                } else {
                  Unpinned(
                    top=transcript.get_scroll_top(),
                    page=page.index,
                    overlap~,
                  )
                },
              ),
            )
          }
        },
        update_tagger: payload => {
          guard payload
            is TranscriptSubscription(
              emit=next,
              departed=left,
              pinned=next_pinned,
              active=next_active,
              page=next_page,
              follow_request=next_request,
              overlap=next_overlap
            ) else {
            return
          }
          emit = next
          departed = left
          pinned = next_pinned
          active = next_active
          overlap = next_overlap
          page = next_page
          if next_request != follow_request {
            follow_request = next_request
            if next_request is Some(_) {
              scheduler.add(emit(JumpToLatest))
            }
          }
        },
      })
    }
    _ => None
  }
}

///|
/// Observe the transcript through Rabbita's typed DOM bindings. The document
/// observer only finds the scroller element once Rabbita has inserted it (the
/// subscription starts before the first paint); content growth and geometry
/// are then observed directly on that element, so unrelated page mutations
/// cannot feed back into component updates. Conversation identity is never
/// read back from the DOM: it is fixed for the component's lifetime.
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
  renderers : @markdown.DiagramRenderers
  images : @dom.IntersectionObserver
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
    renderers: @markdown.DiagramRenderers(on_size_changed),
    images: transcript_image_observer(on_image),
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
  self.renderers.dispose()
  if self.diagrams is Some(diagrams) {
    diagrams.dispose()
  }
  self.diagrams = None
  self.element = next
  if next is Some(element) {
    self.renderers.refresh(
      element,
      dark_mode=element.get_attribute("data-transcript-theme") is Some("dark"),
    )
    self.diagrams = Some(
      @diagram_viewport.DiagramViewports(element, self.on_size_changed),
    )
    observe_transcript_images(self.images, element)
  }
}

///|
fn TranscriptDomMount::refresh_content(self : Self) -> Unit {
  if self.element is Some(element) {
    self.renderers.refresh(
      element,
      dark_mode=element.get_attribute("data-transcript-theme") is Some("dark"),
    )
  }
  if self.diagrams is Some(diagrams) {
    diagrams.refresh()
  }
  if self.element is Some(element) {
    observe_transcript_images(self.images, element)
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
      child_list=true,
      character_data=true,
      subtree=true,
      attribute_filter=[
        "data-transcript-diagram", "data-transcript-diagram-source", "data-transcript-theme",
        // Native disclosures change layout without adding/removing children.
         "open",
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
  on_change : () -> Unit,
  on_image : (String) -> Unit,
) -> Self {
  let mount = TranscriptDomMount(on_change, on_image)
  let resize = @dom.ResizeObserver::new((_, _) => on_change())
  let content = @dom.MutationObserver::new((_, observer) => {
    // Reconciliation itself moves the SVG and installs toolbar nodes. Pause
    // this same observer while doing that so those owned mutations cannot
    // schedule a second component render.
    observer.disconnect()
    mount.refresh_content()
    mount.observe_content(observer)
    on_change()
  })
  let attach = () => {
    let next = @dom.document().get_element_by_id("transcript").to_option()
    guard !mount.is_same_element(next) else { return }
    content.disconnect()
    resize.disconnect()
    mount.replace(next)
    mount.observe_content(content)
    mount.observe_resize(resize)
    if next is Some(_) {
      on_change()
    }
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
pub extend Input with Eq::{equal, not_equal}

///|
pub extend ScrollPosition with Eq::{equal, not_equal}

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend VisibleRow with Eq::{equal, not_equal}
