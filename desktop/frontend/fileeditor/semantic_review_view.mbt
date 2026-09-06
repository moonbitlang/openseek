///|
using @cmd {trait Scheduler}

///|
/// The working-tree document behind Token/Tree's synthetic Modified models.
/// Historical comparisons and a deleted working file deliberately carry no
/// live document because current-checkout IDE requests would be misleading.
pub(all) struct SemanticReviewLiveDocument {
  resource : @common.Uri
  path : @pathx.Relative
} derive(Eq, Debug)

///|
/// The smallest input that can change a Token/Tree section plan. Layout is
/// deliberately absent: switching split/inline updates existing DiffEditors
/// and never reruns MoonDiff.
pub(all) struct SemanticReviewInput {
  old_name : String
  new_name : String
  old_source : String
  new_source : String
  mode : @moon_diff_provider.MoonDiffMode
  ignore_comments : Bool
  ignore_tests : Bool
  /// The working-tree file comments should name. History has no active review
  /// target; a deleted working file still does, even though it has no live
  /// Modified document for language requests.
  feedback_file : @pathx.Relative?
  live_modified : SemanticReviewLiveDocument?
} derive(Eq, Debug)

///|
fn ReviewDiffMode::semantic_mode(
  self : ReviewDiffMode,
) -> @moon_diff_provider.MoonDiffMode? {
  match self {
    ReviewDiffLine => None
    ReviewDiffToken => Some(@moon_diff_provider.Token)
    ReviewDiffTree => Some(@moon_diff_provider.Tree)
  }
}

///|
/// Extract the visible semantic comparison from either a working-tree review
/// or Git history. Line, source mode, non-MoonBit files, and unavailable text
/// deliberately produce no input.
fn semantic_review_input(state : State, ctx : Ctx) -> SemanticReviewInput? {
  guard state.review_diff_mode.semantic_mode() is Some(mode) else {
    return None
  }
  let (old_name, new_name, old_source, new_source, feedback_file, live_modified) = match
    ctx.active_history_diff {
    Some(diff) => {
      guard supports_moon_diff(diff.path.0) &&
        state.history_docs.get(history_diff_key(diff)) is Some(history) &&
        history.original.text() is Some(old_source) &&
        history.modified.text() is Some(new_source) else {
        return None
      }
      (
        diff.original_path.unwrap_or(diff.path).0,
        diff.path.0,
        old_source,
        new_source,
        None,
        None,
      )
    }
    None => {
      guard ctx.active_file is Some(path) &&
        supports_moon_diff(path.0) &&
        state.docs.get(path) is Some(doc) &&
        doc.visible_diff() is Some((old_source, new_source)) else {
        return None
      }
      let live_modified = match doc.state {
        TabLoaded(absolute~, ..) => Some({ resource: absolute, path, })
        TabDeleted
        | TabLoading
        | TabBinary
        | TabOversized
        | TabReadFailed(_)
        | TabUnavailable(_) => None
      }
      (doc.name, doc.name, old_source, new_source, Some(path), live_modified)
    }
  }
  Some({
    old_name,
    new_name,
    old_source,
    new_source,
    mode,
    ignore_comments: state.review_diff_ignore_comments,
    ignore_tests: state.review_diff_ignore_tests,
    feedback_file,
    live_modified,
  })
}

///|
/// Cache the expensive MoonDiff computation in panel state. The renderer and
/// imperative editor lifecycle consume the same immutable section plan.
fn State::sync_semantic_review(self : State, ctx : Ctx) -> State {
  let input = semantic_review_input(self, ctx)
  if input == self.semantic_review_input {
    return self
  }
  let plan = input.bind(input => {
    @moon_diff_provider.compute_sectioned_semantic_review_plan(
      input.old_source,
      input.new_source,
      input.mode,
      old_name=input.old_name,
      new_name=input.new_name,
      ignore_comments=input.ignore_comments,
      ignore_tests=input.ignore_tests,
    )
  })
  {
    ..self,
    semantic_review_input: input,
    semantic_review_plan: plan,
    semantic_review_collapsed: [],
  }
}

///|
fn semantic_range_label(
  range : @moon_diff_provider.SemanticReviewSourceRange,
) -> String {
  if range.line_count <= 1 {
    "L\{range.start_line_number}"
  } else {
    "L\{range.start_line_number}-\{range.start_line_number + range.line_count - 1}"
  }
}

///|
fn semantic_section_label(
  section : @moon_diff_provider.SemanticReviewSection,
) -> String {
  match (section.new_context, section.old_context, section.identity) {
    (Some(context), _, _) | (None, Some(context), _) => context
    (None, None, Some(identity)) => "Top-level #\{identity + 1}"
    (None, None, None) => "Whole file"
  }
}

///|
fn semantic_section_location(
  section : @moon_diff_provider.SemanticReviewSection,
) -> String {
  match (section.old_range, section.new_range) {
    (Some(old), Some(new)) =>
      "\{semantic_range_label(old)} → \{semantic_range_label(new)}"
    (Some(old), None) => semantic_range_label(old)
    (None, Some(new)) => semantic_range_label(new)
    (None, None) => ""
  }
}

///|
fn semantic_section_status(
  kind : @moon_diff_provider.SemanticReviewSectionKind,
) -> @html.Html {
  match kind {
    @moon_diff_provider.SemanticReviewSectionKind::Inserted =>
      @html.span(class="semantic-entry-status added", "A")
    @moon_diff_provider.SemanticReviewSectionKind::Deleted =>
      @html.span(class="semantic-entry-status deleted", "D")
    @moon_diff_provider.SemanticReviewSectionKind::Whole
    | @moon_diff_provider.SemanticReviewSectionKind::Matched => @html.nothing
  }
}

///|
fn semantic_editor_host_id(key : String) -> String {
  "semantic-diff-editor-\{key}"
}

///|
const SemanticReviewScrollWidthId = "semantic-review-scroll-width"

///|
/// Semantic fragments use side-specific schemes so the language registry can
/// expose current-checkout IDE actions on Modified without advertising them on
/// an Original revision that the host cannot answer for.
const SemanticReviewOriginalScheme = "openseek-semantic-diff-original"

///|
const SemanticReviewModifiedScheme = "openseek-semantic-diff-modified"

///|
priv enum SemanticReviewSide {
  SemanticReviewOriginal
  SemanticReviewModified
}

///|
fn semantic_fallback_notice(
  section : @moon_diff_provider.SemanticReviewSection,
  requested : @moon_diff_provider.MoonDiffMode,
) -> @html.Html {
  if section.fallbacks.is_empty() {
    return @html.nothing
  }
  let whole = section.kind
    is @moon_diff_provider.SemanticReviewSectionKind::Whole
  let tree = requested is @moon_diff_provider.Tree
  @html.div(
    class=if whole {
      "diff-notice fallback"
    } else {
      "diff-notice partial-fallback"
    },
    [
      @html.strong(
        if whole && tree {
          "Lexical fallback"
        } else if whole {
          "Sectioning fallback"
        } else if tree {
          "Section lexical fallback"
        } else {
          "Section diff fallback"
        },
      ),
      @html.span(section.fallbacks.join("; ")),
    ],
  )
}

///|
/// Rabbita owns only section chrome and this stable empty host. Source lines,
/// intraline spans, gutters, and alignment zones are all rendered by the real
/// DiffEditor mounted after paint.
fn semantic_section_view(
  dispatch : @cmd.Emit[Msg],
  section : @moon_diff_provider.SemanticReviewSection,
  requested : @moon_diff_provider.MoonDiffMode,
  collapsed : Bool,
) -> @html.Html {
  let label = semantic_section_label(section)
  let location = semantic_section_location(section)
  let content : Array[@html.Html] = [
    semantic_fallback_notice(section, requested),
    @html.div(
      class="semantic-entry-editor-parent",
      @html.div(
        attrs=@html.Attrs::build()
          .id(semantic_editor_host_id(section.key))
          .class("semantic-diff-editor-host")
          .data_set("semantic-section", section.key),
        ([] : Array[@html.Html]),
      ),
    ),
  ]
  @html.section(
    class=if collapsed {
      "semantic-diff-entry collapsed"
    } else {
      "semantic-diff-entry"
    },
    attrs=@html.Attrs::build().data_set("semantic-entry", section.key),
    [
      @html.header(
        class="semantic-entry-header",
        @html.button(
          type_="button",
          class="semantic-entry-header-content",
          title=if location.is_empty() {
            label
          } else {
            "\{label} · \{location}"
          },
          on_click=dispatch(SemanticReviewSectionToggled(section.key)),
          attrs=@html.Attrs::build()
            .aria_expanded((!collapsed).to_string())
            .aria_label(
              if collapsed {
                "Expand \{label}"
              } else {
                "Collapse \{label}"
              },
            ),
          [
            @html.span(
              class=if collapsed {
                "codicon codicon-chevron-right semantic-entry-chevron"
              } else {
                "codicon codicon-chevron-down semantic-entry-chevron"
              },
              "",
            ),
            @html.span(class="semantic-entry-file-icon", ""),
            @html.span(class="semantic-entry-path", [
              @html.span(class="semantic-entry-label", label),
              @html.span(class="semantic-entry-location", location),
            ]),
            semantic_section_status(section.kind),
          ],
        ),
      ),
      @html.div(class="semantic-entry-content", content),
    ],
  )
}

///|
fn semantic_empty_view(message : String) -> @html.Html {
  @html.div(class="semantic-empty", [@html.p(message)])
}

///|
fn semantic_status_empty_view(
  plan : @moon_diff_provider.SectionedSemanticReviewPlan,
  input : SemanticReviewInput,
) -> @html.Html? {
  match plan.status {
    @moon_diff_provider.SemanticReviewStatus::IgnoredOnly => {
      let subject = if input.ignore_comments && input.ignore_tests {
        "comments, blank lines, or test blocks"
      } else if input.ignore_tests {
        "test blocks"
      } else {
        "comments or blank lines"
      }
      Some(
        semantic_empty_view(
          "No changes besides ignored \{subject} were found. Turn off the relevant Ignore filter to view them.",
        ),
      )
    }
    @moon_diff_provider.SemanticReviewStatus::Identical =>
      Some(
        semantic_empty_view(
          if input.mode is @moon_diff_provider.Tree {
            "No structural changes found. Switch to Token or Line to inspect text."
          } else {
            "No token changes found."
          },
        ),
      )
    @moon_diff_provider.SemanticReviewStatus::NoStructuralChanges =>
      Some(
        semantic_empty_view(
          if input.mode is @moon_diff_provider.Tree {
            "No structural changes found. Switch to Token to view text changes."
          } else {
            "No declaration-owned token changes found. Switch to Line to inspect the complete file."
          },
        ),
      )
    @moon_diff_provider.SemanticReviewStatus::Changed
    | @moon_diff_provider.SemanticReviewStatus::Reordered => None
  }
}

///|
fn semantic_plan_view(
  dispatch : @cmd.Emit[Msg],
  plan : @moon_diff_provider.SectionedSemanticReviewPlan,
  input : SemanticReviewInput,
  collapsed : Array[String],
) -> @html.Html {
  if semantic_status_empty_view(plan, input) is Some(empty) {
    return empty
  }
  let sections : Map[String, @html.Html] = Map([])
  if plan.reordered {
    sections["reordered"] = @html.div(
      class="semantic-reorder",
      "Top-level declarations are reordered; each declaration keeps its own DiffEditor.",
    )
  }
  for section in plan.main_sections {
    sections["main:\{section.key}"] = semantic_section_view(
      dispatch,
      section,
      plan.requested,
      collapsed.contains(section.key),
    )
  }
  // Deleted identities cannot participate in the new-side order. Like VS
  // Code's multi-diff items, keep them in the same flat item list and use a D
  // status rather than introducing a second visual document hierarchy.
  for section in plan.deleted_sections {
    sections["deleted:\{section.key}"] = semantic_section_view(
      dispatch,
      section,
      plan.requested,
      collapsed.contains(section.key),
    )
  }
  if sections.is_empty() {
    semantic_empty_view(
      "No semantic section changes found. Switch to Line to inspect the complete file.",
    )
  } else {
    @html.div(class="semantic-document", sections)
  }
}

///|
/// Render section metadata and stable DiffEditor mount points. Source text is
/// intentionally absent from this HTML tree.
pub fn semantic_review_view(
  dispatch : @cmd.Emit[Msg],
  state : State,
) -> @html.Html {
  guard state.semantic_review_input is Some(input) else { return @html.nothing }
  guard state.semantic_review_plan is Some(plan) else {
    return @html.div(class="semantic-review", [
      semantic_empty_view(
        "The semantic result was invalid. Switch to Line to inspect the complete file.",
      ),
    ])
  }
  @html.div(
    class="semantic-review",
    attrs=@html.Attrs::build()
      .data_set(
        "mode",
        if input.mode is @moon_diff_provider.Token {
          "token"
        } else {
          "tree"
        },
      )
      .data_set(
        "layout",
        if state.review_diff_layout is ReviewSideBySide {
          "split"
        } else {
          "unified"
        },
      ),
    [
      semantic_plan_view(dispatch, plan, input, state.semantic_review_collapsed),
      // VS Code's MultiDiffEditor owns one horizontal scroll extent. The
      // imperative lifecycle sizes this otherwise invisible element from the
      // widest local DiffEditor and mirrors the outer scrollLeft into all
      // entries.
      @html.div(
        attrs=@html.Attrs::build()
          .id(SemanticReviewScrollWidthId)
          .class("semantic-review-scroll-width")
          .aria_hidden("true"),
        ([] : Array[@html.Html]),
      ),
    ],
  )
}

///|
priv struct SemanticReviewEditorHost {
  section : @moon_diff_provider.SemanticReviewSection
  old_name : String
  new_name : String
  feedback_file : @pathx.Relative?
  live_modified : SemanticReviewLiveDocument?
  host : @dom.Element
  editor : @viewer.DiffEditor
  provider : @moon_diff_provider.MoonFragmentDiffProvider?
  diff_subscription : @common.Disposable
  content_height_subscription : @common.Disposable
  navigation_reveal_subscription : @common.Disposable
  pending_navigation_reveal_generation : Ref[Int?]
  focus_subscription : @common.Disposable
}

///|
let semantic_review_editors : Map[String, SemanticReviewEditorHost] = Map([])

///|
let semantic_review_order : Array[String] = []

///|
let semantic_review_active_key : Ref[String?] = Ref(None)

///|
/// Fences deferred reveal events and animation frames across rapid navigation,
/// section replacement, and surface teardown.
let semantic_review_navigation_generation : Ref[Int] = Ref(0)

///|
priv enum SemanticReviewNavigationDirection {
  SemanticReviewPrevious
  SemanticReviewNext
}

///|
priv suberror SemanticReviewNavigationSubscription {
  SemanticReviewNavigationSubscription(@cmd.Emit[Msg])
}

///|
fn semantic_review_navigation_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    SemanticReviewNavigationSubscription(dispatch) => {
      let mut dispatch = dispatch
      let target = @dom.document().as_event_target()
      let listener : @dom.Listener = event => {
        guard event.to_keyboard_event() is Some(keyboard) &&
          keyboard.key() == "F7" &&
          @dom.document().get_element_by_id(SemanticReviewHostId).to_option()
          is Some(host) &&
          @base_browser.event_target_has_matching_ancestor(
            event, host, ".semantic-diff-editor-host",
          ) else {
          return
        }
        // Capture runs before the child DiffEditor performs its own cyclic F7
        // command, so exactly one aggregate MultiDiff navigation is emitted.
        event.prevent_default()
        event.stop_propagation()
        scheduler.add(
          dispatch(
            if keyboard.shift_key() {
              RevealPreviousReviewDiffChange
            } else {
              RevealNextReviewDiffChange
            },
          ),
        )
      }
      target.add_event_listener_with_options("keydown", listener, capture=true)
      Some({
        unload: _ => {
          target.remove_event_listener_with_options(
            "keydown",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is SemanticReviewNavigationSubscription(next) else {
            return
          }
          dispatch = next
        },
      })
    }
    _ => None
  }
}

///|
fn semantic_review_navigation_subscription(
  state : State,
  ctx : Ctx,
  dispatch : @cmd.Emit[Msg],
) -> @sub.Sub {
  guard review_diff_navigation_enabled(state, ctx) &&
    !line_diff_ready(state, ctx) else {
    return @sub.none
  }
  @sub.custom_sub(
    "fileeditor-semantic-review-navigation",
    @sub.Local,
    SemanticReviewNavigationSubscription(dispatch),
    semantic_review_navigation_sub_loader,
  )
}

///|
fn update_semantic_review_scroll_width() -> Unit {
  guard @dom.document().get_element_by_id(SemanticReviewHostId).to_option()
    is Some(host) &&
    @dom.document().get_element_by_id(SemanticReviewScrollWidthId).to_option()
    is Some(spacer) else {
    return
  }
  let mut max_scroll = 0.0
  for _, entry in semantic_review_editors {
    if @base_browser.element_is_connected(entry.host) {
      max_scroll = max_scroll.max(entry.editor.get_max_scroll_left())
    }
  }
  @base_browser.set_style_property(
    spacer,
    "width",
    "\{(host.get_client_width() + max_scroll).ceil()}px",
  )
  sync_semantic_review_scroll_left(host.get_scroll_left())
}

///|
/// Project the single outer MultiDiffEditor scrollbar into every item. This
/// mirrors VS Code's `VirtualizedViewItem.setScrollLeft` without exposing each
/// DiffEditor's own horizontal scrollbar.
fn sync_semantic_review_scroll_left(scroll_left : Double) -> Unit {
  // A native overflow element supplies the one visible scrollbar, but VS
  // Code's SmoothScrollableElement does not translate the MultiDiff item DOM.
  // Counter the browser's native translation, then project the offset into
  // every DiffEditor so headers stay put and code moves exactly once.
  if @dom.document().get_element_by_id(SemanticReviewHostId).to_option()
    is Some(host) &&
    host.query_selector(".semantic-document") is Some(document) {
    @base_browser.set_style_property(
      document,
      "transform",
      "translateX(\{scroll_left}px)",
    )
  }
  for _, entry in semantic_review_editors {
    entry.editor.set_scroll_left(scroll_left)
  }
}

///|
fn semantic_diff_options(
  layout : ReviewDiffLayout,
) -> @viewer.DiffEditorOptions {
  @viewer.DiffEditorOptions(
    editor_options=current_diff_pane_options(),
    layout=match layout {
      ReviewSideBySide => @viewer.SideBySide
      ReviewInline => @viewer.Inline
    },
    automatic_inline=false,
    sash_enabled=true,
    diff_word_wrap=@viewer.Off,
    overview_ruler=false,
    render_indicators=true,
    render_markdown_comments=true,
    handle_mouse_wheel=false,
    // Token/Tree use the same rich, initially folded Markdown-comment
    // presentation as ordinary code reading and Line diff. MoonDiff has already
    // decided which sections exist, so presentation must not fall back to raw
    // `///` rows. The outer MultiDiff scroll plane owns wheel input, matching
    // VS Code's per-item `handleMouseWheel: false` configuration.
  )
}

///|
fn semantic_model_uri(side : SemanticReviewSide, key : String) -> @common.Uri? {
  let uri = @common.Uri::from(
    scheme=match side {
      SemanticReviewOriginal => SemanticReviewOriginalScheme
      SemanticReviewModified => SemanticReviewModifiedScheme
    },
    path="/\{key}.mbt",
  ) catch {
    _ => return None
  }
  Some(uri)
}

///|
/// Map one section-local side back into its physical source line domain.
/// Whole-file fallback keeps full-file coordinates; top-level sections carry
/// their own old/new ranges, and an absent side remains absent.
fn semantic_feedback_line_offset(
  section : @moon_diff_provider.SemanticReviewSection,
  side : SemanticReviewSide,
) -> Int? {
  if section.kind is @moon_diff_provider.SemanticReviewSectionKind::Whole {
    return Some(0)
  }
  let range = match side {
    SemanticReviewOriginal => section.old_range
    SemanticReviewModified => section.new_range
  }
  match range {
    Some(range) if range.start_line_number > 0 =>
      Some(range.start_line_number - 1)
    _ => None
  }
}

///|
/// Historical sections and physically absent/empty sides must not advertise
/// the selection-driven feedback UI.
fn semantic_feedback_side_enabled(
  feedback_file : @pathx.Relative?,
  section : @moon_diff_provider.SemanticReviewSection,
  side : SemanticReviewSide,
) -> Bool {
  guard feedback_file is Some(_) &&
    semantic_feedback_line_offset(section, side) is Some(_) else {
    return false
  }
  match side {
    SemanticReviewOriginal => !section.original_source.is_empty()
    SemanticReviewModified => !section.modified_source.is_empty()
  }
}

///|
fn project_semantic_feedback_range(
  range : @common.Range,
  line_offset : Int,
) -> @common.Range {
  @common.Range(
    range.start_line_number + line_offset,
    range.start_column,
    range.end_line_number + line_offset,
    range.end_column,
  )
}

///|
/// Preserve the existing full-diff comment contract: Modified feedback owns
/// an exact working-tree range, while Original feedback retains revision-side
/// identity without pretending that range exists in the working document.
fn semantic_feedback_message(
  file : @pathx.Relative,
  side : SemanticReviewSide,
  range : @common.Range,
  quote : String,
  comment : String,
  resource : ModelUri,
  feedback_id : String,
) -> Msg {
  match side {
    SemanticReviewModified =>
      EditorCommentAdded(
        resource~,
        file~,
        range~,
        quote~,
        comment~,
        feedback_id~,
      )
    SemanticReviewOriginal =>
      diff_comment_message(
        file,
        original_line_number=Some(range.start_line_number),
        modified_line_number=None,
        quote~,
        comment~,
        resource~,
        feedback_id~,
      )
  }
}

///|
priv struct SemanticFeedbackModelProjection {
  model : @model.TextModel
  file : @pathx.Relative
  side : SemanticReviewSide
  line_offset : Int
}

///|
/// Resolve only mounted working-tree semantic models. History and an absent
/// one-sided model stay non-commentable even though their DiffEditor kernels
/// still exist for rendering.
fn semantic_feedback_model_projection(
  resource : @common.Uri,
) -> SemanticFeedbackModelProjection? {
  for _, entry in semantic_review_editors {
    guard entry.feedback_file is Some(file) &&
      entry.editor.get_model() is Some(pair) else {
      continue
    }
    for side in [SemanticReviewOriginal, SemanticReviewModified] {
      guard semantic_feedback_side_enabled(Some(file), entry.section, side) &&
        semantic_feedback_line_offset(entry.section, side) is Some(line_offset) else {
        continue
      }
      let model = match side {
        SemanticReviewOriginal => pair.original
        SemanticReviewModified => pair.modified
      }
      if model.uri.to_string() == resource.to_string() {
        return Some({ model, file, side, line_offset, })
      }
    }
  }
  None
}

///|
fn sync_semantic_feedback(
  services : DesktopViewerServices,
  feedback_file : @pathx.Relative?,
  section : @moon_diff_provider.SemanticReviewSection,
  original : @model.TextModel,
  modified : @model.TextModel,
) -> Unit {
  services.feedback.set_feedback_enabled(
    original.uri,
    semantic_feedback_side_enabled(
      feedback_file,
      section,
      SemanticReviewOriginal,
    ),
  )
  services.feedback.set_feedback_enabled(
    modified.uri,
    semantic_feedback_side_enabled(
      feedback_file,
      section,
      SemanticReviewModified,
    ),
  )
}

///|
/// The semantic model's line numbers are local to one MoonDiff section. Keep
/// the projection explicit instead of making a fragment impersonate the full
/// working file: the host IDE receives the real path and global line number,
/// while the editor continues rendering the section-local diff document.
priv struct SemanticModifiedModelProjection {
  resource : @common.Uri
  path : @pathx.Relative
  line_offset : Int
}

///|
fn @moon_diff_provider.SemanticReviewSection::modified_line_offset(
  self : @moon_diff_provider.SemanticReviewSection,
) -> Int? {
  semantic_feedback_line_offset(self, SemanticReviewModified)
}

///|
/// Resolve only the Modified model of a currently mounted working-tree
/// section. Original and historical models intentionally return `None`.
fn semantic_modified_model_projection(
  model : @model.TextModel,
) -> SemanticModifiedModelProjection? {
  for _, entry in semantic_review_editors {
    match
      (
        entry.live_modified,
        entry.section.modified_line_offset(),
        entry.editor.get_model(),
      ) {
      (Some(live), Some(line_offset), Some(pair)) if pair.modified.same(model) =>
        return Some({ resource: live.resource, path: live.path, line_offset, })
      _ => ()
    }
  }
  None
}

///|
/// Project full-file diagnostics into one section-local Modified model. A
/// diagnostic outside the section is absent; one crossing a section boundary
/// is clipped to the visible model before `TextModel::validate_range` clamps
/// UTF-16 columns against the actual fragment text.
fn project_semantic_modified_diagnostics(
  diagnostics : ArrayView[@language.Diagnostic],
  model : @model.TextModel,
  line_offset : Int,
) -> Array[@language.Diagnostic] {
  let projected : Array[@language.Diagnostic] = []
  let line_count = model.get_line_count()
  for diagnostic in diagnostics {
    let local_start = diagnostic.range.start_line_number - line_offset
    let local_end = diagnostic.range.end_line_number - line_offset
    if local_end < 1 || local_start > line_count {
      continue
    }
    let start_line = local_start.max(1)
    let end_line = local_end.min(line_count)
    let range = model.validate_range(
      @common.Range(
        start_line,
        if local_start < 1 {
          1
        } else {
          diagnostic.range.start_column
        },
        end_line,
        if local_end > line_count {
          model.get_line_max_column(end_line)
        } else {
          diagnostic.range.end_column
        },
      ),
    )
    projected.push({ ..diagnostic, range, })
  }
  projected
}

///|
/// Seed or refresh the synthetic Modified resource from the diagnostics
/// already owned by the live working model. The shared marker service then
/// drives the ordinary diff-pane marker contribution without teaching the
/// reusable Viewer about OpenSeek's fragment projection.
fn sync_semantic_modified_diagnostics(
  services : DesktopViewerServices,
  live_modified : SemanticReviewLiveDocument?,
  section : @moon_diff_provider.SemanticReviewSection,
  model : @model.TextModel,
) -> Unit {
  guard live_modified is Some(live) &&
    section.modified_line_offset() is Some(line_offset) else {
    services.markers.remove_owner_resource(DiagnosticsOwner, model.uri)
    return
  }
  let diagnostics = services.markers.diagnostics_for_resource(live.resource)
  services.markers.set_diagnostics(
    DiagnosticsOwner,
    model.uri,
    project_semantic_modified_diagnostics(diagnostics, model, line_offset),
  )
}

///|
/// Refresh every mounted section backed by `resource` after the live LSP
/// diagnostic batch changes.
fn refresh_semantic_modified_diagnostics(resource : @common.Uri) -> Unit {
  guard viewer_state.services is Some(services) else { return }
  for _, entry in semantic_review_editors {
    guard entry.live_modified is Some(live) &&
      live.resource == resource &&
      entry.editor.get_model() is Some(pair) else {
      continue
    }
    sync_semantic_modified_diagnostics(
      services,
      entry.live_modified,
      entry.section,
      pair.modified,
    )
  }
}

///|
fn semantic_estimated_height(
  section : @moon_diff_provider.SemanticReviewSection,
  layout : ReviewDiffLayout,
) -> Double {
  let old_lines = section.original_source.split("\n").length()
  let new_lines = section.modified_source.split("\n").length()
  let lines = match layout {
    ReviewSideBySide => old_lines.max(new_lines)
    ReviewInline => old_lines + new_lines
  }
  (lines.max(1).to_double() * 20.0 + 8.0).max(40.0)
}

///|
/// The child scroll target produced by Line diff's `Center` reveal for an
/// explicit viewport. This is the relevant subset of
/// `ViewLayout::compute_scroll_top_to_reveal_range`: oversized ranges align at
/// the top, ordinary ranges center, and the result clamps to the child extent.
fn semantic_review_child_scroll_top_to_reveal(
  viewport_height : Double,
  content_height : Double,
  reveal_top : Double,
  reveal_bottom : Double,
) -> Double {
  if viewport_height <= 0.0 {
    return 0.0
  }
  let box_start = reveal_top
  let box_end = reveal_bottom.max(reveal_top)
  let target = if box_end - box_start > viewport_height {
    box_start
  } else {
    (box_start + box_end - viewport_height) / 2.0
  }
  target.clamp(min=0.0, max=(content_height - viewport_height).max(0.0))
}

///|
/// Apply the child reveal as a delta to Token/Tree's outer scroll position.
/// VS Code's `diffEditorItemTemplate.ts` forwards exactly
/// `newChildScrollTop - lastChildScrollTop` to the MultiDiff parent, while
/// `multiDiffEditorWidgetImpl.ts::render` constrains each child to the outer
/// viewport minus its item chrome. Our items use natural DOM flow instead of
/// virtualization, so this function reconstructs those same current/target
/// child offsets and returns the resulting outer scroll position.
fn semantic_review_scroll_top_after_child_reveal(
  outer_scroll_top : Double,
  outer_viewport_height : Double,
  item_content_top : Double,
  item_content_height : Double,
  editor_content_top : Double,
  sticky_chrome_height : Double,
  reveal_top : Double,
  reveal_bottom : Double,
) -> Double {
  let item_viewport_height = item_content_height
    .min(outer_viewport_height)
    .max(0.0)
  let child_viewport_height = (item_viewport_height - sticky_chrome_height).max(
    0.0,
  )
  if child_viewport_height <= 0.0 {
    return outer_scroll_top.max(0.0)
  }
  // Notices before the editor are ordinary scrolling content, not sticky
  // chrome. Shift the editor-local reveal box through that prefix while only
  // reserving the actual sticky header from the child viewport.
  let scrolling_prefix_height = (editor_content_top -
  item_content_top -
  sticky_chrome_height).max(0.0)
  let child_content_height = (item_content_height - sticky_chrome_height).max(
    0.0,
  )
  let max_child_scroll = (child_content_height - child_viewport_height).max(0.0)
  let needs_origin = semantic_review_item_needs_navigation_origin(
    outer_scroll_top, outer_viewport_height, item_content_top, item_content_height,
  )
  let projection_outer_scroll_top = if needs_origin {
    item_content_top
  } else {
    outer_scroll_top
  }
  let current_child_scroll = if needs_origin {
    0.0
  } else {
    (outer_scroll_top - item_content_top).clamp(min=0.0, max=max_child_scroll)
  }
  let target_child_scroll = semantic_review_child_scroll_top_to_reveal(
    child_viewport_height,
    child_content_height,
    scrolling_prefix_height + reveal_top,
    scrolling_prefix_height + reveal_bottom,
  )
  (projection_outer_scroll_top + target_child_scroll - current_child_scroll).max(
    0.0,
  )
}

///|
/// Project one child DiffEditor's centered reveal into Token/Tree's single
/// outer vertical scroll plane. Two frame boundaries let the reveal's paired
/// content-height publication and editor layout commit first; pixel bounds are
/// deliberately re-measured in the second frame so Markdown/ViewZone geometry
/// cannot go stale between the reveal event and the parent scroll.
fn schedule_semantic_review_reveal_scroll(
  key : String,
  editor_host : @dom.Element,
  editor : @viewer.DiffEditor,
  event : @viewer.DiffEditorRevealEvent,
  generation : Int,
) -> Unit {
  @dom.window().request_animation_frame(_ => {
    guard semantic_review_navigation_generation.val == generation &&
      semantic_review_active_key.val == Some(key) &&
      @base_browser.element_is_connected(editor_host) else {
      return
    }
    @dom.window().request_animation_frame(_ => {
      guard semantic_review_navigation_generation.val == generation &&
        semantic_review_active_key.val == Some(key) &&
        @base_browser.element_is_connected(editor_host) &&
        @dom.document().get_element_by_id(SemanticReviewHostId).to_option()
        is Some(scroll_host) &&
        editor_host.closest(".semantic-diff-entry") is Some(item) &&
        item.query_selector(".semantic-entry-header") is Some(header) &&
        editor.get_modified_vertical_reveal_bounds(event.modified_range)
        is Some((reveal_top, reveal_bottom)) else {
        return
      }
      let viewport_height = scroll_host.get_client_height()
      let editor_content_height = editor.get_content_height()
      if viewport_height <= 0.0 ||
        item.get_client_height() <= 0.0 ||
        editor_host.get_client_height() <= 0.0 ||
        editor_content_height <= 0.0 {
        return
      }
      let outer_scroll_top = scroll_host.get_scroll_top()
      let scroll_rect = scroll_host.get_bounding_client_rect()
      let item_rect = item.get_bounding_client_rect()
      let editor_rect = editor_host.get_bounding_client_rect()
      let item_content_top = outer_scroll_top +
        item_rect.get_top() -
        scroll_rect.get_top()
      let editor_content_top = outer_scroll_top +
        editor_rect.get_top() -
        scroll_rect.get_top()
      scroll_host.set_scroll_top(
        semantic_review_scroll_top_after_child_reveal(
          outer_scroll_top,
          viewport_height,
          item_content_top,
          item.get_client_height(),
          editor_content_top,
          header.get_client_height(),
          reveal_top,
          reveal_bottom,
        ),
      )
    })
    |> ignore
  })
  |> ignore
}

///|
/// VS Code's cross-item `_goToFile` first reveals the destination item at its
/// content start; the child editor's subsequent centered reveal contributes a
/// local scroll delta. Do the same before requesting first/last in a section.
fn reveal_semantic_review_item_start(editor_host : @dom.Element) -> Unit {
  guard @dom.document().get_element_by_id(SemanticReviewHostId).to_option()
    is Some(scroll_host) &&
    editor_host.closest(".semantic-diff-entry") is Some(item) else {
    return
  }
  let scroll_rect = scroll_host.get_bounding_client_rect()
  let item_rect = item.get_bounding_client_rect()
  scroll_host.set_scroll_top(
    scroll_host.get_scroll_top() + item_rect.get_top() - scroll_rect.get_top(),
  )
}

///|
/// A focused MultiDiff item can be moved out of the outer viewport with the
/// wheel while remaining the active navigation item. VS Code materializes and
/// reveals such an item before asking its child to navigate. A short item also
/// needs to be fully visible because it has no child scroll range with which to
/// contribute a corrective delta.
fn semantic_review_item_needs_navigation_origin(
  outer_scroll_top : Double,
  outer_viewport_height : Double,
  item_content_top : Double,
  item_content_height : Double,
) -> Bool {
  if outer_viewport_height <= 0.0 || item_content_height <= 0.0 {
    return false
  }
  let outer_bottom = outer_scroll_top + outer_viewport_height
  let item_bottom = item_content_top + item_content_height
  if item_content_height <= outer_viewport_height {
    item_content_top < outer_scroll_top || item_bottom > outer_bottom
  } else {
    // Delta projection is valid only while the parent's local offset lies in
    // the long child's real scroll band, i.e. while the viewport is fully
    // contained by the item. A sliver at either edge still represents a
    // clamped child offset and must be re-originated first.
    outer_scroll_top < item_content_top || outer_bottom > item_bottom
  }
}

///|
/// Commit one final DiffEditor height to its MultiDiff item. The content-height
/// event can arrive while `create_semantic_review_editor` is still constructing
/// the map entry, so this helper deliberately captures the concrete host and
/// editor instead of looking them up by key.
fn apply_semantic_review_editor_height(
  host : @dom.Element,
  editor : @viewer.DiffEditor,
  content_height : Double,
) -> Unit {
  if !@base_browser.element_is_connected(host) {
    return
  }
  if content_height <= 0.0 {
    return
  }
  let height = (content_height.ceil() + 2.0).max(40.0)
  let css_height = "\{height}px"
  if @base_browser.element_style_value(host, "height") != css_height {
    @base_browser.set_style_property(host, "height", css_height)
    editor.layout()
  }
}

///|
fn schedule_semantic_review_scroll_width_update() -> Unit {
  @dom.window().request_animation_frame(_ => {
    update_semantic_review_scroll_width()
    @dom.window().request_animation_frame(_ => {
      update_semantic_review_scroll_width()
    })
    |> ignore
  })
  |> ignore
}

///|
fn dispose_semantic_review_editor(entry : SemanticReviewEditorHost) -> Unit {
  semantic_review_navigation_generation.val += 1
  entry.diff_subscription.dispose()
  entry.content_height_subscription.dispose()
  entry.pending_navigation_reveal_generation.val = None
  entry.navigation_reveal_subscription.dispose()
  entry.focus_subscription.dispose()
  match entry.editor.set_model(None) {
    Some(previous) => {
      if viewer_state.services is Some(services) {
        services.markers.remove_owner_resource(
          DiagnosticsOwner,
          previous.modified.uri,
        )
        services.feedback.set_feedback_enabled(previous.original.uri, false)
        services.feedback.set_feedback_enabled(previous.modified.uri, false)
        services.feedback.clear_feedback(previous.original.uri)
        services.feedback.clear_feedback(previous.modified.uri)
      }
      dispose_diff_comparison_models(previous)
    }
    None => ()
  }
  entry.editor.dispose()
  // Keep the concrete fragment provider alive until after DiffEditor has
  // disposed its ViewModel and provider subscription.
  match entry.provider {
    Some(_) => ()
    None => ()
  }
}

///|
fn create_semantic_review_editor(
  input : SemanticReviewInput,
  section : @moon_diff_provider.SemanticReviewSection,
  layout : ReviewDiffLayout,
  host : @dom.Element,
) -> SemanticReviewEditorHost? {
  guard semantic_model_uri(SemanticReviewOriginal, section.key)
    is Some(original_uri) &&
    semantic_model_uri(SemanticReviewModified, section.key)
    is Some(modified_uri) &&
    viewer_state.services is Some(services) else {
    return None
  }
  viewer_state.version = viewer_state.version + 1
  let version = viewer_state.version
  let original = @model.TextModel(
    original_uri,
    input.old_name,
    "moonbit",
    version,
    "semantic-old-v\{version}",
    section.original_source,
  )
  let modified = @model.TextModel(
    modified_uri,
    input.new_name,
    "moonbit",
    version,
    "semantic-new-v\{version}",
    section.modified_source,
  )
  @base_browser.set_style_property(
    host,
    "height",
    "\{semantic_estimated_height(section, layout)}px",
  )
  let (editor, provider) = match section.diff {
    @moon_diff_provider.SemanticReviewDiff::Line =>
      (
        @viewer.DiffEditor::create(
          host,
          services=services.viewer_services,
          options=semantic_diff_options(layout),
        ),
        None,
      )
    @moon_diff_provider.SemanticReviewDiff::Fragment(document) => {
      let provider = @moon_diff_provider.MoonFragmentDiffProvider(document)
      (
        @viewer.DiffEditor::create(
          host,
          services=services.viewer_services,
          options=semantic_diff_options(layout),
          provider=provider.as_document_diff_provider(),
        ),
        Some(provider),
      )
    }
  }
  let key = section.key
  // Diff readiness still owns the post-render horizontal overflow refresh.
  // Vertical Markdown/ViewZone changes use the paired content-height event
  // below and do not wait for these compatibility layout frames.
  let diff_subscription = editor.on_did_update_diff(() => {
    schedule_semantic_review_scroll_width_update()
  })
  // DiffEditor publishes only after the comment ViewZone and both panes'
  // derived alignment zones have committed. Resize synchronously in that same
  // geometry batch; a delayed retry would only hide a missing notification and
  // leave this MultiDiff item displaying a stale intermediate height.
  let content_height_subscription = editor.on_did_change_content_height(content_height => {
    apply_semantic_review_editor_height(host, editor, content_height)
    update_semantic_review_scroll_width()
  })
  let pending_navigation_reveal_generation : Ref[Int?] = Ref(None)
  let navigation_reveal_subscription = editor.on_did_reveal_change(event => {
    guard pending_navigation_reveal_generation.val is Some(generation) else {
      return
    }
    pending_navigation_reveal_generation.val = None
    schedule_semantic_review_reveal_scroll(key, host, editor, event, generation)
  })
  let focus_listener : @dom.Listener = _ => {
    semantic_review_active_key.val = Some(key)
  }
  host.add_event_listener("focusin", focus_listener)
  let focus_subscription = @common.Disposable::from(() => {
    host.remove_event_listener("focusin", focus_listener)
  })
  editor.set_model(Some(@viewer.DiffEditorModel(original, modified))) |> ignore
  sync_semantic_feedback(
    services,
    input.feedback_file,
    section,
    original,
    modified,
  )
  sync_semantic_modified_diagnostics(
    services,
    input.live_modified,
    section,
    modified,
  )
  // Each VS Code multi-diff item opens on its own first change. Without this,
  // a comment-only section can initially show only the unchanged declaration
  // body below the changed documentation comment.
  editor.reveal_first_diff()
  Some({
    section,
    old_name: input.old_name,
    new_name: input.new_name,
    feedback_file: input.feedback_file,
    live_modified: input.live_modified,
    host,
    editor,
    provider,
    diff_subscription,
    content_height_subscription,
    navigation_reveal_subscription,
    pending_navigation_reveal_generation,
    focus_subscription,
  })
}

///|
fn semantic_sections(
  plan : @moon_diff_provider.SectionedSemanticReviewPlan?,
) -> Array[@moon_diff_provider.SemanticReviewSection] {
  guard plan is Some(plan) else { return [] }
  let sections = plan.main_sections.copy()
  sections.append(plan.deleted_sections)
  sections
}

///|
fn layout_semantic_review_editors() -> Unit {
  for _, entry in semantic_review_editors {
    entry.editor.layout()
  }
  update_semantic_review_scroll_width()
  schedule_semantic_review_scroll_width_update()
}

///|
fn update_semantic_review_editor_layout(layout : ReviewDiffLayout) -> Unit {
  for _, entry in semantic_review_editors {
    entry.editor.update_options(semantic_diff_options(layout))
    entry.editor.layout()
  }
  update_semantic_review_scroll_width()
  schedule_semantic_review_scroll_width_update()
}

///|
fn refresh_semantic_review_editor_options() -> Unit {
  for _, entry in semantic_review_editors {
    let layout = match entry.editor.get_layout() {
      @viewer.SideBySide => ReviewSideBySide
      @viewer.Inline => ReviewInline
    }
    entry.editor.update_options(semantic_diff_options(layout))
    entry.editor.layout()
  }
  update_semantic_review_scroll_width()
  schedule_semantic_review_scroll_width_update()
}

///|
/// Retire one mounted section widget and drop its map entry.
fn remove_semantic_review_editor(key : String) -> Unit {
  if semantic_review_editors.get(key) is Some(entry) {
    dispose_semantic_review_editor(entry)
    semantic_review_editors.remove(key)
  }
}

///|
fn clear_semantic_review_editors() -> Unit {
  semantic_review_navigation_generation.val += 1
  let keys = [ for key, _ in semantic_review_editors => key ]
  for key in keys {
    remove_semantic_review_editor(key)
  }
  semantic_review_order.clear()
  semantic_review_active_key.val = None
  update_semantic_review_scroll_width()
}

///|
fn semantic_review_navigation_index(current : String?) -> Int {
  guard current is Some(current) else { return 0 }
  let index = semantic_review_order.search(current)
  index.unwrap_or(0)
}

///|
fn arm_semantic_review_navigation_reveal(
  entry : SemanticReviewEditorHost,
) -> Unit {
  semantic_review_navigation_generation.val += 1
  entry.pending_navigation_reveal_generation.val = Some(
    semantic_review_navigation_generation.val,
  )
}

///|
/// Move within the focused DiffEditor first, then cycle across Token/Tree
/// items exactly like VS Code's MultiDiffEditor navigation action.
fn navigate_semantic_review_change(
  dispatch : @cmd.Emit[Msg],
  collapsed : Array[String],
  direction : SemanticReviewNavigationDirection,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard !semantic_review_order.is_empty() else { return }
    let index = semantic_review_navigation_index(semantic_review_active_key.val)
    let current = semantic_review_order[index]
    if !collapsed.contains(current) &&
      semantic_review_editors.get(current) is Some(entry) {
      arm_semantic_review_navigation_reveal(entry)
      let revealed = match direction {
        SemanticReviewPrevious =>
          entry.editor.reveal_previous_change_without_wrap()
        SemanticReviewNext => entry.editor.reveal_next_change_without_wrap()
      }
      if revealed {
        semantic_review_active_key.val = Some(current)
        entry.editor.focus()
        return
      }
      entry.pending_navigation_reveal_generation.val = None
    }
    let target_index = match direction {
      SemanticReviewPrevious =>
        if index == 0 {
          semantic_review_order.length() - 1
        } else {
          index - 1
        }
      SemanticReviewNext => (index + 1) % semantic_review_order.length()
    }
    scheduler.add(
      dispatch(
        RevealSemanticReviewSectionChange(
          semantic_review_order[target_index],
          direction is SemanticReviewPrevious,
        ),
      ),
    )
  })
}

///|
/// Complete a cross-item navigation after Rabbita has expanded and committed
/// the destination section.
fn reveal_semantic_review_section_change(
  key : String,
  reveal_last : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      guard semantic_review_editors.get(key) is Some(entry) &&
        @base_browser.element_is_connected(entry.host) else {
        return
      }
      semantic_review_active_key.val = Some(key)
      reveal_semantic_review_item_start(entry.host)
      arm_semantic_review_navigation_reveal(entry)
      if reveal_last {
        entry.editor.reveal_last_diff()
      } else {
        entry.editor.reveal_first_diff()
      }
      entry.editor.focus()
    },
    kind=@cmd.after_render,
  )
}

///|
/// Reconcile section widgets after Rabbita has committed their keyed hosts.
/// Unchanged sections retain their editor models, selection, and scroll state.
fn sync_semantic_review_editors(state : State) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      guard state.semantic_review_input is Some(input) else {
        clear_semantic_review_editors()
        return
      }
      let desired = semantic_sections(state.semantic_review_plan)
      let desired_keys = desired.map(section => section.key)
      semantic_review_order.clear()
      semantic_review_order.append(desired_keys)
      if semantic_review_active_key.val is Some(key) &&
        !desired_keys.contains(key) {
        semantic_review_active_key.val = None
      }
      let is_stale = key => !desired_keys.contains(key)
      let stale = [
        for key, _ in semantic_review_editors if is_stale(key) => key
      ]
      for key in stale {
        remove_semantic_review_editor(key)
      }
      for section in desired {
        let key = section.key
        guard @dom.document()
          .get_element_by_id(semantic_editor_host_id(key))
          .to_option()
          is Some(host) else {
          remove_semantic_review_editor(key)
          continue
        }
        if semantic_review_editors.get(key) is Some(previous) &&
          previous.section == section &&
          previous.old_name == input.old_name &&
          previous.new_name == input.new_name &&
          previous.feedback_file == input.feedback_file &&
          previous.live_modified == input.live_modified &&
          previous.host.is_same_node(host.as_node()) {
          previous.editor.update_options(
            semantic_diff_options(state.review_diff_layout),
          )
          previous.editor.layout()
          continue
        }
        remove_semantic_review_editor(key)
        if create_semantic_review_editor(
            input,
            section,
            state.review_diff_layout,
            host,
          )
          is Some(entry) {
          semantic_review_editors[key] = entry
        }
      }
      update_semantic_review_scroll_width()
      schedule_semantic_review_scroll_width_update()
    },
    kind=@cmd.after_render,
  )
}

///|
pub extend SemanticReviewInput with Eq::{equal, not_equal}

///|
pub extend SemanticReviewInput with Debug::{to_repr}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend SemanticReviewLiveDocument with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` via the trait or `Repr(value)` instead", skip_current_package=true)
#doc(hidden)
pub extend SemanticReviewLiveDocument with Debug::{to_repr}
