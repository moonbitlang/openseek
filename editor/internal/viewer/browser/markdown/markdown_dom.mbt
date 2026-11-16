///|
/// MoonBit-owned browser lifetime for one rendered Markdown target.
priv struct MarkdownDomLifetime {
  target : @rdom.Element
  owner_document : @rdom.Document
  listeners : Array[@base_common.Disposable]
  mermaid_diagrams : Array[MermaidDiagram]
  mermaid_module_loader : MermaidModuleLoader
  /// Diago and UML renders, disposed with the lifetime.
  diagram_renders : Array[@diagrams.PendingDiagram]
  options : MarkdownRenderOptions
  mut target_token : MarkdownTargetToken?
  mut active : Bool
}

///|
/// Installs one renderer-owned lifetime into a caller-owned target. All HTML
/// policy runs in an inert parsed fragment; only the policy-processed result
/// reaches the live DOM. Reusing the target first disposes its previous
/// lifetime.
///
/// ```d2
/// direction: right
///
/// html: converted HTML
/// parse: inert parse
/// policy: sanitizing policy pass
/// target: caller target
/// mermaid: Mermaid queue
///
/// html -> parse
/// parse -> policy
/// policy -> target: replace once
/// diagrams: diagram renderer
///
/// target -> mermaid: enqueue wrappers
/// mermaid -> target: fresh SVG commit
/// target -> diagrams: Diago and UML wrappers
/// diagrams -> policy: generated SVG
/// ```
fn install_markdown_dom(
  target : @rdom.Element,
  html : String,
  options : MarkdownRenderOptions,
  mermaid_module_loader : MermaidModuleLoader,
) -> MarkdownDomLifetime {
  let owner_document = markdown_owner_document(target)
  let lifetime : MarkdownDomLifetime = {
    target,
    owner_document,
    listeners: [],
    mermaid_diagrams: [],
    mermaid_module_loader,
    diagram_renders: [],
    options,
    target_token: None,
    active: true,
  }
  let token = install_markdown_target_lifetime(
    markdown_target_registry,
    target,
    () => lifetime.dispose(),
  )
  lifetime.target_token = Some(token)
  let content = lifetime.sanitized_content(html)
  let pending_diagrams = lifetime.postprocess_diagrams(content)
  replace_target_with_markdown_content(target, content)
  lifetime.render_diagrams(pending_diagrams)
  match options.mermaid_theme {
    Some(theme) => lifetime.rerender_mermaid(mermaid_theme_name(theme))
    None => ()
  }
  lifetime
}

///|
/// Parses `html` into an inert fragment and applies the input, image and link
/// policy every fragment passes before it reaches the live DOM.
fn MarkdownDomLifetime::sanitized_content(
  self : MarkdownDomLifetime,
  html : String,
) -> MarkdownParsedContent {
  let content = parse_markdown_content(self.owner_document, html)
  postprocess_markdown_inputs(content)
  self.postprocess_images(
    content,
    self.options.base_uri,
    self.options.allow_remote_images,
  )
  self.postprocess_anchors(
    content,
    self.options.base_uri,
    self.options.action_handler,
  )
  content
}

///|
fn postprocess_markdown_inputs(content : MarkdownParsedContent) -> Unit {
  for input in markdown_content_query_all(content, "input") {
    if markdown_attribute_or_empty(input, "type").to_lower() != "checkbox" {
      remove_markdown_element(input)
    } else {
      disable_markdown_input(input)
    }
  }
}

///|
fn MarkdownDomLifetime::postprocess_images(
  self : MarkdownDomLifetime,
  content : MarkdownParsedContent,
  base_uri : @base_common.Uri?,
  allow_remote_images : Bool,
) -> Unit {
  let base_uri_string = base_uri.map(uri => uri.to_string()).unwrap_or("")
  let has_base_uri = base_uri is Some(_)
  for image in markdown_content_query_all(content, "img") {
    let resolved = if allow_remote_images {
      resolve_allowed_markdown_uri(
        markdown_attribute_or_empty(image, "src"),
        base_uri_string,
        has_base_uri,
        ImageUri,
      )
    } else {
      ""
    }
    if resolved == "" {
      remove_markdown_element(image)
      continue
    }
    image.set_attribute("src", resolved)
    if self.options.on_size_changed is Some(on_size_changed) {
      self.listen(image, "load", _event => if self.active { on_size_changed() })
    }
  }
}

///|
fn MarkdownDomLifetime::postprocess_anchors(
  self : MarkdownDomLifetime,
  content : MarkdownParsedContent,
  base_uri : @base_common.Uri?,
  action_handler : ((String) -> Unit)?,
) -> Unit {
  let base_uri_string = base_uri.map(uri => uri.to_string()).unwrap_or("")
  let has_base_uri = base_uri is Some(_)
  for anchor in markdown_content_query_all(content, "a") {
    let resolved = resolve_allowed_markdown_uri(
      markdown_attribute_or_empty(anchor, "href"),
      base_uri_string,
      has_base_uri,
      LinkUri,
    )
    if resolved == "" {
      make_markdown_anchor_inert(anchor)
      continue
    }
    match action_handler {
      None => {
        anchor.set_attribute("href", resolved)
        anchor.set_attribute("target", "_blank")
        anchor.set_attribute("rel", "noopener noreferrer")
      }
      Some(handler) => {
        anchor.remove_attribute("href")
        anchor.remove_attribute("target")
        anchor.remove_attribute("rel")
        anchor.set_attribute("role", "link")
        anchor.set_attribute("tabindex", "0")
        self.listen(anchor, "click", event => {
          event.prevent_default()
          let button = markdown_event_button(event)
          if self.active && (button == -1 || button == 0) {
            handler(resolved)
          }
        })
        self.listen(anchor, "auxclick", event => {
          event.prevent_default()
          if self.active && markdown_event_button(event) == 1 {
            handler(resolved)
          }
        })
        self.listen(anchor, "keydown", event => {
          let key = markdown_event_key(event)
          if key == "Enter" || key == " " || key == "Space" || key == "Spacebar" {
            event.prevent_default()
            if self.active {
              handler(resolved)
            }
          }
        })
      }
    }
  }
}

///|
/// Wires every diagram wrapper and returns the Diago and UML wrappers still
/// showing their source fallback.
fn MarkdownDomLifetime::postprocess_diagrams(
  self : MarkdownDomLifetime,
  content : MarkdownParsedContent,
) -> Array[(@rdom.Element, @diagrams.DiagramKind)] {
  let pending = []
  for diagram in markdown_content_query_all(content, "div") {
    if !markdown_element_has_class(diagram, "moonbit-viewer-markdown-diagram") {
      continue
    }
    let language = markdown_attribute_or_empty(diagram, "data-diagram-language")
    if self.options.mermaid_theme is Some(_) && language == "mermaid" {
      self.mermaid_diagrams.push({
        wrapper: diagram,
        source: markdown_diagram_source(diagram),
        epoch: 0,
      })
    }
    if markdown_attribute_or_empty(diagram, "data-diagram-state") == "fallback" &&
      @diagrams.DiagramKind::from_fence(language) is Some(kind) {
      pending.push((diagram, kind))
    }
    self.listen(diagram, "wheel", event => {
      if !self.active ||
        markdown_element_has_class(
          diagram, "moonbit-viewer-markdown-diagram-viewport",
        ) {
        return
      }
      let raw_delta_y = markdown_event_delta_y(event)
      let shift_key = markdown_event_shift_key(event)
      let raw_delta_x = markdown_event_delta_x(event)
      let delta_x = if raw_delta_x != 0.0 {
        raw_delta_x
      } else if shift_key {
        raw_delta_y
      } else {
        0.0
      }
      let delta_y = if shift_key { 0.0 } else { raw_delta_y }
      let consumes_x = markdown_can_scroll(
        delta_x,
        diagram.get_scroll_left(),
        diagram.get_client_width(),
        diagram.get_scroll_width(),
      )
      let consumes_y = markdown_can_scroll(
        delta_y,
        diagram.get_scroll_top(),
        diagram.get_client_height(),
        diagram.get_scroll_height(),
      )
      // Preserve native inner scrolling. At both boundaries, leave the event
      // available to the owning hover, widget, or editor surface.
      if consumes_x || consumes_y {
        event.stop_propagation()
      }
    })
  }
  pending
}

///|
/// Replaces each attached Diago/UML fallback with its compiled SVG. The SVG
/// passes the same input, image and link policy as converted Markdown before
/// it reaches the live DOM. A failed or missing renderer keeps the fallback.
fn MarkdownDomLifetime::render_diagrams(
  self : MarkdownDomLifetime,
  pending : Array[(@rdom.Element, @diagrams.DiagramKind)],
) -> Unit {
  for diagram in pending {
    let (wrapper, kind) = diagram
    let render = @diagrams.render(kind, markdown_diagram_source(wrapper), svg => {
      guard svg is Some(svg) else { return }
      replace_target_with_markdown_content(wrapper, self.sanitized_content(svg))
      wrapper.set_attribute("data-diagram-state", "rendered")
      if self.options.on_size_changed is Some(on_size_changed) {
        on_size_changed()
      }
    })
    self.diagram_renders.push(render)
  }
}

///|
fn MarkdownDomLifetime::listen(
  self : MarkdownDomLifetime,
  target : @rdom.Element,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_type, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn MarkdownDomLifetime::dispose(self : MarkdownDomLifetime) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  for diagram in self.mermaid_diagrams {
    diagram.epoch += 1
  }
  for render in self.diagram_renders {
    render.dispose()
  }
  while self.listeners.length() > 0 {
    let listener = self.listeners.remove(self.listeners.length() - 1)
    listener.dispose()
  }
  if self.target_token is Some(token) {
    clear_markdown_target_lifetime(markdown_target_registry, self.target, token)
  }
  self.target_token = None
}

///|
fn MarkdownDomLifetime::is_current(self : MarkdownDomLifetime) -> Bool {
  guard self.active else { return false }
  match self.target_token {
    Some(token) =>
      markdown_target_lifetime_is_current(
        markdown_target_registry,
        self.target,
        token,
      )
    None => false
  }
}

///|
fn MarkdownDomLifetime::rerender_mermaid(
  self : MarkdownDomLifetime,
  theme : String,
) -> Unit {
  if !self.active || self.options.mermaid_theme is None {
    return
  }
  for diagram in self.mermaid_diagrams {
    diagram.epoch += 1
    mermaid_runtime.enqueue({
      lifetime: self,
      diagram,
      epoch: diagram.epoch,
      theme,
      loader: self.mermaid_module_loader,
    })
  }
}

///|
fn make_markdown_anchor_inert(anchor : @rdom.Element) -> Unit {
  anchor.remove_attribute("href")
  anchor.remove_attribute("target")
  anchor.remove_attribute("rel")
  anchor.remove_attribute("role")
  anchor.remove_attribute("tabindex")
}

///|
fn markdown_can_scroll(
  delta : Double,
  position : Double,
  client_size : Double,
  scroll_size : Double,
) -> Bool {
  if delta < 0.0 {
    position > 0.0
  } else if delta > 0.0 {
    position + client_size < scroll_size - 1.0
  } else {
    false
  }
}

///|
#derive(Eq)
priv enum MarkdownUriKind {
  ImageUri
  LinkUri
}

///|
fn resolve_allowed_markdown_uri(
  raw : String,
  base_uri : String,
  has_base_uri : Bool,
  kind : MarkdownUriKind,
) -> String {
  guard !raw.is_empty() else { return "" }
  let base = if has_base_uri { Some(base_uri) } else { None }
  guard @base_browser.resolve_url(raw, base?) is Ok((href, protocol)) else {
    return ""
  }
  if protocol == "http:" ||
    protocol == "https:" ||
    (kind == LinkUri && protocol == "mailto:") {
    href
  } else {
    ""
  }
}

///|
fn markdown_attribute_or_empty(
  element : @rdom.Element,
  name : String,
) -> String {
  element.get_attribute(name).unwrap_or("")
}

///|
fn markdown_element_has_class(
  element : @rdom.Element,
  class_name : String,
) -> Bool {
  let normalized = markdown_attribute_or_empty(element, "class")
    .replace_all(old="\t", new=" ")
    .replace_all(old="\n", new=" ")
    .replace_all(old="\r", new=" ")
    .replace_all(old="\f", new=" ")
  normalized.split(" ").any(token => token == class_name)
}

///|
fn markdown_diagram_source(wrapper : @rdom.Element) -> String {
  let root = for candidate in wrapper.query_selector_all("div") {
    if markdown_element_has_class(candidate, "monaco-tokenized-source") {
      break candidate
    }
  } nobreak {
    wrapper
  }
  let output = StringBuilder()
  markdown_write_text_with_line_breaks(root.as_node(), output)
  output.to_string()
}

///|
fn markdown_write_text_with_line_breaks(
  node : @rdom.Node,
  output : StringBuilder,
) -> Unit {
  if node.get_node_type() == 3 {
    output.write_string(markdown_node_text_content(node))
    return
  }
  if node.get_node_type() == 1 && node.get_node_name() == "BR" {
    output.write_char('\n')
    return
  }
  for index in 0..<node.get_child_count() {
    markdown_write_text_with_line_breaks(node.get_child(index), output)
  }
}
