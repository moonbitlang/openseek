// The embedded read-only code viewer (moonbitlang/editor). Rabbita has
// no escape hatch for a foreign DOM widget, so the viewer owns one stable,
// never-diffed host element: the view renders `<div id="viewer-host">` empty,
// and after the first paint the viewer attaches its imperative DOM into it.
// The host element is always rendered (merely hidden by CSS when the panel is
// closed), so the viewer attaches exactly once and survives screen switches.

///|
/// The id of the stable element the viewer attaches into; the panel view must
/// render exactly one empty element with this id.
const ViewerHostId = "viewer-host"

///|
/// The `MarkerService` owner for the language server's diagnostics — Monaco
/// keys markers by owner so one source's set replaces cleanly.
const DiagnosticsOwner = "moon-lsp"

///|
/// The viewer's imperative state — the attached widget, its services, and the
/// document it currently shows. None of this may live in the Rabbita model
/// (the virtual DOM must not own imperative DOM state), so it is collected
/// into this one module-level instance instead of loose globals.
priv struct ViewerHost {
  // The single viewer instance. `None` until the first `request_viewer_mount`
  // finds the host element in the DOM — the viewer API constructs attached
  // (`Viewer::create`), so creation and mounting are one step. The host is
  // rendered on every screen from the first paint, and every file read is
  // batched behind a mount request whose after-render tick precedes the async
  // reply, so by the time a document arrives the viewer exists.
  mut viewer : @viewer.Viewer?
  // Desktop owns the concrete marker and feedback stores passed through the
  // Viewer's public handle API. They receive language-server diagnostics and
  // turn inline reviews into composer chips without requiring editor internals.
  mut services : DesktopViewerServices?
  // The absolute path of the file the viewer currently shows, so a
  // diagnostics push that arrives for a different file (or after the panel
  // cleared its document) is dropped rather than drawn over the wrong
  // document. `None` when the viewer shows a notice or nothing.
  mut absolute : @pathx.Absolute?
  // The same file as the conversation names it — the workspace-relative path
  // the panel read it by. A comment filed on the shown document takes this
  // as its chip path, so the chip never has to reverse-engineer a relative
  // name from the absolute one (which the frontend cannot do before the
  // first run reports `cwd`). `None` when the viewer shows a notice or
  // nothing.
  mut relative : @pathx.Relative?
  // The active host/workspace route for Definition/References targets and
  // cross-file Peek previews. Cleared together with the document so a late
  // navigation request can never reopen a previous conversation's file.
  mut navigation : NavigationContext?
  // Monotonic model version; the viewer treats a new version as a new
  // document.
  mut version : Int
  // Each open tab's last scroll position, keyed by workspace-relative path,
  // saved as the viewer switches away and restored when the tab returns.
  // Scroll is DOM state, so it lives here beside the viewer rather than in
  // the Rabbita model.
  view_states : Map[String, @viewer.ViewerViewState]
}

///|
let viewer_state : ViewerHost = {
  viewer: None,
  services: None,
  absolute: None,
  relative: None,
  navigation: None,
  version: 0,
  view_states: Map([]),
}

///|
/// The mounted viewer, or `None` before the first mount.
fn mounted_viewer() -> @viewer.Viewer? {
  viewer_state.viewer
}

///|
/// Register syntax highlighting for the languages the panel can recognize.
/// Files of any other type render as plain text.
fn register_tokenizers() -> Unit {
  @languages.languages.set_tokens_provider(
    "moonbit",
    @lang_moonbit.MoonbitTokenizer(),
  )
  |> ignore
  @languages.languages.set_tokens_provider(
    "javascript",
    @lang_javascript.JavascriptTokenizer(),
  )
  |> ignore
  @languages.languages.set_tokens_provider("json", @lang_json.JsonTokenizer())
  |> ignore
  install_moonbit_markdown_comment_provider()
}

///|
/// Create the viewer in its host element after the next paint, once (the
/// tokenizers and hover provider register with it). A no-op if already
/// mounted or the host element is not in the DOM yet.
///
/// Mounting also wires the comment flow: a comment the user submits through
/// the viewer's agent-feedback input is handed to the update loop as
/// `EditorCommentAdded` — with the selected source quoted out of the current
/// model — so it becomes a chip on the composer draft.
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
        )
        viewer_state.services = Some(services)
        let viewer = @viewer.Viewer::create(
          host,
          services=services.viewer_services,
          options=@viewer.ViewerOptions(
            theme="light",
            placeholder="Select a file to view",
          ),
        )
        viewer_state.viewer = Some(viewer)
        services.feedback.on_did_add_feedback(event => {
          // Only user comments on a file this app put on screen (a URI it
          // minted) become chips; anything else is not ours to carry.
          guard event.feedback.kind is @agent_feedback_api.UserReview else {
            return
          }
          guard model_uri_path(event.feedback.resource) is Some(_) else {
            return
          }
          // Commenting happens through the viewer's own UI, so the feedback
          // can only target the document on screen — the one whose
          // workspace-relative name was recorded when it was shown. A
          // mismatch would mean a stray event for a document already gone;
          // there is nothing correct to attach it to.
          guard viewer.get_model() is Some(model) &&
            model.uri.to_string() == event.feedback.resource.to_string() &&
            viewer_state.relative is Some(file) else {
            return
          }
          scheduler.add(
            dispatch(
              EditorCommentAdded(
                // Just guarded as a URI this app minted.
                resource=ModelUri(event.feedback.resource.to_string()),
                file~,
                range=event.feedback.range,
                quote=model.get_value_in_range(event.feedback.range),
                comment=event.feedback.text,
                feedback_id=event.feedback.id,
              ),
            ),
          )
        })
        |> ignore
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Clear one comment bubble from the editor once its text has become a
/// composer chip — the chip is the comment's carrier from then on. Routed by
/// the same model URI the feedback was filed under. Public for the main
/// package's `EditorCommentAdded` handler, which owns the chip flow.
pub fn remove_editor_feedback(
  resource : ModelUri,
  feedback_id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    guard viewer_state.services is Some(services) else { return }
    // The string is the `to_string()` of a URI this package minted, so the
    // re-parse cannot fail; a stray unparsable string has no bubble anyway.
    let uri = @common.Uri::parse(resource.0) catch { _ => return }
    services.feedback.remove_feedback(uri, feedback_id)
  })
}

///|
/// Re-measure the viewport after the panel's width changes (it is laid out by
/// CSS, so the viewer cannot see the change on its own). Public for the main
/// package's viewport-resize handler — a window resize or phone rotation
/// changes the panel's host size without any panel message.
pub fn request_viewer_remeasure() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _after => if viewer_state.viewer is Some(viewer) { viewer.layout() },
    kind=@cmd.after_render,
  )
}

///|
/// Show a file's contents in the viewer as a fresh read-only document. A
/// symbol jump's `range`, when present, is revealed centered once the
/// document is set and — unless empty (a symbol placed without a range) —
/// selected, so the named code reads highlighted. `annotation`, when present
/// (an annotation chip's jump), is re-shown as a comment bubble over `range`
/// — the bubble the chip replaced when the comment was filed.
///
/// The outgoing document's scroll position is always saved under its
/// relative path; `restore_scroll` (a tab switch or an in-place reload)
/// brings the incoming document back to its saved position instead of the
/// top — the Monaco save/restore-view-state contract around `set_model`.
fn show_file_in_viewer(
  owner : @interop.ConversationKey,
  workspace : @pathx.Absolute?,
  name : String,
  content : String,
  absolute? : @pathx.Absolute,
  relative? : @pathx.Relative,
  range? : @common.Range? = None,
  annotation? : String,
  restore_scroll? : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    // Reads are always batched behind a mount request whose after-render tick
    // runs before this async reply, so the viewer exists here (see
    // `ViewerHost::viewer`); the guard only drops a pathological stray.
    guard viewer_state.viewer is Some(viewer) else { return }
    // The URI is the file's absolute path — the whole address the hover
    // provider needs, travelling with the model itself. A notice document
    // (withheld binary/oversized file) has no file behind it, so its inert
    // scheme never parses as a model path and hover stays off.
    let uri = match absolute {
      Some(absolute) => model_uri_of(owner.channel, absolute)
      None => app_uri("openseek-notice", "/" + name)
    }
    // Whether anything needs redrawing is decided here, against the document
    // the viewer really shows — the update loop only says "show this", it
    // does not guess at the screen from its tab cache. When the viewer
    // already displays this exact text (a reload that found the disk
    // unchanged, or a jump into the file on screen), the model is left
    // untouched so the selection, scroll, and feedback bubbles survive; a
    // jump's reveal and annotation still apply below, over the kept document.
    let same_document = viewer.get_model() is Some(model) &&
      model.uri.to_string() == uri.to_string() &&
      model.get_value() == content
    if !same_document {
      // Park the outgoing document's scroll position for its tab's return.
      if viewer_state.relative is Some(prev) &&
        viewer.get_model() is Some(_) &&
        viewer.save_view_state() is Some(view_state) {
        viewer_state.view_states[prev.0] = view_state
      }
      viewer_state.version = viewer_state.version + 1
      let version = viewer_state.version
      let text_model = @model.TextModel(
        uri,
        name,
        language_id(name),
        version,
        "v" + version.to_string(),
        content,
      )
      // `set_model` resets the view state itself (the Monaco contract), so a
      // fresh document always opens at the top; a tab switch or reload then
      // restores the saved position over that reset.
      viewer.set_model(Some(text_model))
      if restore_scroll &&
        relative is Some(rel) &&
        viewer_state.view_states.get(rel.0) is Some(saved) {
        viewer.restore_view_state(Some(saved))
      }
      // Match the reference workbench's host policy: ordinary `.mbt` files
      // open as a top-level outline. `set_model` computes folding ranges
      // synchronously, so this is stable initialization state rather than a
      // delayed render effect. Keeping it in the fresh-model branch leaves
      // folding interactions on the current model entirely user-controlled.
      if should_auto_fold_top_level(text_model) {
        viewer.fold_top_level()
      }
    }
    // Gate incoming diagnostics to the file now on screen (a notice document,
    // with no absolute path, takes no diagnostics). The relative name rides
    // along for comments filed on this document (see `ViewerHost::relative`).
    viewer_state.absolute = absolute
    viewer_state.relative = relative
    viewer_state.navigation = match (absolute, relative) {
      (Some(absolute), Some(relative)) =>
        navigation_context_for_file(owner, workspace, absolute, relative)
      _ => None
    }
    // Commenting (select → inline input → composer chip) is for real files;
    // a notice document has nothing behind it to comment on.
    if viewer_state.services is Some(services) {
      services.feedback.set_feedback_enabled(uri, absolute is Some(_))
      if absolute is Some(_) {
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
    if range is Some(range) {
      if !range.is_empty() {
        // `set_selection` never scrolls on its own (the Monaco contract), so
        // pair it with the reveal below.
        viewer.set_selection(
          @core.Selection::from_positions(
            range.get_start_position(),
            @common.Position(range.end_line_number, range.end_column),
          ),
        )
      }
      viewer.reveal_range_in_center(range)
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
/// Drop the viewer's current document so it falls back to the placeholder.
/// Used when the active conversation changes (which also invalidates every
/// parked scroll position — they belong to the previous workspace's tabs)
/// and when the last tab closes: the viewer is imperative state outside the
/// model, so it would otherwise keep showing the previous document. A no-op
/// until the viewer has been attached.
fn clear_viewer() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    viewer_state.view_states.clear()
    if viewer_state.viewer is Some(viewer) {
      viewer_state.absolute = None
      viewer_state.relative = None
      viewer_state.navigation = None
      viewer.set_model(None)
    }
  })
}

///|
/// Show the viewer's placeholder without touching the other tabs' parked
/// scroll positions — the last-tab-closed case, where the panel stays on
/// this conversation.
fn clear_document() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if viewer_state.viewer is Some(viewer) {
      viewer_state.absolute = None
      viewer_state.relative = None
      viewer_state.navigation = None
      viewer.set_model(None)
    }
  })
}

///|
/// Forget a closed tab's parked scroll position. Batched after the
/// neighbor's `show_file_in_viewer` (which re-parks the outgoing document,
/// closed tab included), so the closed tab's entry does not linger.
fn forget_view_state(path : @pathx.Relative) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => viewer_state.view_states.remove(path.0))
}

///|
/// Draw the language server's diagnostics for the file at `absolute` onto the
/// viewer — but only while it still shows that file, so a push that raced a
/// file switch or a cleared panel is dropped. The diagnostics are keyed to the
/// model's own URI, so the viewer's marker-decoration service renders their
/// squiggles on the document on screen.
fn apply_diagnostics(
  channel : @interop.ChannelId,
  absolute : @pathx.Absolute,
  diagnostics : Array[@protocol.LspDiagnostic],
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if viewer_state.absolute is Some(current) &&
      current == absolute &&
      viewer_state.services is Some(services) {
      let uri = model_uri_of(channel, absolute)
      services.markers.set_diagnostics(
        DiagnosticsOwner,
        uri,
        DiagnosticsProjection(diagnostics).to_viewer(),
      )
    }
  })
}

///|
/// The viewer language id for a file name. Only MoonBit, JavaScript and JSON
/// have tokenizers; everything else falls back to unhighlighted plain text.
fn language_id(name : String) -> String {
  let lower = name.to_lower()
  if lower.has_suffix(".mbt") ||
    lower.has_suffix(".mbti") ||
    lower.has_suffix(".mbt.md") {
    "moonbit"
  } else if lower.has_suffix(".js") ||
    lower.has_suffix(".mjs") ||
    lower.has_suffix(".cjs") {
    "javascript"
  } else if lower.has_suffix(".json") {
    "json"
  } else {
    "plaintext"
  }
}
