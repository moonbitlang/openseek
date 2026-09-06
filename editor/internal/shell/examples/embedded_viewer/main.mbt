// A real embedding target, the way Monaco's standalone editor proves its
// package boundary: the viewer library plus the file-tree widget mounted
// against in-memory documents and an in-memory tree provider, with zero server
// or websocket involvement. The host owns document selection and passes
// text models directly to the viewer.

///|
let memory_root : String = "memory://workspace"

///|
priv suberror StartupSubscription

///|
fn startup_sub(cmd : @cmd.Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "embedded-viewer-startup",
    Local,
    StartupSubscription,
    SubLoader((_, scheduler) => {
      scheduler.add(cmd)
      Some({ unload: _ => (), update_tagger: _ => (), })
    }),
  )
}

///|
/// In-memory workspace backend: a handful of hardcoded documents and
/// directories. The tree widget uses the `workspace` tree trait; the viewer
/// receives text models directly from host code.
priv struct MemoryWorkspace {
  root_uri : @base_common.Uri
  directories : Map[String, Array[@workspace.WorkspaceStat]]
  documents : Map[String, String]
  original_documents : Map[String, String]
}

///|
fn memory_uri(raw : String) -> @base_common.Uri {
  try! @base_common.Uri::parse(raw)
}

///|
fn memory_file(path : String, name : String) -> @workspace.WorkspaceStat {
  {
    uri: memory_uri("\{memory_root}/\{path}"),
    name,
    kind: File,
    children: None,
  }
}

///|
fn memory_dir(path : String, name : String) -> @workspace.WorkspaceStat {
  {
    uri: memory_uri("\{memory_root}/\{path}"),
    name,
    kind: Directory,
    children: None,
  }
}

///|
fn memory_workspace() -> MemoryWorkspace {
  let directories : Map[String, Array[@workspace.WorkspaceStat]] = Map([])
  directories[memory_root] = [
    memory_dir("src", "src"),
    memory_file("broken.mbt", "broken.mbt"),
    memory_file("comments-only.mbt", "comments-only.mbt"),
    memory_file("comments.mbt", "comments.mbt"),
    memory_file("alignment-zones.mbt", "alignment-zones.mbt"),
    memory_file("fragmented-large.mbt", "fragmented-large.mbt"),
    memory_file("large.mbt", "large.mbt"),
    memory_file("navigation-anchors.mbt", "navigation-anchors.mbt"),
    memory_file("scroll-sync.mbt", "scroll-sync.mbt"),
    memory_file("tabbed-deletion.mbt", "tabbed-deletion.mbt"),
    memory_file("oversized-line.mbt", "oversized-line.mbt"),
    memory_file("identical.mbt", "identical.mbt"),
    memory_file("README.md", "README.md"),
    memory_file("Guide.MD", "Guide.MD"),
    memory_file("tour.MBT.MD", "tour.MBT.MD"),
    memory_file("moon.mod", "moon.mod"),
  ]
  directories["\{memory_root}/src"] = [
    memory_dir("src/lib", "lib"),
    memory_file("src/main.mbt", "main.mbt"),
  ]
  directories["\{memory_root}/src/lib"] = [
    memory_file("src/lib/util.mbt", "util.mbt"),
  ]
  let documents : Map[String, String] = Map([])
  documents["\{memory_root}/broken.mbt"] = "fn okay() {}\n"
  documents["\{memory_root}/comments-only.mbt"] = [
    "fn stable() -> Int {", "", "  // updated note", "  1", "}",
  ].join("\n")
  documents["\{memory_root}/comments.mbt"] = [
    "fn review_value() -> Int {", "", "  // updated explanation", "  new_value()",
    "}",
  ].join("\n")
  documents["\{memory_root}/alignment-zones.mbt"] = alignment_diff_document(
    false,
  )
  documents["\{memory_root}/large.mbt"] = large_diff_document("modified")
  documents["\{memory_root}/fragmented-large.mbt"] = fragmented_deletion_document(
    false,
  )
  documents["\{memory_root}/navigation-anchors.mbt"] = [
    "fn navigation_anchors() {", "  let stable_head = 0", "  let stable_middle_one = 2",
    "  let stable_middle_two = 3", "  let stable_middle_three = 4", "  let stable_middle_four = 5",
    "  let stable_middle_five = 6", "  let stable_middle_six = 7", "  let inserted_only = 8",
    "  let stable_tail = 9", "}",
  ].join("\n")
  documents["\{memory_root}/scroll-sync.mbt"] = scroll_sync_document(false)
  documents["\{memory_root}/tabbed-deletion.mbt"] = "let retained = 1\n"
  documents["\{memory_root}/oversized-line.mbt"] = oversized_diff_line("m")
  documents["\{memory_root}/identical.mbt"] = identical_diff_document()
  documents["\{memory_root}/README.md"] = (
    #|# Embedded Markdown document
    #|
    #|This URI-backed in-memory model is rendered directly by the public **MarkdownViewer**.
    #|
    #|- The embedding host selects the Markdown presentation explicitly.
    #|- No remote protocol or WebSocket participates.
    #|
  )
  documents["\{memory_root}/Guide.MD"] = "# Uppercase Markdown\n"
  documents["\{memory_root}/tour.MBT.MD"] = (
    #|# MoonBit Markdown
    #|
    #|```mbt check
    #|let answer = 42
    #|```
    #|
  )
  documents["\{memory_root}/moon.mod"] = "name = \"embedded-example\"\n"
  documents["\{memory_root}/src/main.mbt"] = (
    #|///|
    #|fn main {
    #|  println(greeting())
    #|}
    #|
  )
  documents["\{memory_root}/src/lib/util.mbt"] = (
    #|///|
    #|pub fn util_answer() -> Int {
    #|  42
    #|}
    #|
  )
  let original_documents : Map[String, String] = Map([])
  original_documents["\{memory_root}/broken.mbt"] = "fn broken( {\n"
  original_documents["\{memory_root}/comments-only.mbt"] = [
    "fn stable() -> Int {", "  // obsolete note", "  1", "}",
  ].join("\n")
  original_documents["\{memory_root}/comments.mbt"] = [
    "fn review_value() -> Int {", "  // obsolete explanation", "  old_value()", "}",
  ].join("\n")
  original_documents["\{memory_root}/alignment-zones.mbt"] = alignment_diff_document(
    true,
  )
  original_documents["\{memory_root}/large.mbt"] = large_diff_document(
    "original",
  )
  original_documents["\{memory_root}/fragmented-large.mbt"] = fragmented_deletion_document(
    true,
  )
  original_documents["\{memory_root}/navigation-anchors.mbt"] = [
    "fn navigation_anchors() {", "  let stable_head = 0", "  let deleted_only = 1",
    "  let stable_middle_one = 2", "  let stable_middle_two = 3", "  let stable_middle_three = 4",
    "  let stable_middle_four = 5", "  let stable_middle_five = 6", "  let stable_middle_six = 7",
    "  let stable_tail = 9", "}",
  ].join("\n")
  original_documents["\{memory_root}/scroll-sync.mbt"] = scroll_sync_document(
    true,
  )
  original_documents["\{memory_root}/tabbed-deletion.mbt"] = "\t".repeat(160) +
    "deleted_tail\n"
  original_documents["\{memory_root}/oversized-line.mbt"] = oversized_diff_line(
    "o",
  )
  original_documents["\{memory_root}/identical.mbt"] = identical_diff_document()
  original_documents["\{memory_root}/README.md"] = (
    #|# Embedded document
    #|
    #|This in-memory model is rendered by the public MarkdownViewer.
    #|
  )
  original_documents["\{memory_root}/Guide.MD"] = "# Old uppercase Markdown\n"
  original_documents["\{memory_root}/tour.MBT.MD"] = (
    #|# Old MoonBit Markdown
    #|
    #|```mbt check
    #|let answer = 41
    #|```
    #|
  )
  original_documents["\{memory_root}/moon.mod"] = ""
  original_documents["\{memory_root}/src/main.mbt"] = (
    #|///|
    #|fn main {
    #|  println("hello")
    #|}
    #|
  )
  original_documents["\{memory_root}/src/lib/util.mbt"] = (
    #|///|
    #|pub fn util_answer() -> Int {
    #|  41
    #|}
    #|
  )
  {
    root_uri: memory_uri(memory_root),
    directories,
    documents,
    original_documents,
  }
}

///|
/// A valid sub-1-MiB source pair with enough short changed lines to exercise
/// the DiffEditor's two code-editor kernels and viewport virtualization.
fn large_diff_document(prefix : String) -> String {
  let content = StringBuilder()
  for index in 0..<2600 {
    content.write_string("let \{prefix}_\{index} = \{index}\n")
  }
  content.to_string()
}

///|
/// Twenty independent 130-line deletions separated by stable anchors. This
/// prevents a renderer from satisfying the DOM budget only for one giant hunk
/// while eagerly retaining every individually short deleted block.
fn fragmented_deletion_document(original : Bool) -> String {
  let content = StringBuilder()
  for fragment in 0..<20 {
    if original {
      for line in 0..<130 {
        content.write_string(
          "let fragment_\{fragment}_deleted_\{line} = \{line}\n",
        )
      }
    }
    content.write_string("let fragment_\{fragment}_retained = \{fragment}\n")
  }
  content.to_string()
}

///|
/// A valid MoonBit-shaped source pair with two independently measured
/// Markdown comment ViewZones and visible edits near the top, middle, and
/// bottom. Comment source line counts stay paired while their rendered pixel
/// heights differ; later code hunks also change logical line counts.
fn alignment_diff_document(original : Bool) -> String {
  let content = StringBuilder()
  content.write_string("fn alignment_fixture() -> Int {\n")
  for index in 0..<700 {
    if index == 20 {
      content.write_string("  //~ ## First rendered note\n")
      content.write_string(
        if original {
          "  //~ This original-side paragraph is deliberately long enough to wrap across several rendered rows in a narrow diff pane, so its external ViewZone has a larger measured pixel height than the modified-side note.\n"
        } else {
          "  //~ Short modified note.\n"
        },
      )
      content.write_string("  //~ Shared final sentence.\n")
    } else if index == 180 {
      content.write_string("  //~ ## Second rendered note\n")
      content.write_string(
        if original {
          "  //~ Short original note.\n"
        } else {
          "  //~ This modified-side paragraph is deliberately long enough to wrap across several rendered rows in a narrow diff pane, reversing which child owns the taller external ViewZone.\n"
        },
      )
      content.write_string("  //~ Shared final sentence.\n")
    } else if index == 60 {
      content.write_string("  //~ ## Shared note before an insertion\n")
      content.write_string("  //~ Shared note body.\n")
      if !original {
        content.write_string("  //~ Inserted documentation line.\n")
        content.write_string("  //~ Another inserted documentation line.\n")
        content.write_string("  let inserted_after_comment_60 = 60\n")
      }
    } else if index == 300 {
      content.write_string("  let replacement_300 = 300\n")
      if !original {
        content.write_string("  let inserted_301 = 301\n")
        content.write_string("  let inserted_302 = 302\n")
      }
    } else if index == 480 {
      content.write_string("  let replacement_480 = 480\n")
      if original {
        content.write_string("  let deleted_481 = 481\n")
        content.write_string("  let deleted_482 = 482\n")
        content.write_string("  let deleted_483 = 483\n")
      }
    } else if index == 80 {
      content.write_string(
        if original {
          "  let changed_80 = 80\n"
        } else {
          "  let changed_80 = 800\n"
        },
      )
    } else if index == 120 {
      content.write_string("  let wide_120 = \"" + "x".repeat(400) + "\"\n")
    } else if index == 640 {
      content.write_string(
        if original {
          "  let changed_640 = 640\n"
        } else {
          "  let changed_640 = 6400\n"
        },
      )
    } else {
      content.write_string("  let stable_\{index} = \{index}\n")
    }
  }
  content.write_string("  0\n}\n")
  content.to_string()
}

///|
priv struct EmbeddedAlignmentMarkdownProvider {}

///|
impl @language.MarkdownCommentProvider for EmbeddedAlignmentMarkdownProvider with fn provide_markdown_comments(
  _self,
  model,
) {
  if !model.uri.path.has_suffix("/alignment-zones.mbt") {
    return []
  }
  let snapshot = model.snapshot()
  let blocks : Array[@language.MarkdownCommentBlock] = []
  let mut line_number = 1
  while line_number <= snapshot.line_count() {
    if !snapshot.get_line_content(line_number).trim().has_prefix("//~") {
      line_number += 1
      continue
    }
    let start_line_number = line_number
    let markdown : Array[String] = []
    while line_number <= snapshot.line_count() {
      let line = snapshot.get_line_content(line_number).trim().to_owned()
      if !line.has_prefix("//~") {
        break
      }
      let mut start = 3
      if start < line.length() && line[start].to_int() == 32 {
        start += 1
      }
      markdown.push(line.unsafe_substring(start~, end=line.length()))
      line_number += 1
    }
    blocks.push({
      line_range: LineRange(start_line_number, line_number),
      markdown: markdown.join("\n"),
    })
  }
  blocks
}

///|
/// Each side is a single valid source line below the desktop's 1 MiB read
/// limit, while their combined UTF-16 size exceeds the legacy eager-diff budget.
fn oversized_diff_line(fill : String) -> String {
  fill.repeat(524289)
}

///|
/// Both panes overflow horizontally at ordinary split widths, but the
/// original has a much larger maximum. The shared stable tail also provides a
/// model-relative vertical anchor for two-way scroll and layout transitions.
fn scroll_sync_document(original : Bool) -> String {
  let content = StringBuilder()
  let wide = if original { "o".repeat(1800) } else { "m".repeat(700) }
  content.write_string("fn scroll_sync_fixture() {\n")
  content.write_string("  let wide = \"" + wide + "\"\n")
  for index in 0..<700 {
    content.write_string("  let scroll_stable_\{index} = \{index}\n")
  }
  content.write_string("}\n")
  content.to_string()
}

///|
fn identical_diff_document() -> String {
  [
    "fn identical_fixture() -> Int {", "  let unchanged = 42", "  unchanged", "}",
  ].join("\n")
}

///|
impl @workspace.WorkspaceTreeProvider for MemoryWorkspace with fn root(self) {
  self.root_uri
}

///|
impl @workspace.WorkspaceTreeProvider for MemoryWorkspace with fn resolve(
  self,
  uri,
) {
  match self.directories.get(uri.to_string()) {
    Some(children) =>
      WorkspaceResolved({
        uri,
        name: @base_common.basename_or_authority(uri),
        kind: Directory,
        children: Some(children),
      })
    None =>
      WorkspaceResolveError(
        FileSystemProviderError(FileNotFound, "Directory does not exist.", uri~),
      )
  }
}

///|
let workspace_backend : MemoryWorkspace = memory_workspace()

///|
let embed_model_version : Ref[Int] = Ref(0)

///|
fn next_embed_model_version() -> Int {
  embed_model_version.val += 1
  embed_model_version.val
}

///|
fn MemoryWorkspace::model(
  self : MemoryWorkspace,
  uri : @base_common.Uri,
) -> @model.TextModel? {
  match self.documents.get(uri.to_string()) {
    Some(text) => {
      let version = next_embed_model_version()
      Some(
        TextModel(
          uri,
          @base_common.basename_or_authority(uri),
          @workspace.infer_language_id(@base_common.basename_or_authority(uri)),
          version,
          "memory-\{version.to_string()}",
          text,
        ),
      )
    }
    None => None
  }
}

///|
priv enum EmbedSourcePresentation {
  Code
  Markdown
} derive(Eq)

///|
fn EmbedSourcePresentation::label(self : EmbedSourcePresentation) -> String {
  match self {
    Code => "code"
    Markdown => "markdown"
  }
}

///|
fn embed_source_presentation(uri : @base_common.Uri) -> EmbedSourcePresentation {
  if uri.path.to_lower().has_suffix(".md") {
    Markdown
  } else {
    Code
  }
}

///|
priv struct EmbedModel {
  status : String
  diff_visible : Bool
  inline_layout : Bool
  sash_enabled : Bool
  source_presentation : EmbedSourcePresentation
} derive(Eq)

///|
priv enum EmbedMsg {
  Boot
  OpenFile(@base_common.Uri)
  ViewerReady(@base_common.Uri)
  ViewerFailed
  ToggleDiff
  ToggleDiffLayout
  ToggleDiffSash
}

///|
let embed_dispatch : Ref[((EmbedMsg) -> Unit)?] = Ref(None)

///|
fn dispatch_embed_msg(msg : EmbedMsg) -> Unit {
  match embed_dispatch.val {
    Some(dispatch) => dispatch(msg)
    None => ()
  }
}

///|
let embed_viewer_cell : Ref[@viewer.Viewer?] = Ref(None)

///|
let embed_markdown_viewer_cell : Ref[@viewer.MarkdownViewer?] = Ref(None)

///|
let embed_diff_editor_cell : Ref[@viewer.DiffEditor?] = Ref(None)

///|
/// Resolves the embedded code viewer, creating it into the shell-rendered
/// `.code-viewer-host` element on first use. First use happens in the boot
/// after-render command, so the host element is always in the DOM by then.
fn embed_viewer() -> @viewer.Viewer {
  match embed_viewer_cell.val {
    Some(viewer) => viewer
    None => {
      let host = @rdom.document()
        .query_selector(".code-viewer-host")
        .to_option()
        .unwrap()
      let viewer = @viewer.Viewer::create(
        host,
        options=ViewerOptions(placeholder="Loading source..."),
      )
      viewer.on_did_change_model(event => {
        guard event.new_model_url is Some(attached_uri) else { return }
        // `attach_model` queued the Viewer flush before publishing this
        // semantic model event. Browser rAF callbacks are FIFO, so this host
        // callback runs after that pending DOM patch. A second URI check drops
        // stale callbacks from rapid model swaps.
        embed_ready_animation_frame(() => {
          match viewer.get_model() {
            Some(current) =>
              if current.uri.to_string() == attached_uri.to_string() {
                dispatch_embed_msg(ViewerReady(attached_uri))
              }
            None => ()
          }
        })
      })
      |> ignore
      embed_viewer_cell.val = Some(viewer)
      viewer
    }
  }
}

///|
/// The rich Markdown surface is a separate public widget. The embedding host,
/// rather than Viewer, owns presentation selection.
fn embed_markdown_viewer() -> @viewer.MarkdownViewer {
  match embed_markdown_viewer_cell.val {
    Some(viewer) => viewer
    None => {
      let host = @rdom.document()
        .query_selector(".markdown-viewer-host")
        .to_option()
        .unwrap()
      let viewer = @viewer.MarkdownViewer::create(
        host,
        options=MarkdownViewerOptions(placeholder="Loading Markdown..."),
      )
      viewer.on_did_change_model(event => {
        guard event.new_model_url is Some(attached_uri) else { return }
        embed_ready_animation_frame(() => {
          match viewer.get_model() {
            Some(current) =>
              if current.model.uri.to_string() == attached_uri.to_string() {
                dispatch_embed_msg(ViewerReady(attached_uri))
              }
            None => ()
          }
        })
      })
      |> ignore
      embed_markdown_viewer_cell.val = Some(viewer)
      viewer
    }
  }
}

///|
fn replace_embed_code_model(
  viewer : @viewer.Viewer,
  model : @model.TextModel?,
) -> Unit {
  let previous = viewer.get_model()
  viewer.set_model(model)
  match previous {
    Some(previous) =>
      match model {
        Some(current) if previous.same(current) => ()
        _ => previous.dispose()
      }
    None => ()
  }
}

///|
fn replace_embed_markdown_model(
  viewer : @viewer.MarkdownViewer,
  model : @viewer.MarkdownViewerModel?,
) -> Unit {
  match viewer.set_model(model) {
    Some(previous) =>
      match model {
        // A resource-kind-only replacement keeps the same active TextModel.
        Some(current) if previous.model.same(current.model) => ()
        _ => previous.model.dispose()
      }
    None => ()
  }
}

///|
fn embed_current_source_model() -> @model.TextModel? {
  match embed_viewer_cell.val {
    Some(viewer) if viewer.get_model() is Some(model) => return Some(model)
    _ => ()
  }
  match embed_markdown_viewer_cell.val {
    Some(viewer) => viewer.get_model().map(model => model.model)
    None => None
  }
}

///|
/// Resolves the switchable public diff surface in its own stable host. Source
/// and diff views are siblings. DiffEditor owns two internal code-editor
/// kernels and one shared diff ViewModel; it never creates a public Viewer.
fn embed_diff_editor() -> @viewer.DiffEditor {
  match embed_diff_editor_cell.val {
    Some(view) => view
    None => {
      let host = @rdom.document()
        .query_selector(".diff-editor-host")
        .to_option()
        .unwrap()
      let view = @viewer.DiffEditor::create(host)
      embed_diff_editor_cell.val = Some(view)
      view
    }
  }
}

///|
fn dispose_embed_diff_model_pair(models : @viewer.DiffEditorModel) -> Unit {
  models.original.dispose()
  if !models.modified.same(models.original) {
    models.modified.dispose()
  }
}

///|
fn replace_embed_diff_model(
  view : @viewer.DiffEditor,
  model : @viewer.DiffEditorModel?,
) -> Unit {
  // A same-pair no-op returns None, so the active models are never disposed.
  // A real replacement returns a pair that is already fully detached.
  match view.set_model(model) {
    Some(previous) => dispose_embed_diff_model_pair(previous)
    None => ()
  }
}

///|
fn set_embed_diff_visible(
  visible : Bool,
  inline_layout : Bool,
  sash_enabled : Bool,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(
    _ => {
      if !visible {
        match embed_diff_editor_cell.val {
          Some(view) => replace_embed_diff_model(view, None)
          None => ()
        }
        return
      }
      guard embed_current_source_model() is Some(model) &&
        workspace_backend.original_documents.get(model.uri.to_string())
        is Some(original) else {
        return
      }
      let diff_editor = embed_diff_editor()
      diff_editor.update_options(
        DiffEditorOptions(
          layout=if inline_layout { Inline } else { SideBySide },
          sash_enabled~,
          // This fixture deliberately exercises horizontal synchronization;
          // every other embedded diff keeps the production default.
          diff_word_wrap=if model.uri.path.has_suffix("/scroll-sync.mbt") {
            Off
          } else {
            Inherit
          },
        ),
      )
      let version = next_embed_model_version()
      let original_uri = @base_common.Uri::from(
        scheme="memory-original",
        authority=model.uri.authority,
        path=model.uri.path,
      ) catch {
        _ => return
      }
      let original_model = @model.TextModel(
        original_uri,
        model.display_name,
        model.language_id,
        version,
        "original-memory-\{version.to_string()}",
        original,
      )
      let modified_model = @model.TextModel(
        model.uri,
        model.display_name,
        model.language_id,
        version,
        "modified-memory-\{version.to_string()}",
        model.get_value(),
      )
      replace_embed_diff_model(
        diff_editor,
        Some(DiffEditorModel(original_model, modified_model)),
      )
    },
    kind=@cmd.after_render,
  )
}

///|
fn set_embed_diff_options(inline : Bool, sash_enabled : Bool) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    embed_diff_editor().update_options(
      DiffEditorOptions(
        layout=if inline { Inline } else { SideBySide },
        sash_enabled~,
      ),
    )
  })
}

///|
extern "js" fn embed_ready_animation_frame(callback : () -> Unit) -> Unit =
  #| (callback) => { globalThis.requestAnimationFrame(callback); }

///|
let embed_tree_cell : Ref[@file_tree.FileTree?] = Ref(None)

///|
fn embed_tree() -> @file_tree.FileTree {
  match embed_tree_cell.val {
    Some(tree) => tree
    None => {
      let tree = @file_tree.FileTree(workspace_backend, on_open=uri => {
        dispatch_embed_msg(OpenFile(uri))
      })
      embed_tree_cell.val = Some(tree)
      tree
    }
  }
}

///|
fn update_embed(
  _emit : @rabbita.Emit[EmbedMsg],
  msg : EmbedMsg,
  model : EmbedModel,
) -> (@rabbita.Cmd, EmbedModel) {
  match msg {
    Boot => {
      let first_file = memory_uri("\{memory_root}/src/main.mbt")
      (
        @rabbita.batch([
          embed_tree().refresh(),
          open_embed_document_cmd(first_file),
        ]),
        model,
      )
    }
    OpenFile(uri) =>
      (
        @rabbita.batch([
          set_embed_diff_visible(false, model.inline_layout, model.sash_enabled),
          open_embed_document_cmd(uri),
        ]),
        {
          ..model,
          status: "loading",
          diff_visible: false,
          source_presentation: embed_source_presentation(uri),
        },
      )
    ViewerReady(uri) =>
      (embed_tree().set_active(uri), { ..model, status: "ready", })
    ViewerFailed =>
      (
        set_embed_diff_visible(false, model.inline_layout, model.sash_enabled),
        { ..model, status: "error", diff_visible: false, },
      )
    ToggleDiff =>
      if model.status != "ready" {
        (@rabbita.none, model)
      } else {
        let visible = !model.diff_visible
        (
          set_embed_diff_visible(
            visible,
            model.inline_layout,
            model.sash_enabled,
          ),
          { ..model, diff_visible: visible, },
        )
      }
    ToggleDiffLayout | ToggleDiffSash => {
      if model.status != "ready" || !model.diff_visible {
        return (@rabbita.none, model)
      }
      let next = if msg is ToggleDiffLayout {
        { ..model, inline_layout: !model.inline_layout, }
      } else {
        { ..model, sash_enabled: !model.sash_enabled, }
      }
      (set_embed_diff_options(next.inline_layout, next.sash_enabled), next)
    }
  }
}

///|
fn open_embed_document_cmd(uri : @base_common.Uri) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    match workspace_backend.model(uri) {
      Some(model) =>
        if model.uri.path.to_lower().has_suffix(".md") ||
          model.get_language_id() == "markdown" {
          match embed_viewer_cell.val {
            Some(viewer) => replace_embed_code_model(viewer, None)
            None => ()
          }
          let viewer = embed_markdown_viewer()
          let resource_kind = if model.uri.path.to_lower().has_suffix(".mbt.md") {
            @viewer.MarkdownResourceKind::MoonBitMarkdown
          } else {
            OrdinaryMarkdown
          }
          replace_embed_markdown_model(
            viewer,
            Some(MarkdownViewerModel(model, resource_kind)),
          )
          viewer.handle_initialized()
        } else {
          match embed_markdown_viewer_cell.val {
            Some(viewer) => replace_embed_markdown_model(viewer, None)
            None => ()
          }
          let viewer = embed_viewer()
          replace_embed_code_model(viewer, Some(model))
          viewer.handle_initialized()
        }
      None => dispatch_embed_msg(ViewerFailed)
    }
  })
}

///|
fn view_embed(
  emit : @rabbita.Emit[EmbedMsg],
  model : EmbedModel,
  tree_html : @html.Html,
) -> @html.Html {
  @html.main_(
    class="editor-shell",
    attrs=@html.Attrs::build()
      .data_set("status", model.status)
      .data_set("source-presentation", model.source_presentation.label())
      .data_set("theme", "dark"),
    [
      @html.div(class="editor-main", [
        @html.aside(
          class="workspace-sidebar",
          attrs=@html.Attrs::build().aria_label("Workspace files"),
          [
            @html.div(class="workspace-title", [
              @html.span(class="workspace-title-label", "Explorer"),
              @html.div(class="workspace-title-actions", [
                @html.button(
                  type_="button",
                  class="sidebar-action embed-diff-toggle",
                  title=if model.diff_visible {
                    "Show source"
                  } else {
                    "Show full diff"
                  },
                  on_click=emit(ToggleDiff),
                  attrs=@html.Attrs::build()
                    .data_set("action", "toggle-diff")
                    .aria_label("Full diff")
                    .aria_pressed(model.diff_visible.to_string()),
                  if model.diff_visible {
                    "Source"
                  } else {
                    "Diff"
                  },
                ),
                @html.button(
                  type_="button",
                  class="sidebar-action embed-diff-toggle",
                  title=if model.inline_layout {
                    "Use side-by-side diff layout"
                  } else {
                    "Use inline diff layout"
                  },
                  disabled=!model.diff_visible,
                  on_click=emit(ToggleDiffLayout),
                  attrs=@html.Attrs::build()
                    .data_set("action", "toggle-diff-layout")
                    .aria_label("Inline diff layout")
                    .aria_pressed(model.inline_layout.to_string()),
                  "Inline",
                ),
                @html.button(
                  type_="button",
                  class="sidebar-action embed-diff-toggle",
                  title=if model.sash_enabled {
                    "Disable diff pane sash"
                  } else {
                    "Enable diff pane sash"
                  },
                  disabled=!model.diff_visible,
                  on_click=emit(ToggleDiffSash),
                  attrs=@html.Attrs::build()
                    .data_set("action", "toggle-diff-sash")
                    .aria_label("Diff pane sash")
                    .aria_pressed(model.sash_enabled.to_string()),
                  "Sash",
                ),
              ]),
            ]),
            tree_html,
          ],
        ),
        @html.div(class="embedded-viewer-stack", [
          // Stable imperative-DOM hosts share the grid's content cell; the
          // shell never renders vdom children into either host.
          @html.div(
            class=if model.diff_visible || model.source_presentation == Markdown {
              "viewer-host code-viewer-host moonbit-viewer-surface-hidden"
            } else {
              "viewer-host code-viewer-host"
            },
            ([] : Array[@html.Html]),
          ),
          @html.div(
            class=if model.diff_visible || model.source_presentation == Code {
              "viewer-host markdown-viewer-host moonbit-viewer-surface-hidden"
            } else {
              "viewer-host markdown-viewer-host"
            },
            ([] : Array[@html.Html]),
          ),
          @html.div(
            class=if model.diff_visible {
              "viewer-host diff-editor-host"
            } else {
              "viewer-host diff-editor-host moonbit-viewer-surface-hidden"
            },
            ([] : Array[@html.Html]),
          ),
        ]),
      ]),
    ],
  )
}

///|
fn main {
  // Compile the external-facade contract in `public_api_contract.mbt` without
  // executing it in the example. The discarded function value keeps every
  // supported root/common signature checked by the real embedding package.
  let _ = compile_external_viewer_api_contract
  @languages.languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    EmbeddedAlignmentMarkdownProvider::{ },
  )
  |> ignore
  // Highlighting needs no server: the language package is composed in
  // by import and registered through the viewer languages facade.
  @languages.languages.set_tokens_provider(
    "moonbit",
    @lang_moonbit.MoonBitTokenizer(),
  )
  |> ignore
  @languages.languages.set_tokens_provider(
    "moonbit-config",
    @lang_moon_config.MoonConfigTokenizer(),
  )
  |> ignore
  let app = @rabbita.new(() => {
    let tree_view = embed_tree().view()
    let (model, emit) = @rabbita.create_state(
      {
        status: "loading",
        diff_visible: false,
        inline_layout: false,
        sash_enabled: true,
        source_presentation: Code,
      },
      update=(model, msg, emit) => {
        let (cmd, model) = update_embed(emit, msg, model)
        (model, cmd)
      },
      subscriptions=(_model, emit) => {
        startup_sub(
          @cmd.custom_cmd(scheduler => {
            embed_dispatch.val = Some(msg => scheduler.add(emit(msg)))
            // Boot after the first paint: the view host and tree value must be
            // in the DOM before the viewer attaches and opens.
            scheduler.add(
              @cmd.custom_cmd(
                after => {
                  embed_viewer() |> ignore
                  after.add(emit(Boot))
                },
                kind=@cmd.after_render,
              ),
            )
          }),
        )
      },
    )
    model.view2(tree_view, (model, tree_html) => {
      view_embed(emit, model, tree_html)
    })
  })
  app.mount("app")
}
