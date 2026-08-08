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
  { root_uri: memory_uri(memory_root), directories, documents }
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
} derive(Eq)

///|
priv enum EmbedMsg {
  Boot
  OpenFile(@base_common.Uri)
  ViewerReady(@base_common.Uri)
  ViewerFailed
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
    OpenFile(uri) => (open_embed_document_cmd(uri), { status: "loading" })
    ViewerReady(uri) => (embed_tree().set_active(uri), { status: "ready" })
    ViewerFailed => (@rabbita.none, { status: "error" })
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
  _emit : @rabbita.Emit[EmbedMsg],
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
            ]),
            tree_html,
          ],
        ),
        // The stable view host: the viewer attaches its imperative DOM
        // into this element after the first paint; the shell must never
        // render vdom children into it.
        @html.div(class="viewer-host", ([] : Array[@html.Html])),
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
  let app = @rabbita.new(() => {
    let tree_view = embed_tree().view()
    let (model, emit) = @rabbita.create_state(
      { status: "loading" },
      update=(emit, msg, model) => {
        let (cmd, model) = update_embed(emit, msg, model)
        (model, cmd)
      },
      subscriptions=(emit, _model) => {
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
