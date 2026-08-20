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
      Some({ unload: _ => (), update_tagger: _ => () })
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
    memory_file("large.mbt", "large.mbt"),
    memory_file("tabbed-deletion.mbt", "tabbed-deletion.mbt"),
    memory_file("oversized-line.mbt", "oversized-line.mbt"),
    memory_file("README.md", "README.md"),
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
  documents["\{memory_root}/large.mbt"] = large_diff_document("modified")
  documents["\{memory_root}/tabbed-deletion.mbt"] = "let retained = 1\n"
  documents["\{memory_root}/oversized-line.mbt"] = oversized_diff_line("m")
  documents["\{memory_root}/README.md"] = (
    #|# Embedded Markdown document
    #|
    #|This URI-backed in-memory model is rendered directly by the public **Viewer**.
    #|
    #|- No workbench presentation branch participates.
    #|- No remote protocol or WebSocket participates.
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
  original_documents["\{memory_root}/large.mbt"] = large_diff_document(
    "original",
  )
  original_documents["\{memory_root}/tabbed-deletion.mbt"] = "\t".repeat(160) +
    "deleted_tail\n"
  original_documents["\{memory_root}/oversized-line.mbt"] = oversized_diff_line(
    "o",
  )
  original_documents["\{memory_root}/README.md"] = (
    #|# Embedded document
    #|
    #|This in-memory model is rendered by the public Viewer.
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
/// the DiffViewer's ordinary Viewer virtualization.
fn large_diff_document(prefix : String) -> String {
  let content = StringBuilder()
  for index in 0..<2600 {
    content.write_string("let \{prefix}_\{index} = \{index}\n")
  }
  content.to_string()
}

///|
/// Each side is a single valid source line below the desktop's 1 MiB read
/// limit, while their combined UTF-16 size exceeds the legacy eager-diff budget.
fn oversized_diff_line(fill : String) -> String {
  fill.repeat(524289)
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
  embed_model_version.val = embed_model_version.val + 1
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
priv struct EmbedModel {
  status : String
  diff_visible : Bool
  unified_render : Bool
} derive(Eq)

///|
priv enum EmbedMsg {
  Boot
  OpenFile(@base_common.Uri)
  ViewerReady(@base_common.Uri)
  ViewerFailed
  ToggleDiff
  ToggleDiffLayout
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
let embed_diff_view_cell : Ref[@viewer.DiffViewer?] = Ref(None)

///|
/// Resolves the embedded viewer, creating it into the shell-rendered
/// `.viewer-host` element on first use. First use happens in the boot
/// after-render command, so the host element is always in the DOM by then.
fn embed_viewer() -> @viewer.Viewer {
  match embed_viewer_cell.val {
    Some(viewer) => viewer
    None => {
      let host = @rdom.document()
        .query_selector(".viewer-host")
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
/// Resolves the switchable public diff surface in its own stable host. Source
/// and diff views are siblings so toggling never replaces the source Viewer's
/// model, selection, or scroll state; render-mode changes stay inside the
/// DiffViewer.
fn embed_diff_view() -> @viewer.DiffViewer {
  match embed_diff_view_cell.val {
    Some(view) => view
    None => {
      let host = @rdom.document()
        .query_selector(".diff-viewer-host")
        .to_option()
        .unwrap()
      let view = @viewer.DiffViewer::create(host)
      embed_diff_view_cell.val = Some(view)
      view
    }
  }
}

///|
fn dispose_embed_diff_models(view : @viewer.DiffViewer) -> Unit {
  let models = view.get_model()
  view.clear()
  if models is Some(models) {
    models.original.dispose()
    if !models.modified.same(models.original) {
      models.modified.dispose()
    }
  }
}

///|
fn set_embed_diff_visible(visible : Bool) -> @rabbita.Cmd {
  @cmd.custom_cmd(
    _ => {
      if !visible {
        match embed_diff_view_cell.val {
          Some(view) => dispose_embed_diff_models(view)
          None => ()
        }
        return
      }
      guard embed_viewer().get_model() is Some(model) &&
        workspace_backend.original_documents.get(model.uri.to_string())
        is Some(original) else {
        return
      }
      let diff_view = embed_diff_view()
      dispose_embed_diff_models(diff_view)
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
      diff_view.set_model(Some(DiffEditorModel(original_model, modified_model)))
    },
    kind=@cmd.after_render,
  )
}

///|
fn set_embed_diff_render_mode(unified : Bool) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    embed_diff_view().set_render_mode(
      if unified {
        Unified
      } else {
        SideBySide
      },
    )
  })
}

///|
/// Production delegates directly to the native browser rAF queue. The
/// optional global hook lets the embed smoke test hold only this host-ready
/// callback while the Viewer's own render rAF continues normally.
extern "js" fn embed_ready_animation_frame(callback : () -> Unit) -> Unit =
  #| (callback) => {
  #|   const testHook = globalThis.__embeddedReadyAnimationFrame;
  #|   if (typeof testHook === 'function') {
  #|     testHook(callback);
  #|     return;
  #|   }
  #|   globalThis.requestAnimationFrame(callback);
  #| }

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
          set_embed_diff_visible(false),
          open_embed_document_cmd(uri),
        ]),
        { ..model, status: "loading", diff_visible: false },
      )
    ViewerReady(uri) =>
      (embed_tree().set_active(uri), { ..model, status: "ready" })
    ViewerFailed =>
      (
        set_embed_diff_visible(false),
        { ..model, status: "error", diff_visible: false },
      )
    ToggleDiff =>
      if model.status != "ready" {
        (@rabbita.none, model)
      } else {
        let visible = !model.diff_visible
        (set_embed_diff_visible(visible), { ..model, diff_visible: visible })
      }
    ToggleDiffLayout =>
      if model.status != "ready" || !model.diff_visible {
        (@rabbita.none, model)
      } else {
        let unified_render = !model.unified_render
        (
          set_embed_diff_render_mode(unified_render),
          { ..model, unified_render, },
        )
      }
  }
}

///|
fn open_embed_document_cmd(uri : @base_common.Uri) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    match workspace_backend.model(uri) {
      Some(model) => {
        let viewer = embed_viewer()
        viewer.set_model(Some(model))
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
                  title=if model.unified_render {
                    "Use side-by-side diff layout"
                  } else {
                    "Use unified diff layout"
                  },
                  disabled=!model.diff_visible,
                  on_click=emit(ToggleDiffLayout),
                  attrs=@html.Attrs::build()
                    .data_set("action", "toggle-diff-layout")
                    .aria_label("Unified diff layout")
                    .aria_pressed(model.unified_render.to_string()),
                  "Unified",
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
            class=if model.diff_visible {
              "viewer-host moonbit-viewer-surface-hidden"
            } else {
              "viewer-host"
            },
            ([] : Array[@html.Html]),
          ),
          @html.div(
            class=if model.diff_visible {
              "viewer-host diff-viewer-host"
            } else {
              "viewer-host diff-viewer-host moonbit-viewer-surface-hidden"
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
      { status: "loading", diff_visible: false, unified_render: false },
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
