///|
priv struct MermaidDiagram {
  wrapper : @rdom.Element
  source : String
  mut epoch : Int
}

///|
priv struct MermaidRenderRequest {
  lifetime : MarkdownDomLifetime
  diagram : MermaidDiagram
  epoch : Int
  theme : String
  loader : MermaidModuleLoader
}

///|
/// One serialized Mermaid runtime protects Mermaid's global initialize/render
/// pair while leaving per-target freshness and DOM ownership in MoonBit.
priv struct MermaidRuntime {
  requests : Array[MermaidRenderRequest]
  mut module_loader : MermaidModuleLoader?
  mut module_api : MermaidApi?
  mut running : Bool
  mut id_nonce : String
  mut next_diagram_id : Int
}

///|
let mermaid_runtime : MermaidRuntime = get_or_create_shared_mermaid_runtime(() => {
  requests: [],
  module_loader: None,
  module_api: None,
  running: false,
  id_nonce: new_mermaid_id_nonce(),
  next_diagram_id: 0,
})

///|
let mermaid_module_path = "mermaid/mermaid.esm.min.mjs"

///|
fn MermaidRuntime::enqueue(
  self : MermaidRuntime,
  request : MermaidRenderRequest,
) -> Unit {
  self.requests.push(request)
  self.pump()
}

///|
/// Advances the one realm-wide Mermaid queue. Mermaid configuration is global,
/// so module loading, `initialize`, and `render` remain serialized even when
/// different Viewer targets enqueue concurrently. Per-diagram epochs decide
/// whether the eventual result may commit.
///
/// ```mermaid
/// flowchart LR
///   A[Pump] --> B{Running or<br>queue empty?}
///   B -->|yes| C[Return]
///   B -->|no| D[Dequeue oldest<br>request]
///   D --> E[Load module or<br>reuse cached API]
///   E --> F{Rendered and consumer<br>still current?}
///   F -->|yes| G[Replace fallback<br>with SVG]
///   F -->|no| H[Discard stale or<br>failed result]
///   G --> I[Finish request,<br>pump again]
///   H --> I
/// ```
fn MermaidRuntime::pump(self : MermaidRuntime) -> Unit {
  if self.running || self.requests.length() == 0 {
    return
  }
  self.running = true
  let request = self.requests.remove(0)
  match (self.module_loader, self.module_api) {
    (Some(loader), Some(api)) if same_mermaid_loader(loader, request.loader) =>
      self.start_render(request, api)
    _ => {
      self.module_loader = Some(request.loader)
      self.module_api = None
      start_mermaid_module_load(
        request.loader,
        mermaid_module_path,
        api => {
          if self.module_loader is Some(loader) &&
            same_mermaid_loader(loader, request.loader) {
            self.module_api = Some(api)
          }
          self.start_render(request, api)
        },
        () => {
          if self.module_loader is Some(loader) &&
            same_mermaid_loader(loader, request.loader) {
            self.module_api = None
          }
          self.finish_request()
        },
      )
    }
  }
}

///|
fn MermaidRuntime::start_render(
  self : MermaidRuntime,
  request : MermaidRenderRequest,
  api : MermaidApi,
) -> Unit {
  start_mermaid_api_render(
    api,
    if request.theme == "light" {
      "default"
    } else {
      "dark"
    },
    self.next_id(request.lifetime.owner_document),
    request.diagram.source,
    result => request.commit(result),
    () => (),
    () => self.finish_request(),
  )
}

///|
fn MermaidRuntime::finish_request(self : MermaidRuntime) -> Unit {
  self.running = false
  self.pump()
}

///|
fn MermaidRuntime::next_id(
  self : MermaidRuntime,
  owner_document : @rdom.Document,
) -> String {
  while true {
    self.next_diagram_id += 1
    let id = "moonbit-markdown-mermaid-\{self.id_nonce}-\{self.next_diagram_id.to_string()}"
    if mermaid_id_is_available(owner_document, id) {
      return id
    }
  }
  abort("unreachable")
}

///|
fn MermaidRenderRequest::is_current(self : MermaidRenderRequest) -> Bool {
  self.lifetime.is_current() &&
  self.diagram.epoch == self.epoch &&
  markdown_target_contains_if_supported(
    self.lifetime.target,
    self.diagram.wrapper,
  )
}

///|
fn MermaidRenderRequest::commit(
  self : MermaidRenderRequest,
  result : MermaidRenderResult,
) -> Unit {
  guard self.is_current() else { return }
  let mut committed = false
  with_mermaid_render_svg(result, svg => {
    if self.is_current() {
      self.diagram.wrapper.set_inner_html(svg)
      self.diagram.wrapper.set_attribute("data-mermaid-state", "rendered")
      committed = true
    }
  })
  |> ignore
  guard committed else { return }
  try_bind_mermaid_result(result, self.diagram.wrapper)
  if self.is_current() {
    match self.lifetime.on_size_changed {
      Some(on_size_changed) => on_size_changed()
      None => ()
    }
  }
}
