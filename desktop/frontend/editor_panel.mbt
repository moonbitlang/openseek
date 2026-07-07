// The embedded read-only code viewer (moonbit-community/editor). Rabbita has
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
/// The single viewer instance. `None` until the first `request_viewer_mount`
/// finds the host element in the DOM — the viewer API constructs attached
/// (`Viewer::create`), so creation and mounting are one step. The host is
/// rendered on every screen from the first paint, and every file read is
/// batched behind a mount request whose after-render tick precedes the async
/// reply, so by the time a document arrives the viewer exists.
let viewer_cell : Ref[@viewer.Viewer?] = Ref(None)

///|
/// The viewer's services, built here rather than defaulted inside the viewer so
/// we keep a handle on the `MarkerService` — the viewer holds them privately.
/// The host pushes diagnostics through it (`apply_diagnostics`), and the viewer
/// renders the squiggles for whichever resource its model currently shows.
let services_cell : Ref[@viewer.ViewerServices?] = Ref(None)

///|
/// The absolute path of the file the viewer currently shows, so a diagnostics
/// push that arrives for a different file (or after the panel cleared its
/// document) is dropped rather than drawn over the wrong document. `None` when
/// the viewer shows a notice or nothing.
let current_absolute : Ref[@pathx.Absolute?] = Ref(None)

///|
/// The `MarkerService` owner for the language server's diagnostics — Monaco
/// keys markers by owner so one source's set replaces cleanly.
const DiagnosticsOwner = "moon-lsp"

///|
/// Monotonic model version; the viewer treats a new version as a new document.
let model_version : Ref[Int] = Ref(0)

///|
/// The mounted viewer, or `None` before the first mount. Held in a `Ref`
/// rather than the model because it is imperative DOM state the virtual DOM
/// must not own.
fn mounted_viewer() -> @viewer.Viewer? {
  viewer_cell.val
}

///|
/// Register syntax highlighting for the languages the panel can recognize.
/// Files of any other type render as plain text.
fn register_tokenizers() -> Unit {
  @languages.languages.set_tokens_provider(
    "moonbit",
    @lang_moonbit.MoonbitTokenizer::new(),
  )
  |> ignore
  @languages.languages.set_tokens_provider(
    "javascript",
    @lang_javascript.JavascriptTokenizer::new(),
  )
  |> ignore
  @languages.languages.set_tokens_provider(
    "json",
    @lang_json.JsonTokenizer::new(),
  )
  |> ignore
}

///|
/// Create the viewer in its host element after the next paint, once (the
/// tokenizers and hover provider register with it). A no-op if already
/// mounted or the host element is not in the DOM yet.
fn request_viewer_mount() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _after => {
      if viewer_cell.val is None &&
        @dom.document().get_element_by_id(ViewerHostId).to_option()
        is Some(host) {
        register_tokenizers()
        register_hover_provider()
        let services = @viewer.ViewerServices::new()
        services_cell.val = Some(services)
        let viewer = @viewer.Viewer::create(
          host,
          services~,
          options=@viewer.ViewerOptions(
            theme="light",
            placeholder="Select a file to view",
          ),
        )
        viewer_cell.val = Some(viewer)
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Re-measure the viewport after the panel's width changes (it is laid out by
/// CSS, so the viewer cannot see the change on its own).
fn request_viewer_remeasure() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _after => if mounted_viewer() is Some(viewer) { viewer.layout() },
    kind=@cmd.after_render,
  )
}

///|
/// Show a file's contents in the viewer as a fresh read-only document. A
/// symbol jump's `range`, when present, is revealed centered once the
/// document is set and — unless empty (a symbol placed without a range) —
/// selected, so the named code reads highlighted.
fn show_file_in_viewer(
  name : String,
  content : String,
  absolute? : @pathx.Absolute,
  range? : @common.Range? = None,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    // Reads are always batched behind a mount request whose after-render tick
    // runs before this async reply, so the viewer exists here (see
    // `viewer_cell`); the guard only drops a pathological stray.
    guard mounted_viewer() is Some(viewer) else { return }
    // Gate incoming diagnostics to the file now on screen (a notice document,
    // with no absolute path, takes no diagnostics).
    current_absolute.val = absolute
    model_version.val = model_version.val + 1
    let version = model_version.val
    // The URI is the file's absolute path — the whole address the hover
    // provider needs, travelling with the model itself. A notice document
    // (withheld binary/oversized file) has no file behind it, so its inert
    // URI never parses as a model path and hover stays off.
    let uri : @common.Uri = {
      value: match absolute {
        Some(absolute) => model_uri(absolute)
        None => "openseek-notice://" + @uri.encode_path(name)
      },
    }
    let text_model = @model.TextModel(
      uri,
      name,
      language_id(name),
      version,
      "v" + version.to_string(),
      content,
    )
    // `set_model` resets the view state itself (the Monaco contract), so a
    // fresh document always opens at the top.
    viewer.set_model(Some(text_model))
    if range is Some(range) {
      if !range.is_empty() {
        // `set_selection` never scrolls on its own (the Monaco contract), so
        // pair it with the reveal below.
        viewer.set_selection(
          @view_model.Selection::from_positions(
            range.get_start_position(),
            range.get_end_position(),
          ),
        )
      }
      viewer.reveal_range_in_center(range)
    }
  })
}

///|
/// Drop the viewer's current document so it falls back to the placeholder.
/// Used when the active conversation changes: the viewer is imperative state
/// outside the model, so it would otherwise keep showing the previous
/// conversation's file. A no-op until the viewer has been attached.
fn clear_viewer() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if mounted_viewer() is Some(viewer) {
      current_absolute.val = None
      viewer.set_model(None)
    }
  })
}

///|
/// Draw the language server's diagnostics for the file at `absolute` onto the
/// viewer — but only while it still shows that file, so a push that raced a
/// file switch or a cleared panel is dropped. The diagnostics are keyed to the
/// model's own URI, so the viewer's marker-decoration service renders their
/// squiggles on the document on screen.
fn apply_diagnostics(
  absolute : @pathx.Absolute,
  diagnostics : Json,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if current_absolute.val is Some(current) &&
      current == absolute &&
      services_cell.val is Some(services) {
      let uri : @common.Uri = { value: model_uri(absolute) }
      services.markers.set_diagnostics(
        DiagnosticsOwner,
        uri,
        decode_diagnostics(diagnostics),
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
