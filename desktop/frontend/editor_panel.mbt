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
/// The single viewer instance, built lazily so its tokenizers register once.
let viewer_cell : Ref[@viewer.Viewer?] = Ref(None)

///|
/// Whether the viewer has been attached to its host element yet.
let viewer_attached : Ref[Bool] = Ref(false)

///|
/// Monotonic model version; the viewer treats a new version as a new document.
let model_version : Ref[Int] = Ref(0)

///|
/// The viewer, constructing it (and registering language tokenizers) on first
/// use. Held in a `Ref` rather than the model because it is imperative DOM
/// state the virtual DOM must not own.
fn viewer() -> @viewer.Viewer {
  match viewer_cell.val {
    Some(viewer) => viewer
    None => {
      register_tokenizers()
      let viewer = @viewer.Viewer(
        theme="light",
        placeholder="Select a file to view",
      )
      viewer_cell.val = Some(viewer)
      viewer
    }
  }
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
/// Attach the viewer to its host element after the next paint, once. A no-op
/// if already attached or the host element is not in the DOM yet.
fn request_viewer_mount() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _after => {
      if !viewer_attached.val &&
        @dom.document().get_element_by_id(ViewerHostId).to_option()
        is Some(host) {
        viewer().attach(host)
        viewer_attached.val = true
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
    _after => if viewer_attached.val { viewer().remeasure() },
    kind=@cmd.after_render,
  )
}

///|
/// Show a file's contents in the viewer as a fresh read-only document.
fn show_file_in_viewer(
  path : String,
  name : String,
  content : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    model_version.val = model_version.val + 1
    let version = model_version.val
    let uri : @common.Uri = { value: "openseek:///" + path }
    let text_model = @model.TextModel(
      uri,
      name,
      language_id(name),
      version,
      "v" + version.to_string(),
      content,
    )
    viewer().set_model(text_model, view_state=Reset)
  })
}

///|
/// Drop the viewer's current document so it falls back to the placeholder.
/// Used when the active conversation changes: the viewer is imperative state
/// outside the model, so it would otherwise keep showing the previous
/// conversation's file. A no-op until the viewer has been attached.
fn clear_viewer() -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    if viewer_attached.val {
      viewer().clear_model()
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
