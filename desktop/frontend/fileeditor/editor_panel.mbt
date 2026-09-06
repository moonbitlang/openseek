// The embedded read-only code viewer (moonbitlang/editor). Rabbita has
// no escape hatch for a foreign DOM widget, so the source viewer and Line
// full-file comparison each own a stable, never-diffed host element. The view
// renders those hosts empty, and after the first paint each widget attaches its
// imperative DOM. Token/Tree uses a fourth stable sibling containing keyed,
// empty per-section hosts; each receives a real DiffEditor. Every top-level
// stays independent, so no global monotonic line mapping is synthesized.

///|
/// The id of the stable element the viewer attaches into; the panel view must
/// render exactly one empty element with this id.
const ViewerHostId = "viewer-host"

///|
/// The stable sibling host for rich Markdown source presentation. Selection
/// is an explicit desktop policy; the code-only Viewer never changes its own
/// presentation from model metadata.
const MarkdownViewerHostId = "markdown-viewer-host"

///|
/// The stable sibling host for the UML rendering of an ordinary generated
/// MoonBit interface. The code Viewer keeps the same source model mounted
/// behind it so switching back to source is non-destructive.
const MbtiDiagramHostId = "mbti-diagram-host"

///|
/// The stable sibling host reserved for the switchable DiffEditor.
const DiffEditorHostId = "diff-editor-host"

///|
/// The stable sibling host for Token/Tree semantic review. Rabbita owns its
/// section chrome and the imperative section DiffEditors own their host DOM.
const SemanticReviewHostId = "semantic-review-host"

///|
/// A model in this URI scheme is a Git HEAD snapshot, not a document the
/// current host language tools can answer for. The live provider selector is
/// intentionally restricted to `@resource.Scheme` (see lsp.mbt).
const OriginalRevisionScheme = "openseek-review-original"

///|
/// Both sides of a historical comparison are immutable Git objects. Keeping a
/// separate inert scheme ensures current-checkout language providers never
/// answer hover/navigation requests for either revision.
const HistoryRevisionScheme = "openseek-git-history"

///|
/// The `MarkerService` owner for the language server's diagnostics — Monaco
/// keys markers by owner so one source's set replaces cleanly.
const DiagnosticsOwner = "moon-lsp"

///|
const DefaultEditorFontFamily = "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace"

///|
const DefaultEditorFontSize : Double = 13.0

///|
/// The viewer's imperative state — the attached widget, its services, and the
/// document it currently shows. None of this may live in the Rabbita model
/// (the virtual DOM must not own imperative DOM state), so it is collected
/// into this one module-level instance instead of loose globals.
priv struct ViewerHost {
  // The code-only source Viewer. `None` until the first
  // `request_viewer_mount` finds the host element in the DOM — the Viewer API constructs attached
  // (`Viewer::create`), so creation and mounting are one step. The host is
  // rendered on every screen from the first paint, and every file read is
  // batched behind a mount request whose after-render tick precedes the async
  // reply, so by the time a document arrives the viewer exists.
  mut viewer : @viewer.Viewer?
  // Kept separate from the source Viewer so a Diff/Source toggle preserves
  // the source model, selection, folding, and scroll state. DiffEditor owns
  // two code kernels directly rather than wrapping public Viewers.
  mut diff_editor : @viewer.DiffEditor?
  // Rich Markdown is a separate public surface, never a presentation branch
  // inside the code Viewer. It shares product services but owns its own model
  // and view-state lifetime.
  mut markdown_viewer : @viewer.MarkdownViewer?
  // The MBTI host is plain generated SVG rather than another editor widget.
  // Cache the rendered input so unrelated app updates do not repeat UML
  // layout while its stable host remains mounted.
  mut mbti_resource : String?
  mut mbti_source : String?
  // Desired full-comparison layout survives a pre-mount command in the same
  // way font settings do for the source Viewer.
  mut diff_options : @viewer.DiffEditorOptions
  // A positioned transcript link keeps its caret collapsed at the requested
  // column. This persistent whole-line decoration makes the destination visible
  // without turning the line into a selection and opening Comment UI. Symbol
  // navigation uses a fresh, short-lived collection instead (see below).
  mut point_range_highlight : @viewer.EditorDecorationsCollection?
  // Workspace Search owns one persistent collection over the displayed source
  // model. Every result range uses the same readable `findMatch` presentation.
  // The collection is replaced when Search state changes and cleared before a
  // model swap, matching VS Code's FileMatch lifetime.
  mut search_match_highlights : @viewer.EditorDecorationsCollection?
  // Desktop owns the concrete marker and feedback stores passed through the
  // Viewer's public handle API. They receive language-server diagnostics and
  // turn inline reviews into composer chips without requiring editor internals.
  mut services : DesktopViewerServices?
  // The absolute path of the file the viewer currently shows, so a
  // diagnostics push that arrives for a different file (or after the panel
  // cleared its document) is dropped rather than drawn over the wrong
  // document. `None` when the viewer shows a notice or nothing.
  mut absolute : @common.Uri?
  // The same file as the conversation names it — the workspace-relative path
  // the panel read it by. A comment filed on the shown document takes this
  // as its chip path, so the chip never has to reverse-engineer a relative
  // name from the absolute one. `None` when the viewer shows a notice or
  // nothing.
  mut relative : @pathx.Relative?
  // The active host/workspace route for Definition/References targets and
  // cross-file Peek previews. Cleared together with the document so a late
  // navigation request can never reopen a previous conversation's file.
  mut navigation : NavigationContext?
  // Monotonic model version; the viewer treats a new version as a new
  // document.
  mut version : Int
  // Imperative canvas/Markdown renderers must receive theme changes through
  // their options API; CSS data attributes alone cannot repaint their pixels.
  mut theme : String
  // Desired family survives before the Viewer mounts, so startup settings and
  // a later first file open cannot race back to the editor package default.
  mut font_family : String
  // Desired size has the same pre-mount lifetime as the family. The Viewer
  // consumes pixels as a Double and re-measures whenever this value changes.
  mut font_size : Double
  // Each open tab's last scroll position, keyed by workspace-relative path,
  // saved as the viewer switches away and restored when the tab returns.
  // Scroll is DOM state, so it lives here beside the viewer rather than in
  // the Rabbita model.
  view_states : Map[String, @viewer.ViewerViewState]
  markdown_view_states : Map[String, @viewer.MarkdownViewerViewState]
}

///|
let viewer_state : ViewerHost = {
  viewer: None,
  diff_editor: None,
  markdown_viewer: None,
  mbti_resource: None,
  mbti_source: None,
  diff_options: @viewer.DiffEditorOptions(
    editor_options=@viewer.ViewerOptions(
      theme="light",
      soft_wrap=true,
      font_family=DefaultEditorFontFamily,
      font_size=DefaultEditorFontSize,
    ),
    layout=@viewer.SideBySide,
    automatic_inline=false,
    diff_word_wrap=@viewer.Off,
  ),
  point_range_highlight: None,
  search_match_highlights: None,
  services: None,
  absolute: None,
  relative: None,
  navigation: None,
  version: 0,
  theme: "light",
  font_family: DefaultEditorFontFamily,
  font_size: DefaultEditorFontSize,
  view_states: Map([]),
  markdown_view_states: Map([]),
}

///|
/// The mounted viewer, or `None` before the first mount.
fn mounted_viewer() -> @viewer.Viewer? {
  viewer_state.viewer
}

///|
fn mounted_markdown_viewer() -> @viewer.MarkdownViewer? {
  viewer_state.markdown_viewer
}

///|
fn mounted_diff_editor() -> @viewer.DiffEditor? {
  viewer_state.diff_editor
}

///|
priv enum ActiveEditorSurface {
  CodeEditorSurface
  MarkdownEditorSurface
  DiffEditorSurface
  SemanticEditorSurface
}

///|
fn active_editor_surface_from_visibility(
  code_visible : Bool,
  markdown_visible : Bool,
  diff_visible : Bool,
  semantic_visible : Bool,
) -> ActiveEditorSurface? {
  if semantic_visible {
    Some(SemanticEditorSurface)
  } else if diff_visible {
    Some(DiffEditorSurface)
  } else if markdown_visible {
    Some(MarkdownEditorSurface)
  } else if code_visible {
    Some(CodeEditorSurface)
  } else {
    None
  }
}

///|
fn editor_surface_host_visible(host_id : String) -> Bool {
  guard @dom.document().get_element_by_id(host_id).to_option() is Some(host) else {
    return false
  }
  let rect = host.get_bounding_client_rect()
  rect.get_width() > 0.0 && rect.get_height() > 0.0
}

///|
fn active_editor_surface() -> ActiveEditorSurface? {
  active_editor_surface_from_visibility(
    editor_surface_host_visible(ViewerHostId),
    editor_surface_host_visible(MarkdownViewerHostId),
    editor_surface_host_visible(DiffEditorHostId),
    editor_surface_host_visible(SemanticReviewHostId),
  )
}

///|
fn layout_active_editor_surface() -> Unit {
  match active_editor_surface() {
    Some(CodeEditorSurface) =>
      match mounted_viewer() {
        Some(viewer) => viewer.layout()
        None => ()
      }
    Some(MarkdownEditorSurface) =>
      match mounted_markdown_viewer() {
        Some(viewer) => viewer.layout()
        None => ()
      }
    Some(DiffEditorSurface) =>
      match mounted_diff_editor() {
        Some(viewer) => viewer.layout()
        None => ()
      }
    Some(SemanticEditorSurface) => layout_semantic_review_editors()
    None => ()
  }
}

///|
/// Resolves feedback for the live working document. The code source Viewer is
/// normally authoritative; when rich Markdown is selected it is detached, so
/// the modified DiffEditor kernel becomes the working-document surface.
fn working_feedback_model(
  source_model : @model.TextModel?,
  diff_model : @viewer.DiffEditorModel?,
  resource : @common.Uri,
) -> @model.TextModel? {
  match source_model {
    Some(model) if model.uri.to_string() == resource.to_string() => Some(model)
    _ =>
      match diff_model {
        Some(model) if model.modified.uri.to_string() == resource.to_string() =>
          Some(model.modified)
        _ => None
      }
  }
}

///|
/// Register syntax highlighting for the languages the panel can recognize.
/// `.mbtx` scripts register under their own id but use the MoonBit tokenizer,
/// so they color exactly like `.mbt` source. Files of any other type render
/// as plain text.
fn register_tokenizers() -> Unit {
  @languages.languages.set_tokens_provider(
    "moonbit",
    @lang_moonbit.MoonBitTokenizer(),
  )
  |> ignore
  @languages.languages.set_tokens_provider(
    "mbtx",
    @lang_moonbit.MoonBitTokenizer(),
  )
  |> ignore
  @languages.languages.set_tokens_provider(
    "javascript",
    @lang_javascript.JavascriptTokenizer(),
  )
  |> ignore
  @languages.languages.set_tokens_provider("json", @lang_json.JsonTokenizer())
  |> ignore
  @languages.languages.set_tokens_provider(
    "moonbit-config",
    @lang_moon_config.MoonConfigTokenizer(),
  )
  |> ignore
  install_moonbit_markdown_comment_provider()
}

///|
fn supports_moon_diff(path : String) -> Bool {
  path.to_lower().has_suffix(".mbt")
}

///|
fn uses_markdown_presentation(name : String) -> Bool {
  name.to_lower().has_suffix(".md") || language_id(name) == "markdown"
}

///|
fn uses_mbti_presentation(name : String) -> Bool {
  name.to_lower().has_suffix(".mbti")
}

///|
fn markdown_resource_kind(name : String) -> @viewer.MarkdownResourceKind {
  if name.to_lower().has_suffix(".mbt.md") {
    @viewer.MoonBitMarkdown
  } else {
    @viewer.OrdinaryMarkdown
  }
}

///|
/// Create the viewer in its host element after the next paint, once (the
/// tokenizers and hover provider register with it). A no-op if already
/// mounted or the host element is not in the DOM yet.
///
/// Mounting also wires both code-pane comment flows into the update
/// loop. Working-side feedback becomes `EditorCommentAdded`; feedback filed on
/// the original pane becomes `DiffCommentAdded` with original-revision
/// identity. The main package turns either event into a composer chip.
fn request_viewer_mount(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      if viewer_state.viewer is None &&
        @dom.document().get_element_by_id(ViewerHostId).to_option()
        is Some(host) {
        register_tokenizers()
        register_hover_provider()
        let services = DesktopViewerServices(
          navigation_location_opener((owner, path, range) => {
            scheduler.add(
              dispatch(OpenNavigationLocation(owner~, path~, range~)),
            )
          }),
          navigation_text_model_resolver(),
          (owner, message) => {
            scheduler.add(dispatch(LanguageRequestFailed(owner~, message~)))
          },
        )
        viewer_state.services = Some(services)
        let viewer = @viewer.Viewer::create(
          host,
          services=services.viewer_services,
          options=@viewer.ViewerOptions(
            theme=viewer_state.theme,
            placeholder="Select a file to view",
            font_family=viewer_state.font_family,
            font_size=viewer_state.font_size,
          ),
        )
        viewer_state.viewer = Some(viewer)
        viewer_state.point_range_highlight = Some(
          viewer.create_decorations_collection(),
        )
        viewer_state.search_match_highlights = Some(
          viewer.create_decorations_collection(),
        )
        services.feedback.on_did_add_feedback(event => {
          guard event.feedback.kind is @agent_feedback_api.UserReview else {
            return
          }
          if semantic_feedback_model_projection(event.feedback.resource)
            is Some(projection) {
            let range = project_semantic_feedback_range(
              event.feedback.range,
              projection.line_offset,
            )
            scheduler.add(
              dispatch(
                semantic_feedback_message(
                  projection.file,
                  projection.side,
                  range,
                  projection.model.get_value_in_range(event.feedback.range),
                  event.feedback.text,
                  ModelUri(event.feedback.resource.to_string()),
                  event.feedback.id,
                ),
              ),
            )
            return
          }
          guard viewer_state.relative is Some(file) else { return }
          // The modified pane and code source use the same live URI. Rich
          // Markdown detaches that source Viewer, so resolve the modified diff
          // model as the fallback working-document owner.
          let diff_model = viewer_state.diff_editor.bind(editor => {
            editor.get_model()
          })
          if working_feedback_model(
              viewer.get_model(),
              diff_model,
              event.feedback.resource,
            )
            is Some(model) {
            scheduler.add(
              dispatch(
                EditorCommentAdded(
                  resource=ModelUri(event.feedback.resource.to_string()),
                  file~,
                  range=event.feedback.range,
                  quote=model.get_value_in_range(event.feedback.range),
                  comment=event.feedback.text,
                  feedback_id=event.feedback.id,
                ),
              ),
            )
            return
          }
          // Original models use an inert revision URI, so they never enter
          // host language providers. Their feedback still uses the ordinary
          // Viewer UI and is projected onto the existing original-side chip
          // contract, including a key for clearing that Viewer's bubble.
          guard diff_model is Some(diff_model) &&
            diff_model.original.uri.to_string() ==
            event.feedback.resource.to_string() else {
            return
          }
          let quote = diff_model.original.get_value_in_range(
            event.feedback.range,
          )
          scheduler.add(
            dispatch(
              diff_comment_message(
                file,
                original_line_number=Some(
                  event.feedback.range.start_line_number,
                ),
                modified_line_number=None,
                quote~,
                comment=event.feedback.text,
                resource=ModelUri(event.feedback.resource.to_string()),
                feedback_id=event.feedback.id,
              ),
            ),
          )
        })
        |> ignore
        services.feedback.on_did_submit_feedback(event => {
          // `add_feedback` fires first, so the scheduler receives the comment
          // chip before this apply action. Ignore batches without user review
          // items; only the inline user's explicit action should send a prompt.
          if event.user_count > 0 {
            scheduler.add(dispatch(ApplyAllFeedback))
          }
        })
        |> ignore
      }
      if viewer_state.markdown_viewer is None &&
        viewer_state.services is Some(services) &&
        @dom.document().get_element_by_id(MarkdownViewerHostId).to_option()
        is Some(markdown_host) {
        viewer_state.markdown_viewer = Some(
          @viewer.MarkdownViewer::create(
            markdown_host,
            services=services.viewer_services,
            options=@viewer.MarkdownViewerOptions(
              theme=viewer_state.theme,
              placeholder="Select a Markdown file to view",
            ),
          ),
        )
      }
      if viewer_state.diff_editor is None &&
        viewer_state.services is Some(services) &&
        @dom.document().get_element_by_id(DiffEditorHostId).to_option()
        is Some(diff_host) {
        let diff_editor = @viewer.DiffEditor::create(
          diff_host,
          services=services.viewer_services,
          options=viewer_state.diff_options,
        )
        diff_editor.on_did_update_diff(() => {
          let navigation_available = if diff_editor.is_diff_up_to_date() {
            match diff_editor.get_diff() {
              Some(diff) => !diff.changes.is_empty()
              None => false
            }
          } else {
            false
          }
          scheduler.add(
            dispatch(
              ReviewDiffNavigationAvailabilityChanged(navigation_available),
            ),
          )
        })
        |> ignore
        viewer_state.diff_editor = Some(diff_editor)
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Reveal the previous change through DiffEditor's existing cyclic navigation.
/// This deliberately leaves focus where it is so toolbar clicks do not change
/// keyboard ownership beyond the editor's own cursor update.
fn reveal_previous_review_diff_change() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if viewer_state.diff_editor is Some(diff_editor) {
      diff_editor.reveal_previous_change() |> ignore
    }
  })
}

///|
/// Reveal the next change through DiffEditor's existing cyclic navigation.
fn reveal_next_review_diff_change() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if viewer_state.diff_editor is Some(diff_editor) {
      diff_editor.reveal_next_change() |> ignore
    }
  })
}

///|
/// Retain and apply the panel's side-by-side/inline preference without
/// replacing the comparison models or either code kernel.
fn apply_review_diff_layout(layout : ReviewDiffLayout) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    let editor_layout = match layout {
      ReviewSideBySide => @viewer.SideBySide
      ReviewInline => @viewer.Inline
    }
    let options = viewer_state.diff_options.with_layout(editor_layout)
    viewer_state.diff_options = options
    if viewer_state.diff_editor is Some(diff_editor) {
      diff_editor.update_options(options)
    }
    update_semantic_review_editor_layout(layout)
  })
}

///|
fn current_diff_pane_options() -> @viewer.ViewerOptions {
  @viewer.ViewerOptions(
    theme=viewer_state.theme,
    soft_wrap=true,
    font_family=viewer_state.font_family,
    font_size=viewer_state.font_size,
  )
}

///|
fn refresh_diff_pane_options() -> Unit {
  let options = viewer_state.diff_options.with_editor_options(
    current_diff_pane_options(),
  )
  viewer_state.diff_options = options
  if viewer_state.diff_editor is Some(diff_editor) {
    diff_editor.update_options(options)
  }
  refresh_semantic_review_editor_options()
}

///|
/// Update every imperative presentation, including canvas overview markers
/// and Markdown diagrams that cannot repaint from inherited CSS alone.
pub fn apply_theme(theme : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    viewer_state.theme = theme
    if viewer_state.viewer is Some(viewer) {
      viewer.update_options(viewer.get_options().with_theme(theme))
    }
    if viewer_state.markdown_viewer is Some(markdown_viewer) {
      markdown_viewer.update_options(
        markdown_viewer.get_options().with_theme(theme),
      )
    }
    refresh_diff_pane_options()
  })
}

///|
/// Retain the selected family for future mounts and update an attached Viewer
/// through its public options API. Updating options re-measures glyph widths
/// and recomputes wrapping before the next render.
pub fn apply_font_family(font_family : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    viewer_state.font_family = font_family
    if viewer_state.viewer is Some(viewer) {
      viewer.update_options(viewer.get_options().with_font_family(font_family))
    }
    refresh_diff_pane_options()
  })
}

///|
/// Retain the selected size for future mounts and update an attached Viewer.
/// ViewerOptions owns the rebuild decision, including glyph measurement and
/// wrapping changes caused by the new pixel size.
pub fn apply_font_size(font_size : Double) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    viewer_state.font_size = font_size
    if viewer_state.viewer is Some(viewer) {
      viewer.update_options(viewer.get_options().with_font_size(font_size))
    }
    refresh_diff_pane_options()
  })
}

///|
/// Keep the renderer-to-application mapping explicit and independently
/// testable. No DOM details cross this boundary; both line-number domains are
/// retained for the main update loop to interpret.
fn diff_comment_message(
  file : @pathx.Relative,
  original_line_number~ : Int?,
  modified_line_number~ : Int?,
  quote~ : String,
  comment~ : String,
  resource? : ModelUri,
  feedback_id? : String,
) -> Msg {
  DiffCommentAdded(
    file~,
    original_line_number~,
    modified_line_number~,
    quote~,
    comment~,
    resource~,
    feedback_id~,
  )
}

///|
/// Clear one comment bubble from the editor once its text has become a
/// composer chip — the chip is the comment's carrier from then on. Routed by
/// the same model URI the feedback was filed under. Public for the main
/// package's `EditorCommentAdded` handler, which owns the chip flow. Removal
/// waits until after render so Add-and-Apply can synchronously mark the still
/// accepted item submitted and publish its host event first.
pub fn remove_editor_feedback(
  resource : ModelUri,
  feedback_id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      guard viewer_state.services is Some(services) else { return }
      // The string is the `to_string()` of a URI this package minted, so the
      // re-parse cannot fail; a stray unparsable string has no bubble anyway.
      let uri = @common.Uri::parse(resource.0) catch { _ => return }
      services.feedback.remove_feedback(uri, feedback_id)
    },
    kind=@cmd.after_render,
  )
}

///|
/// Re-measure the viewport after the panel's width changes (it is laid out by
/// CSS, so the viewer cannot see the change on its own). Public for the main
/// package's viewport-resize handler — a window resize or phone rotation
/// changes the panel's host size without any panel message.
pub fn request_viewer_remeasure() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _after => layout_active_editor_surface(),
    kind=@cmd.after_render,
  )
}

///|
/// Build an inert model identity for the Git HEAD side of a comparison. The
/// path remains useful for feedback identity and display, but the distinct
/// scheme prevents every live-checkout language selector from matching it.
fn original_revision_model_uri(
  owner : @interop.ConversationKey,
  absolute : @common.Uri?,
  relative : @pathx.Relative?,
  fallback_name : String,
) -> @common.Uri? {
  let path = match (absolute, relative) {
    (Some(absolute), _) => absolute.path
    (None, Some(relative)) => "/" + relative.0
    (None, None) => "/" + fallback_name
  }
  let uri = @common.Uri::from(
    scheme=OriginalRevisionScheme,
    authority=owner.channel.uri_authority(),
    path~,
  ) catch {
    _ => return None
  }
  Some(uri)
}

///|
/// Dispose a pair returned by `DiffEditor::set_model`. The return contract
/// guarantees both kernels and the shared view model have already detached
/// it, so no frame-delayed retirement or compatibility grace period exists.
fn dispose_diff_comparison_models(previous : @viewer.DiffEditorModel) -> Unit {
  previous.original.dispose()
  if !previous.modified.same(previous.original) {
    previous.modified.dispose()
  }
}

///|
/// Detach the caller-owned models currently installed in the comparison.
/// Ordinary source/diff toggles and file navigation deliberately do not call
/// this: the last complete pair stays parked behind the inactive surface until
/// its successor is ready. Hard owner/workspace boundaries clear it here.
fn clear_diff_comparison() -> Unit {
  guard viewer_state.diff_editor is Some(diff_editor) else { return }
  let previous = diff_editor.set_model(None)
  if previous is Some(previous) {
    if viewer_state.services is Some(services) {
      services.feedback.set_feedback_enabled(previous.original.uri, false)
      services.feedback.clear_feedback(previous.original.uri)
    }
    dispose_diff_comparison_models(previous)
  }
}

///|
/// Install one full comparison without disturbing the separately mounted
/// source Viewer. Equal inputs retain the current pair so selection, scroll,
/// and feedback UI survive an unchanged review refresh.
fn show_diff_comparison(
  owner : @interop.ConversationKey,
  name : String,
  modified_uri : @common.Uri,
  absolute : @common.Uri?,
  relative : @pathx.Relative?,
  original_content : String,
  modified_content : String,
) -> Unit {
  guard viewer_state.diff_editor is Some(diff_editor) &&
    viewer_state.services is Some(services) &&
    original_revision_model_uri(owner, absolute, relative, name)
    is Some(original_uri) else {
    return
  }
  if diff_editor.get_model() is Some(current) &&
    current.original.uri.to_string() == original_uri.to_string() &&
    current.modified.uri.to_string() == modified_uri.to_string() &&
    current.original.get_value() == original_content &&
    current.modified.get_value() == modified_content {
    services.feedback.set_feedback_enabled(original_uri, relative is Some(_))
    return
  }
  let current = diff_editor.get_model()
  if current is Some(previous) {
    services.feedback.set_feedback_enabled(previous.original.uri, false)
    services.feedback.clear_feedback(previous.original.uri)
  }
  let model_version = viewer_state.version
  let language = language_id(name)
  let original_model = @model.TextModel(
    original_uri,
    name,
    language,
    model_version,
    "head-v" + model_version.to_string(),
    original_content,
  )
  let modified_model = @model.TextModel(
    modified_uri,
    name,
    language,
    model_version,
    "diff-v" + model_version.to_string(),
    modified_content,
  )
  let previous = diff_editor.set_model(
    Some(@viewer.DiffEditorModel(original_model, modified_model)),
  )
  // Match VS Code's TextDiffEditor host policy: a genuinely new comparison
  // with no restored view state starts at its first raw diff mapping. The
  // equality guard above deliberately keeps Source/Diff toggles and unchanged
  // review refreshes at the reviewer's existing position.
  diff_editor.reveal_first_diff()
  services.feedback.set_feedback_enabled(original_uri, relative is Some(_))
  if previous is Some(previous) {
    dispose_diff_comparison_models(previous)
  }
}

///|
fn history_revision_model_uri(
  owner : @interop.ConversationKey,
  revision : String,
  side : String,
  path : @pathx.Relative,
) -> @common.Uri? {
  let uri = @common.Uri::from(
    scheme=HistoryRevisionScheme,
    authority=owner.channel.uri_authority(),
    path="/\{revision}/\{side}/\{path.0}",
  ) catch {
    _ => return None
  }
  Some(uri)
}

///|
/// Install a historical pair directly into the permanent DiffEditor. Neither
/// model represents the working tree, so feedback, quick diff, diagnostics,
/// and language navigation stay disabled on both sides.
fn show_history_diff_in_viewer(
  owner : @interop.ConversationKey,
  diff : @dock.GitHistoryDiff,
  original_content : String,
  modified_content : String,
) -> @cmd.Cmd {
  let show = @cmd.custom_cmd(_scheduler => {
    guard viewer_state.diff_editor is Some(diff_editor) &&
      viewer_state.services is Some(services) else {
      return
    }
    let original_revision = diff.parent.unwrap_or("empty-tree")
    let original_path = diff.original_path.unwrap_or(diff.path)
    guard history_revision_model_uri(
        owner, original_revision, "original", original_path,
      )
      is Some(original_uri) &&
      history_revision_model_uri(owner, diff.commit, "modified", diff.path)
      is Some(modified_uri) else {
      return
    }
    if diff_editor.get_model() is Some(current) &&
      current.original.uri.to_string() == original_uri.to_string() &&
      current.modified.uri.to_string() == modified_uri.to_string() &&
      current.original.get_value() == original_content &&
      current.modified.get_value() == modified_content {
      services.feedback.set_feedback_enabled(original_uri, false)
      services.feedback.set_feedback_enabled(modified_uri, false)
      return
    }
    let current = diff_editor.get_model()
    if current is Some(previous) {
      services.feedback.set_feedback_enabled(previous.original.uri, false)
      services.feedback.set_feedback_enabled(previous.modified.uri, false)
      services.feedback.clear_feedback(previous.original.uri)
      services.feedback.clear_feedback(previous.modified.uri)
    }
    viewer_state.version += 1
    let version = viewer_state.version
    let name = basename(diff.path)
    let language = language_id(name)
    let original_model = @model.TextModel(
      original_uri,
      name,
      language,
      version,
      "history-original-v" + version.to_string(),
      original_content,
    )
    let modified_model = @model.TextModel(
      modified_uri,
      name,
      language,
      version,
      "history-modified-v" + version.to_string(),
      modified_content,
    )
    let previous = diff_editor.set_model(
      Some(@viewer.DiffEditorModel(original_model, modified_model)),
    )
    // Historical comparisons are fresh DiffEditor inputs too. Equal pairs
    // return above, preserving the reader's position just like a restored VS
    // Code diff view state.
    diff_editor.reveal_first_diff()
    services.feedback.set_feedback_enabled(original_uri, false)
    services.feedback.set_feedback_enabled(modified_uri, false)
    viewer_state.absolute = None
    viewer_state.relative = None
    viewer_state.navigation = None
    if previous is Some(previous) {
      dispose_diff_comparison_models(previous)
    }
  })
  @cmd.batch([show, request_viewer_remeasure()])
}

///|
/// The collapsed caret and decoration used for one programmatic navigation.
/// Point locations highlight their whole line; non-empty symbol locations use
/// the same exact-range feedback as the Viewer's same-resource Definition
/// path. Neither presentation creates a selection, so navigation cannot open
/// the selection-driven Comment UI.
priv struct NavigationTargetPresentation {
  position : @common.Position
  decoration : @model.ModelDeltaDecoration
  is_transient : Bool
}

///|
fn navigation_target_presentation(
  range : @common.Range,
) -> NavigationTargetPresentation {
  let position = range.get_start_position()
  let point = range.is_empty()
  let decoration : @model.ModelDeltaDecoration = if point {
    {
      range: @common.Range(
        range.start_line_number,
        1,
        range.start_line_number,
        1,
      ),
      options: @model.ModelDecorationOptions(
        "rangeHighlight",
        is_whole_line=true,
        description="point-range-line-highlight",
      ),
    }
  } else {
    {
      range,
      options: @model.ModelDecorationOptions(
        "symbolHighlight",
        description="symbol-navigate-action-highlight",
      ),
    }
  }
  { position, decoration, is_transient: !point, }
}

///|
/// VS Code `FileMatchImpl.updateHighlights` projects every match into one model
/// decoration collection. OpenSeek receives the same one-based UTF-16 ranges
/// from its Host search, but deliberately uses one readable presentation for
/// every result instead of a stronger current-match color.
fn search_match_decorations(
  ranges : Array[@common.Range],
) -> Array[@model.ModelDeltaDecoration] {
  ranges.map(range => {
    range,
    options: @model.ModelDecorationOptions(
      "findMatch",
      inline_class_name="findMatchInline",
      z_index=10,
      show_if_collapsed=true,
      stickiness=@model.NeverGrowsWhenTypingAtEdges,
      description="search-find-match",
    ),
  })
}

///|
fn set_search_match_highlights(
  highlights : @grep_search.EditorHighlights?,
) -> Unit {
  if viewer_state.search_match_highlights is Some(collection) {
    let decorations = match highlights {
      Some(highlights) => search_match_decorations(highlights.ranges())
      None => []
    }
    collection.set(decorations) |> ignore
  }
}

///|
/// Refresh Search decorations without replacing the current Viewer model.
/// Query/options changes clear them immediately; the accepted Host reply then
/// installs the new complete file projection.
fn update_search_match_highlights(
  highlights : @grep_search.EditorHighlights?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => set_search_match_highlights(highlights))
}

///|
/// Match the reusable Viewer's Definition/References target feedback: keep an
/// exact symbol highlight for 350ms, then clear it only while the Viewer still
/// owns the model that received it. A fresh collection prevents an older timer
/// from clearing a newer navigation target.
fn show_transient_navigation_target_highlight(
  viewer : @viewer.Viewer,
  target_model : @model.TextModel,
  decoration : @model.ModelDeltaDecoration,
) -> Unit {
  let decorations = viewer.create_decorations_collection(decorations=[
    decoration,
  ])
  @base_browser.schedule_timeout(
    () => {
      match viewer.get_model() {
        Some(current) if current.same(target_model) => decorations.clear()
        _ => ()
      }
    },
    350,
  )
  |> ignore
}

///|
fn dispose_markdown_model(model : @viewer.MarkdownViewerModel?) -> Unit {
  match model {
    Some(model) => model.model.dispose()
    None => ()
  }
}

///|
fn dispose_source_model(model : @model.TextModel?) -> Unit {
  match model {
    Some(model) => model.dispose()
    None => ()
  }
}

///|
/// Render a generated interface into the stable MBTI host at most once per
/// resource/content pair. The UML module returns generated SVG at this trusted
/// insertion boundary; a malformed interface gets an explicit error surface
/// with the source toggle still available in the breadcrumb.
fn show_mbti_diagram(resource : @common.Uri, source : String) -> Unit {
  let resource_key = resource.to_string()
  if viewer_state.mbti_resource == Some(resource_key) &&
    viewer_state.mbti_source == Some(source) {
    return
  }
  guard @dom.document().get_element_by_id(MbtiDiagramHostId).to_option()
    is Some(host) else {
    return
  }
  viewer_state.mbti_resource = Some(resource_key)
  viewer_state.mbti_source = Some(source)
  match @viewer.render_mbti_diagram_svg(source) {
    Some(svg) => host.set_inner_html(svg)
    None => {
      let message =
        #|<div class="mbti-diagram-error" role="status">This interface could not be rendered as a UML diagram. View the source for details.</div>
      host.set_inner_html(message)
    }
  }
}

///|
fn clear_mbti_diagram() -> Unit {
  viewer_state.mbti_resource = None
  viewer_state.mbti_source = None
  if @dom.document().get_element_by_id(MbtiDiagramHostId).to_option()
    is Some(host) {
    host.set_inner_html("")
  }
}

///|
/// Schedule an imperative editor effect for the render that exposes its stable
/// host. Keeping the scheduler plumbing here also leaves large effect bodies in
/// the formatter's compact single-closure form.
fn after_render_effect(action : () -> Unit) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => action(), kind=@cmd.after_render)
}

///|
/// Show a file's contents in the viewer as a fresh read-only document. A
/// symbol jump's `range`, when present, is revealed centered once the
/// document is set. The caret stays collapsed at the range start while an
/// independent decoration highlights either the exact symbol for 350ms or a
/// point's whole line until the next document show. `annotation`, when
/// present (an annotation chip's jump), is re-shown as a comment bubble over
/// `range` — the bubble the chip replaced when the comment was filed.
///
/// The outgoing document's scroll position is always saved under its
/// relative path; `restore_scroll` (a tab switch or an in-place reload)
/// brings the incoming document back to its saved position instead of the
/// top — the Monaco save/restore-view-state contract around `set_model`.
/// `review_original`, when present, is the Git HEAD baseline used by the
/// code Viewer's quick-diff contribution. An empty string is meaningful for a
/// new file; omission clears any earlier baseline for this resource. A
/// comparison pair, when present, is rendered by the sibling DiffEditor while
/// both source widgets remain mounted. Every show is followed by an
/// after-render layout pass: a sibling host may have just left `display: none`,
/// where its child widget could only measure Monaco's 5px minimum.
fn show_file_in_viewer(
  owner : @interop.ConversationKey,
  root~ : @common.Uri?,
  name : String,
  content : String,
  absolute? : @common.Uri,
  relative? : @pathx.Relative,
  range? : @common.Range? = None,
  annotation? : String,
  restore_scroll? : Bool = false,
  review_original? : String,
  diff? : (String, String),
  search_highlights? : @grep_search.EditorHighlights,
) -> @cmd.Cmd {
  let show = after_render_effect(() => {
    // A fast host (including the browser fixture) may settle `read_file`
    // before the mount command from the open action reaches its after-render
    // phase. Commit the document in that same phase so the stable hosts and
    // their widgets exist before either the source model or MBTI SVG is set.
    guard viewer_state.viewer is Some(viewer) &&
      viewer_state.markdown_viewer is Some(markdown_viewer) else {
      return
    }
    let show_markdown = uses_markdown_presentation(name)
    // The URI is the file's absolute path and host identity. The hover
    // provider pairs it with the active navigation root. A notice document
    // (withheld binary/oversized file) has no file behind it, so its inert
    // scheme never parses as a model path and hover stays off.
    let uri = match absolute {
      Some(absolute) => model_uri_of(absolute)
      None =>
        // Deleted previews have no absolute file URI. Use the full relative
        // path when one exists so equal basenames in different directories do
        // not alias one Viewer model and leak its view state across tabs.
        @common.Uri::from(
          scheme="openseek-notice",
          path="/" + relative.map(path => path.0).unwrap_or(name),
        ) catch {
          _ => return
        }
    }
    if uses_mbti_presentation(name) {
      show_mbti_diagram(uri, content)
    }
    // Whether anything needs redrawing is decided here, against the document
    // the viewer really shows — the update loop only says "show this", it
    // does not guess at the screen from its tab cache. When the viewer
    // already displays this exact text (a reload that found the disk
    // unchanged, or a jump into the file on screen), the model is left
    // untouched so the selection, scroll, and feedback bubbles survive; a
    // jump's reveal and annotation still apply below, over the kept document.
    let code_model = viewer.get_model()
    let markdown_model = markdown_viewer.get_model()
    let same_code_resource = !show_markdown &&
      code_model is Some(current) &&
      current.uri.to_string() == uri.to_string()
    let same_document = if show_markdown {
      markdown_model is Some(current) &&
      current.model.uri.to_string() == uri.to_string() &&
      current.model.get_value() == content &&
      current.resource_kind == markdown_resource_kind(name)
    } else {
      code_model is Some(current) &&
      current.uri.to_string() == uri.to_string() &&
      current.get_value() == content
    }
    let previous_uri = match code_model {
      Some(model) => Some(model.uri)
      None => markdown_model.map(model => model.model.uri)
    }
    let restore_view_state = should_restore_view_state(
      restore_scroll, previous_uri, uri,
    )
    // Decorations live on the current text model. Remove the previous
    // persistent point highlight before a possible model swap. Symbol jumps
    // use fresh transient collections that retire themselves after 350ms.
    if viewer_state.point_range_highlight is Some(highlight) {
      highlight.clear()
    }
    if viewer_state.search_match_highlights is Some(highlights) {
      highlights.clear()
    }
    if same_code_resource && !same_document {
      // VS Code reloads an existing text-file model in place. The readonly
      // Viewer uses its whole-value flush lane, bracketed by view-state
      // persistence so folding contribution state survives the decorations
      // that `set_value` deliberately destroys.
      let current_view_state = viewer.save_view_state()
      viewer.set_value(content)
      viewer.restore_view_state(current_view_state)
    } else if !same_document {
      // Park the outgoing document's view state for its tab's return.
      if viewer_state.relative is Some(prev) {
        if code_model is Some(_) && viewer.save_view_state() is Some(view_state) {
          viewer_state.view_states[prev.0] = view_state
        }
        if markdown_model is Some(_) &&
          markdown_viewer.save_view_state() is Some(view_state) {
          viewer_state.markdown_view_states[prev.0] = view_state
        }
      }
      viewer_state.version += 1
      let version = viewer_state.version
      let text_model = @model.TextModel(
        uri,
        name,
        language_id(name),
        version,
        "v" + version.to_string(),
        content,
      )
      if show_markdown {
        // The public surfaces are mutually exclusive model owners. Detach and
        // retire Code before installing the rich Markdown model.
        viewer.set_model(None)
        dispose_source_model(code_model)
        let previous = markdown_viewer.set_model(
          Some(
            @viewer.MarkdownViewerModel(
              text_model,
              markdown_resource_kind(name),
            ),
          ),
        )
        dispose_markdown_model(previous)
        if restore_view_state &&
          relative is Some(rel) &&
          viewer_state.markdown_view_states.get(rel.0) is Some(saved) {
          markdown_viewer.restore_view_state(Some(saved))
        }
      } else {
        // `MarkdownViewer::set_model` returns only after its attachment and
        // bridges are detached, so the caller-owned TextModel can be retired
        // immediately before Code takes over.
        dispose_markdown_model(markdown_viewer.set_model(None))
        viewer.set_model(Some(text_model))
        dispose_source_model(code_model)
        let restored_code_view_state = if restore_view_state &&
          relative is Some(rel) &&
          viewer_state.view_states.get(rel.0) is Some(saved) {
          viewer.restore_view_state(Some(saved))
          true
        } else {
          false
        }
        // Match the reference workbench's host policy: ordinary `.mbt` files
        // open as a top-level outline. `set_model` computes folding ranges
        // synchronously, so this is stable initialization state rather than a
        // delayed render effect. A restored state already carries the user's
        // fold choices, so the initial policy must not run over it.
        if !restored_code_view_state && should_auto_fold_top_level(text_model) {
          viewer.fold_top_level()
        }
      }
    } else if show_markdown {
      viewer.set_model(None)
      dispose_source_model(code_model)
    } else {
      dispose_markdown_model(markdown_viewer.set_model(None))
    }
    // Gate incoming diagnostics to the file now on screen (a notice document,
    // with no absolute path, takes no diagnostics). The relative name rides
    // along for comments filed on this document (see `ViewerHost::relative`).
    viewer_state.absolute = absolute
    viewer_state.relative = relative
    viewer_state.navigation = match (absolute, relative) {
      (Some(absolute), Some(relative)) =>
        navigation_context_for_file(owner, root, absolute, relative)
      _ => None
    }
    // Commenting (select → inline input → composer chip) is for real files;
    // a notice document has nothing behind it to comment on.
    if viewer_state.services is Some(services) {
      // Only the displayed resource needs a stored baseline. Retire the
      // outgoing URI before publishing the incoming one so tab switches and
      // conversation changes cannot accumulate up-to-1-MiB HEAD blobs.
      if previous_uri is Some(previous) &&
        previous.to_string() != uri.to_string() {
        services.quick_diff.set_original_content(previous, None)
      }
      // The service is resource-keyed, so setting this after `set_model` also
      // handles a late HEAD reply for the document already on screen. The
      // service event makes the gutter recompute without replacing the model.
      services.quick_diff.set_original_content(
        uri,
        if show_markdown {
          None
        } else {
          review_original
        },
      )
      // MarkdownViewer has no code-feedback contribution, but the same live
      // resource may be mounted in DiffEditor's modified code kernel. Keep the
      // resource enabled so review comments remain available there.
      services.feedback.set_feedback_enabled(uri, absolute is Some(_))
      if absolute is Some(_) && !show_markdown {
        // A fresh document view starts with no bubbles (comments become
        // chips the moment they are filed, so anything lingering here is a
        // previous jump's re-display); an annotation chip's jump then
        // re-shows its comment over the commented range. `Submitted` keeps
        // the display copy quiet: it fires no `did_add_feedback` (so the
        // chip callback cannot mint a duplicate) and draws no Created-state
        // button bar. A same-document show only re-stages bubbles for a
        // jump that carries an annotation — a plain unchanged reload must
        // not clear what the user is looking at (or typing into).
        if !same_document || annotation is Some(_) {
          services.feedback.clear_feedback(uri)
          if annotation is Some(text) && range is Some(range) {
            services.feedback.add_feedback(
              uri,
              range,
              text,
              state=@agent_feedback_api.Submitted,
            )
            |> ignore
          }
        }
      }
    }
    match diff {
      Some((original, modified)) =>
        show_diff_comparison(
          owner, name, uri, absolute, relative, original, modified,
        )
      // The sibling comparison is intentionally parked when the source
      // surface is active or a replacement pair is still loading. CSS alone
      // selects the visible surface; keeping this bounded two-model cache
      // avoids a blank repaint and makes View file a non-destructive toggle.
      None => ()
    }
    set_search_match_highlights(
      if show_markdown {
        None
      } else {
        search_highlights
      },
    )
    if range is Some(range) {
      if show_markdown {
        markdown_viewer.reveal_range_in_center(range)
      } else {
        let target = navigation_target_presentation(range)
        viewer.set_position(target.position)
        let search_match = match search_highlights {
          Some(highlights) => highlights.ranges().contains(range)
          None => false
        }
        if search_match {
          ()
        } else if target.is_transient {
          if viewer.get_model() is Some(target_model) {
            show_transient_navigation_target_highlight(
              viewer,
              target_model,
              target.decoration,
            )
          }
        } else if viewer_state.point_range_highlight is Some(highlight) {
          highlight.set([target.decoration]) |> ignore
        }
        viewer.reveal_range_in_center(range)
      }
    }
  })
  @cmd.batch([show, request_viewer_remeasure()])
}

///|
/// Preserve reading position for an explicit tab/reload request and whenever
/// the Viewer replaces the model for the resource already on screen. The latter
/// covers generation-fenced review refreshes whose cached `Doc` is deliberately
/// parked as `TabLoading` while its old working text remains visible.
fn should_restore_view_state(
  explicit : Bool,
  previous : @common.Uri?,
  current : @common.Uri,
) -> Bool {
  explicit ||
  (previous is Some(previous) && previous.to_string() == current.to_string())
}

///|
/// Remove only the displayed model's quick-diff baseline. Ordinary navigation
/// out of review mode uses this before starting a ranged read, so a failed read
/// cannot leave the former HEAD gutter attached to an ordinary document.
fn clear_quick_diff_baseline() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if viewer_state.viewer is Some(viewer) &&
      viewer_state.services is Some(services) &&
      viewer.get_model() is Some(model) {
      services.quick_diff.set_original_content(model.uri, None)
    }
  })
}

///|
/// Whether Desktop applies the reference workbench's initial outline policy.
///
/// Only ordinary MoonBit `.mbt` source files opt in. Interfaces, literate
/// documents, extensionless sources, and other languages stay expanded.
fn should_auto_fold_top_level(text_model : @model.TextModel) -> Bool {
  text_model.get_language_id() == "moonbit" &&
  text_model.display_name.has_suffix(".mbt")
}

///|
/// Retire the source and Markdown documents on screen, the file identity they
/// were shown under, and the MBTI diagram.
fn clear_source_presentation() -> Unit {
  if viewer_state.viewer is Some(viewer) {
    if viewer_state.point_range_highlight is Some(highlight) {
      highlight.clear()
    }
    if viewer_state.search_match_highlights is Some(highlights) {
      highlights.clear()
    }
    if viewer_state.services is Some(services) &&
      viewer.get_model() is Some(model) {
      services.quick_diff.set_original_content(model.uri, None)
    }
    let previous = viewer.get_model()
    viewer.set_model(None)
    dispose_source_model(previous)
  }
  if viewer_state.markdown_viewer is Some(markdown_viewer) {
    dispose_markdown_model(markdown_viewer.set_model(None))
  }
  viewer_state.absolute = None
  viewer_state.relative = None
  viewer_state.navigation = None
  clear_mbti_diagram()
}

///|
/// Drop the viewer's current document so it falls back to the placeholder.
/// Used when the active conversation changes (which also invalidates every
/// parked scroll position — they belong to the previous workspace's tabs)
/// and when the last tab closes: the viewer is imperative state outside the
/// model, so it would otherwise keep showing the previous document. A no-op
/// until the viewer has been attached.
fn clear_viewer() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    viewer_state.view_states.clear()
    viewer_state.markdown_view_states.clear()
    clear_source_presentation()
    clear_diff_comparison()
    clear_semantic_review_editors()
  })
}

///|
/// Clear the active source presentation without touching the other tabs'
/// parked scroll positions. The comparison remains parked: transient review
/// reads, unavailable files, ordinary navigation, and View file all hide it by
/// CSS, while the next complete comparison replaces it atomically. Its memory
/// stays bounded to one pair and `clear_viewer` retires it at an owner boundary.
fn clear_document() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => clear_source_presentation())
}

///|
/// Forget a closed tab's parked scroll position. Batched after the
/// neighbor's `show_file_in_viewer` (which re-parks the outgoing document,
/// closed tab included), so the closed tab's entry does not linger.
fn forget_view_state(path : @pathx.Relative) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    viewer_state.view_states.remove(path.0)
    viewer_state.markdown_view_states.remove(path.0)
  })
}

///|
/// Draw the language server's diagnostics for the file at `absolute` onto the
/// viewer — but only while it still shows that file, so a push that raced a
/// file switch or a cleared panel is dropped. The diagnostics are keyed to the
/// model's own URI, so the viewer's marker-decoration service renders their
/// squiggles on the document on screen.
fn apply_diagnostics(
  channel : @interop.ChannelId,
  absolute : @common.Uri,
  diagnostics : Array[@protocol.LspDiagnostic],
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if @resource.belongs_to(absolute, channel) &&
      viewer_state.absolute is Some(current) &&
      current == absolute &&
      viewer_state.services is Some(services) {
      let uri = model_uri_of(absolute)
      services.markers.set_diagnostics(
        DiagnosticsOwner,
        uri,
        DiagnosticsProjection(diagnostics).to_viewer(),
      )
      refresh_semantic_modified_diagnostics(uri)
    }
  })
}

///|
/// The viewer language id for a file name. MoonBit source (`.mbt`, `.mbti`,
/// `.mbt.md`), `.mbtx` scripts, MoonBit manifests, JavaScript, and JSON have
/// tokenizers; everything else falls back to unhighlighted plain text. A
/// `.mbtx` script carries its own id but shares the MoonBit tokenizer, so its
/// top-of-file `import` block highlights exactly as MoonBit source does.
fn language_id(name : String) -> String {
  let lower = name.to_lower()
  if lower == "moon.pkg" || lower == "moon.mod" {
    "moonbit-config"
  } else if lower.has_suffix(".mbtx") {
    "mbtx"
  } else if lower.has_suffix(".mbt") ||
    lower.has_suffix(".mbti") ||
    lower.has_suffix(".mbt.md") {
    "moonbit"
  } else if lower.has_suffix(".js") ||
    lower.has_suffix(".mjs") ||
    lower.has_suffix(".cjs") {
    "javascript"
  } else if lower.has_suffix(".json") {
    "json"
  } else if lower.has_suffix(".md") {
    "markdown"
  } else {
    "plaintext"
  }
}
