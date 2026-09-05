// Markdown rendering for transcript content. The engine's assistant text is
// CommonMark (with the GFM-ish cmark extensions: tables, strikethrough, task
// lists); this module parses it with moonbit-community/cmark and maps the
// document tree directly onto Rabbita nodes. Untrusted model output therefore
// never reaches `innerHTML`: raw HTML blocks and spans are rendered as visible
// text instead of being injected into the DOM.

///|
/// Render a markdown string to a list of block-level Rabbita nodes.
///
/// The parse is guarded: cmark can panic on some inputs (observed: "Index
/// out of bounds" in `Parser::add_open_blocks` on streaming-truncated text).
/// A panic escaping `view` would kill Rabbita's render loop — and since
/// every delta re-renders the same accumulated text, the transcript would
/// freeze on the last good frame forever. MoonBit panics on the js target
/// surface as JS exceptions, so `@js.Error_::wrap` is the one place a cmark
/// crash can be contained; the fallback shows the raw text instead.
///
/// `open_file`, when supplied, turns explicit local-path links and positioned
/// file references in prose into clickable elements whose click runs the
/// returned command (the frontend opens the file or reveals the directory).
/// Absent (tests, plain rendering), explicit links remain ordinary anchors.
/// Inline code stays inert.
pub fn markdown_nodes(
  source : String,
  open_file? : (String) -> @cmd.Cmd,
) -> Array[@html.Html] {
  @js.Error_::wrap(() => {
    let doc = @cmark.Doc::from_string(source, strict=false)
    let render = MarkdownRender::{ defs: doc.defs, open_file, }
    @js.Value::cast_from(render.block_nodes(doc.block))
  }) catch {
    _ => [@html.pre(class="markdown-fallback", source)]
  }
}

///|
priv struct MarkdownRender {
  // Link-reference and footnote definitions collected by the parser, used to
  // resolve `[text][label]` style references to their destinations.
  defs : Map[String, @cmark.LabelDef]
  // How to make a file path clickable; `None` renders paths inertly.
  open_file : ((String) -> @cmd.Cmd)?
}

///|
fn MarkdownRender::block_nodes(
  self : MarkdownRender,
  block : @cmark.Block,
) -> Array[@html.Html] {
  let out : Array[@html.Html] = []
  self.push_block(out, block)
  out
}

///|
fn MarkdownRender::push_block(
  self : MarkdownRender,
  out : Array[@html.Html],
  block : @cmark.Block,
) -> Unit {
  match block {
    BlankLine(_) | LinkRefDefinition(_) => ()
    Blocks(node) =>
      for child in node.v.iter() {
        self.push_block(out, child)
      }
    Paragraph(node) => out.push(@html.p(self.inline_nodes(node.v.inline)))
    Heading(node) => out.push(self.heading(node.v))
    BlockQuote(node) =>
      out.push(@html.blockquote(self.block_nodes(node.v.block)))
    CodeBlock(node) | ExtMathBlock(node) => out.push(code_block(node.v))
    // Raw HTML is shown as text, not injected; see the module comment.
    HtmlBlock(node) =>
      out.push(@html.pre(class="raw-html", lines_text(node.v.0)))
    List(node) => out.push(self.list(node.v))
    ThematicBreak(_) => out.push(@html.hr())
    ExtTable(node) => out.push(self.table(node.v))
    ExtFootnoteDefinition(node) => {
      let children : Array[@html.Html] = [
        @html.span(class="footnote-label", node.v.label.key),
      ]
      for child in self.block_nodes(node.v.block) {
        children.push(child)
      }
      out.push(@html.div(class="footnote", children))
    }
  }
}

///|
fn MarkdownRender::heading(
  self : MarkdownRender,
  heading : @cmark.BlockHeading,
) -> @html.Html {
  let children = self.inline_nodes(heading.inline)
  match heading.level {
    1 => @html.h1(children)
    2 => @html.h2(children)
    3 => @html.h3(children)
    4 => @html.h4(children)
    5 => @html.h5(children)
    _ => @html.h6(children)
  }
}

///|
fn lines_text(lines : @cmark.Seq[@cmark.Node[String]]) -> String {
  lines.iter().map(line => line.v).join("\n")
}

///|
#warnings("-alert_xss_vulnerable")
fn code_block(block : @cmark.CodeBlock) -> @html.Html {
  let language = match block.info_string {
    Some(info) =>
      match @cmark.CodeBlock::language_of_info_string(info.v) {
        Some((language, _)) => language
        None => ""
      }
    None => ""
  }
  let source = lines_text(block.code)
  if language == "uml" || language == "plantuml" {
    match @editor_viewer.render_uml_diagram_svg(source) {
      Some(svg) =>
        return @html.div(
          class="chat-markdown-diagram moonbit-viewer-markdown-diagram",
          attrs=@html.Attrs::build()
            .data_set("diagram-language", "uml")
            .inner_html(svg),
          ([] : Array[@html.Html]),
        )
      None => ()
    }
  }
  let code_class = if language.is_empty() { "" } else { "language-" + language }
  @html.pre([@html.code(class=code_class, source)])
}

///|
fn MarkdownRender::list(
  self : MarkdownRender,
  list : @cmark.BlockList,
) -> @html.Html {
  let items : Array[@html.Html] = []
  for item_node in list.items.iter() {
    let item = item_node.v
    let children : Array[@html.Html] = []
    if item.ext_task_marker is Some(marker) {
      let symbol = match @cmark.ListTaskStatus::from_marker(marker.v) {
        Checked => "☑"
        Cancelled => "☒"
        Unchecked | Other(_) => "☐"
      }
      children.push(@html.span(class="task-marker", symbol + " "))
    }
    for child in self.block_nodes(item.block) {
      children.push(child)
    }
    items.push(@html.li(children))
  }
  let class = if list.tight { "tight" } else { "" }
  match list.ty {
    Ordered(start, _) => @html.ol(class~, start~, items)
    Unordered(_) => @html.ul(class~, items)
  }
}

///|
fn MarkdownRender::table(
  self : MarkdownRender,
  table : @cmark.Table,
) -> @html.Html {
  let head : Array[@html.Html] = []
  let body : Array[@html.Html] = []
  for row in table.rows.iter() {
    let (row_node, _) = row
    match row_node.v {
      Header(cells) => {
        let cell_nodes : Array[@html.Html] = []
        for cell in cells.iter() {
          cell_nodes.push(@html.th(self.inline_nodes(cell.0)))
        }
        head.push(@html.tr(cell_nodes))
      }
      Data(cells) => {
        let cell_nodes : Array[@html.Html] = []
        for cell in cells.iter() {
          cell_nodes.push(@html.td(self.inline_nodes(cell.0)))
        }
        body.push(@html.tr(cell_nodes))
      }
      Sep(_) => ()
    }
  }
  @html.table([@html.thead(head), @html.tbody(body)])
}

///|
fn MarkdownRender::inline_nodes(
  self : MarkdownRender,
  inline : @cmark.Inline,
  linkify_urls? : Bool = true,
) -> Array[@html.Html] {
  let out : Array[@html.Html] = []
  self.push_inline(out, inline, linkify_urls~)
  out
}

///|
fn MarkdownRender::push_inline(
  self : MarkdownRender,
  out : Array[@html.Html],
  inline : @cmark.Inline,
  linkify_urls~ : Bool,
) -> Unit {
  match inline {
    Text(node) =>
      if linkify_urls {
        for child in self.prose_nodes(node.v) {
          out.push(child)
        }
      } else {
        out.push(@html.text(node.v))
      }
    Inlines(node) =>
      for child in node.v.iter() {
        self.push_inline(out, child, linkify_urls~)
      }
    Break(node) =>
      match node.v.ty {
        Hard => out.push(@html.br())
        Soft => out.push(@html.text(" "))
      }
    // Inline code stays plain code even when it names a file. Positioned file
    // references are recognized only in prose or an explicit link below.
    CodeSpan(node) => out.push(@html.code(class="inline-code", node.v.code()))
    Emphasis(node) =>
      out.push(@html.em(self.inline_nodes(node.v.inline, linkify_urls~)))
    StrongEmphasis(node) =>
      out.push(@html.strong(self.inline_nodes(node.v.inline, linkify_urls~)))
    ExtStrikethrough(node) =>
      out.push(@html.del(self.inline_nodes(node.v.0, linkify_urls~)))
    ExtMathSpan(node) => out.push(@html.code(class="inline-code", node.v.tex()))
    Autolink(node) => {
      let url = node.v.link.v
      // Email autolinks resolve to a safe `mailto:`; a URI autolink like
      // <javascript:alert(1)> must pass the same unsafe-scheme filter as
      // regular links and images, otherwise it renders as inert text.
      if node.v.is_email {
        out.push(link_node("mailto:" + url, [@html.text(url)]))
      } else if @cmark.InlineLink::is_unsafe(url) {
        out.push(@html.text(url))
      } else {
        out.push(link_node(url, [@html.text(url)]))
      }
    }
    Link(node) => {
      // The label is already inside an anchor. Leaving bare-URL detection on
      // here would turn `[https://label](https://target)` into nested anchors.
      let children = self.inline_nodes(node.v.text, linkify_urls=false)
      // The destination is authoritative Markdown data; the label is only
      // presentation and may deliberately describe another location.
      // `file://` is deliberately handled as an app action before cmark's
      // unsafe-scheme filter. It never becomes a browser anchor.
      if self.open_file is Some(open) &&
        self.file_destination(node.v) is Some(path) {
        out.push(file_link_node(open, path, children))
      } else {
        match self.link_destination(node.v) {
          Some(url) => out.push(link_node(url, children))
          None => out.push(@html.span(children))
        }
      }
    }
    // Images keep their alt text visible; the picture itself is only loaded
    // from destinations that pass the same safety filter as links.
    Image(node) => {
      let alt = plain_text(node.v.text)
      if self.local_image_destination(node.v) is Some(path) {
        // Local paths must not resolve against the page's `proton://app/`
        // origin. Leave `src` empty and let the transcript's viewport observer
        // read bounded bytes from the owning host only when this node is seen.
        out.push(
          @html.img(
            class="transcript-image pending",
            alt~,
            title=path,
            loading="lazy",
            decoding="async",
            attrs=@html.Attrs::build().data_set("transcript-image", path),
          ),
        )
      } else {
        match self.link_destination(node.v) {
          Some(url) => out.push(@html.img(src=url, alt~, loading="lazy"))
          None => out.push(@html.text(alt))
        }
      }
    }
    // Raw HTML is shown as text, not injected; see the module comment.
    RawHtml(node) => out.push(@html.text(tights_text(node.v.0)))
  }
}

///|
/// Bare HTTP(S) URLs in conversation prose. CommonMark only autolinks URLs
/// written inside angle brackets, while conversational text commonly emits
/// them directly. The match stops at whitespace/markup delimiters; prose
/// punctuation is separated below before the anchor is built.
let bare_web_url_pattern : Regex = re"(?i:https?)://[^[:space:]<>]+"

///|
/// Bare prose candidates that carry an unambiguous editor position. Ordinary
/// path-shaped words stay text to avoid reviving the old noisy linkification.
let bare_interactive_pattern : Regex = re"(?i:https?)://[^[:space:]<>]+|[[:alnum:]_~./@+:\-\\]+\.[[:alnum:]_+\-]{1,8}(?::[[:digit:]]+(?::[[:digit:]]+)?|#L[[:digit:]]+)"

///|
/// Remove prose punctuation from the end of a URL-shaped token. Balanced
/// closing delimiters remain part of the URL (`.../wiki/Foo_(bar)`), while an
/// unmatched delimiter supplied by the surrounding sentence does not.
fn trim_bare_url(candidate : String) -> (String, String) {
  let mut url = candidate
  for ;; {
    let old_length = url.length()
    url = url.trim_end(chars=".,;:!?\"'").to_owned()
    url = trim_unmatched_closer(url, '(', ')', ")")
    url = trim_unmatched_closer(url, '[', ']', "]")
    url = trim_unmatched_closer(url, '{', '}', "}")
    if url.length() == old_length {
      break
    }
  }
  let suffix = candidate.view(start_offset=url.length()).to_owned()
  (url, suffix)
}

///|
/// Drop one trailing closer when the URL contains more of it than its opener.
fn trim_unmatched_closer(
  url : String,
  opener : Char,
  closer : Char,
  suffix : String,
) -> String {
  guard url.has_suffix(suffix) else { return url }
  let (opens, closes) = for ch in url; opens = 0, closes = 0 {
    if ch == opener {
      continue opens + 1, closes
    } else if ch == closer {
      continue opens, closes + 1
    } else {
      continue opens, closes
    }
  } nobreak {
    (opens, closes)
  }
  if closes > opens {
    url.view(end_offset=url.length() - 1).to_owned()
  } else {
    url
  }
}

///|
/// Whether a matched token has a non-empty web authority. This excludes a
/// bare `https://`, which is useful text while streaming but not a destination
/// the browser can navigate to.
fn has_web_authority(url : String) -> Bool {
  let scheme_length = if url.length() >= 8 &&
    url.view(end_offset=8).equal_ignore_ascii_case("https://") {
    8
  } else {
    7
  }
  let rest = url.view(start_offset=scheme_length)
  for index, ch in rest {
    if ch == '/' || ch == '?' || ch == '#' {
      return index > 0
    }
  }
  !rest.is_empty()
}

///|
/// Render plain conversation prose with bare HTTP(S) URLs as safe external
/// anchors. Callers decide which spans are prose: Markdown code spans and the
/// user's backtick-delimited snippets deliberately bypass this helper.
pub fn linkified_text_nodes(source : String) -> Array[@html.Html] {
  let out : Array[@html.Html] = []
  let mut rest = source.view()
  while bare_web_url_pattern.execute(rest) is Some(matched) {
    if !matched.before().is_empty() {
      out.push(@html.text(matched.before().to_owned()))
    }
    let (url, suffix) = trim_bare_url(matched.content().to_owned())
    if has_web_authority(url) {
      out.push(link_node(url, [@html.text(url)]))
    } else {
      out.push(@html.text(url))
    }
    if !suffix.is_empty() {
      out.push(@html.text(suffix))
    }
    rest = matched.after()
  }
  if !rest.is_empty() {
    out.push(@html.text(rest.to_owned()))
  }
  out
}

///|
/// Render ordinary transcript prose. URL behavior stays identical to the
/// public URL-only renderer, while a configured file opener additionally
/// turns location-bearing path tokens into file buttons.
fn MarkdownRender::prose_nodes(
  self : MarkdownRender,
  source : String,
) -> Array[@html.Html] {
  guard self.open_file is Some(open) else {
    return linkified_text_nodes(source)
  }
  let out : Array[@html.Html] = []
  let mut rest = source.view()
  while bare_interactive_pattern.execute(rest) is Some(matched) {
    let before = matched.before()
    if !before.is_empty() {
      out.push(@html.text(before.to_owned()))
    }
    let candidate = matched.content().to_owned()
    if candidate.view() =~ re"(?i:^https?://)" {
      let (url, suffix) = trim_bare_url(candidate)
      // Keep the URL-only renderer's contract here: prose may only create an
      // HTTP(S) anchor when the destination has a non-empty authority. In
      // particular, a file-shaped custom scheme must stay inert text.
      if has_web_authority(url) {
        out.push(link_node(url, [@html.text(url)]))
      } else {
        out.push(@html.text(url))
      }
      if !suffix.is_empty() {
        out.push(@html.text(suffix))
      }
    } else if is_file_path(candidate) &&
      // The regex cannot use look-around, so validate both sides here. A
      // match after `%` may be the middle of `build%20/src/a.mbt:12`, while
      // whitespace and prose delimiters establish a fresh token.
      (before.is_empty() || before =~ re"[[:space:]<>,;!?\"'(){}\[\]]$") &&
      // A sentence-ending dot is a boundary; `.bak` continues the same token.
      (
        matched.after().is_empty() ||
        matched.after() =~ re"^[[:space:]<>,;!?\"'(){}\[\]]" ||
        matched.after() =~ re"^\.(?:$|[[:space:]<>,;!?\"'(){}\[\]])"
      ) {
      out.push(file_link_node(open, candidate, [@html.text(candidate)]))
    } else {
      out.push(@html.text(candidate))
    }
    rest = matched.after()
  }
  if !rest.is_empty() {
    out.push(@html.text(rest.to_owned()))
  }
  out
}

///|
/// The resolved, safe destination of a link or image. `None` for unresolved
/// references and for destinations cmark flags as unsafe (`javascript:` and
/// friends); the caller then renders the text without linking it.
fn MarkdownRender::link_destination(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> String? {
  guard self.raw_link_destination(link) is Some(destination) else {
    return None
  }
  if @cmark.InlineLink::is_unsafe(destination) {
    None
  } else {
    Some(destination)
  }
}

///|
/// Resolve an inline or reference-style Markdown link without deciding how
/// its scheme may be used. Callers must either apply cmark's unsafe-scheme
/// filter or convert a local `file://` URI into an app-owned filesystem path.
fn MarkdownRender::raw_link_destination(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> String? {
  let definition = match link.reference {
    Inline(node) => Some(node.v)
    Ref(_, _, _) =>
      match link.reference_definition(self.defs) {
        Some(LinkDef(node)) => Some(node.v)
        _ => None
      }
  }
  match definition {
    Some(definition) => definition.dest.map(dest => dest.v)
    None => None
  }
}

///|
/// A Markdown destination that the app may open as a local path. Ordinary
/// path destinations retain the existing cmark safety check. A `file://` URI
/// is accepted only for this machine, with no query, and is converted to a
/// decoded filesystem path before it reaches the host.
fn MarkdownRender::file_destination(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> String? {
  guard self.raw_link_destination(link) is Some(destination) else {
    return None
  }
  if FileReference(destination).local_file_uri_path() is Some(path) {
    return Some(path)
  }
  if !@cmark.InlineLink::is_unsafe(destination) && is_local_path(destination) {
    Some(destination)
  } else {
    None
  }
}

///|
/// A local raster image destination. Explicit `file://` URIs use the same
/// local-host rules as file links. Plain URI-reference paths are percent
/// decoded and may be absolute or relative (including `..`); their extension
/// is only a rendering hint because the host later verifies the byte signature.
fn MarkdownRender::local_image_destination(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> String? {
  guard self.raw_link_destination(link) is Some(destination) else {
    return None
  }
  if FileReference(destination).local_file_uri_path() is Some(path) {
    return if LocalImagePath(path).has_raster_extension() {
      Some(path)
    } else {
      None
    }
  }
  if @cmark.InlineLink::is_unsafe(destination) ||
    destination.contains("://") ||
    destination.has_prefix("//") ||
    destination.contains_any(chars="?#") {
    return None
  }
  // `Uri::parse` requires a scheme in strict mode and promotes a missing one
  // to `file:` otherwise. A private scheme lets it percent-decode the path
  // without changing whether that path was absolute or relative.
  let uri = @common.Uri::parse("openseek-local:" + destination, strict=true) catch {
    _ => return None
  }
  guard uri.scheme == "openseek-local" &&
    uri.authority.is_empty() &&
    uri.query.is_empty() &&
    uri.fragment.is_empty() else {
    return None
  }
  if LocalImagePath(uri.path).has_raster_extension() {
    Some(uri.path)
  } else {
    None
  }
}

///|
/// A model-authored path that is a candidate for host-backed image loading.
priv struct LocalImagePath(String)

///|
fn LocalImagePath::has_raster_extension(self : LocalImagePath) -> Bool {
  guard !self.0.is_blank() &&
    !self.0.contains_any(chars="\t\r\n") &&
    !self.0.has_suffix("/") else {
    return false
  }
  let base = match self.0.rev_split_once("/") {
    Some((_, base)) => base.to_owned()
    None => self.0
  }
  guard file_extension(base) is Some(ext) else { return false }
  ext.equal_ignore_ascii_case("png") ||
  ext.equal_ignore_ascii_case("jpg") ||
  ext.equal_ignore_ascii_case("jpeg") ||
  ext.equal_ignore_ascii_case("gif") ||
  ext.equal_ignore_ascii_case("webp")
}

///|
fn link_node(href : String, children : Array[@html.Html]) -> @html.Html {
  @html.a(href~, target=Blank, rel="noopener noreferrer", children)
}

///|
/// A clickable file reference: a button styled inline whose click runs the
/// command the frontend built for `path`. A button (not an anchor) because
/// only buttons carry an `on_click` in this html layer, and opening is an app
/// action rather than navigation.
fn file_link_node(
  open : (String) -> @cmd.Cmd,
  path : String,
  children : Array[@html.Html],
) -> @html.Html {
  @html.button(
    class="file-link",
    type_="button",
    title="Open \{path}",
    attrs=@html.Attrs::build().data_set("context-file", path),
    on_click=open(path),
    children,
  )
}

///|
/// One file reference as it appears in a link label or destination.
priv struct FileReference(String)

///|
/// Convert a local `file://` URI into the path understood by `host.open_path`.
/// Empty authority and `localhost` both identify this machine; other hosts are
/// not silently treated as local paths. A fragment is retained only when it is
/// the supported positive `#Lline` editor position.
fn FileReference::local_file_uri_path(self : FileReference) -> String? {
  guard self.0.view() =~ re"(?i:^file://)" else { return None }
  let uri = @common.Uri::parse(self.0) catch { _ => return None }
  guard uri.scheme.equal_ignore_ascii_case("file") &&
    (
      uri.authority.is_empty() ||
      uri.authority.equal_ignore_ascii_case("localhost")
    ) &&
    uri.query.is_empty() else {
    return None
  }
  let position = if uri.fragment.is_empty() {
    ""
  } else if uri.fragment.view() =~ re"^L[1-9][[:digit:]]*$" {
    "#" + uri.fragment
  } else {
    return None
  }
  // `Uri::fs_path` preserves a non-empty authority as a UNC host. Normalize
  // the conventional `localhost` spelling to the same local URI as an empty
  // authority before asking for the platform-specific filesystem path.
  let local_uri = if uri.authority.is_empty() {
    uri
  } else {
    @common.Uri::from(scheme="file", path=uri.path) catch {
      _ => return None
    }
  }
  let path = local_uri.fs_path()
  guard !path.is_empty() &&
    !path.contains_any(chars="\t\r\n") &&
    !path.has_suffix("/") else {
    return None
  }
  let base = match path.rev_split_once("/") {
    Some((_, base)) => base.to_owned()
    None => path
  }
  // Spaces are valid here because URI parsing has already decoded `%20`.
  // Unlike bare prose, an explicit `file://` destination is already clearly
  // path-shaped, so only the same plausible-extension check is needed.
  guard file_extension(base) is Some(_) else { return None }
  Some(path + position)
}

///|
/// The path before a supported editor position, when one is present.
fn FileReference::position_path(self : FileReference) -> String? {
  if self.0.view() =~ (re":[[:digit:]]+(?::[[:digit:]]+)?$", before=path) {
    return Some(path.to_owned())
  }
  if self.0.view() =~ (re"#L[[:digit:]]+$", before=path) {
    return Some(path.to_owned())
  }
  None
}

///|
/// The suffix-free path, or the whole reference when it has no position.
fn FileReference::path(self : FileReference) -> String {
  self.position_path().unwrap_or(self.0)
}

///|
/// Explicit Markdown destinations that unambiguously name a local path. A
/// slash-bearing target may be a file or directory; the host decides from the
/// filesystem when clicked. Bare destinations stay conservative and retain
/// the known-file-extension rule so prose-like links do not become actions.
fn is_local_path(text : String) -> Bool {
  let s = text.trim().to_owned()
  guard !s.is_empty() && !s.contains_any(chars="\t\r\n") else { return false }
  guard !s.contains("://") &&
    !s.has_prefix("#") &&
    !s.has_prefix("mailto:") &&
    !s.contains("?") else {
    return false
  }
  let path = FileReference(s).path()
  guard !path.contains("#") else { return false }
  // Colons are either a Windows drive prefix or position syntax already
  // removed above. Rejecting other colon forms keeps custom schemes inert.
  if path.contains(":") && !is_windows_drive_path(path) {
    return false
  }
  path.contains("/") || path.contains("\\") || is_file_path(s)
}

///|
fn is_windows_drive_path(path : String) -> Bool {
  guard path.length() >= 3 && path[1] == ':' else { return false }
  let drive = path[0]
  let letter = (drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')
  letter && (path[2] == '/' || path[2] == '\\')
}

///|
/// Whether a string looks like a file path worth making clickable: a single
/// whitespace-free token, not a URL, whose final component ends in a known
/// source-file extension. Both `src/main.mbt` and a bare `main.mbt` qualify.
/// Pure shape only — the host decides at open time whether the file exists, so
/// a false positive just fails to open rather than misleading the eye much.
fn is_file_path(text : String) -> Bool {
  let s = text.trim().to_owned()
  guard !s.is_empty() else { return false }
  guard !s.contains_any(chars=" \t\r\n") else { return false }
  // URLs (`https://…`, `mailto:…`) and bare fragments are not local files.
  guard !s.contains("://") && !s.has_prefix("#") && !s.has_prefix("mailto:") else {
    return false
  }
  // A trailing separator marks a directory, not a file.
  guard !s.has_suffix("/") else { return false }
  // Location suffixes are shape metadata, not part of the extension. Keep the
  // original `s` for the click: the host must first check whether that literal
  // positioned filename exists before interpreting the suffix.
  let path = FileReference(s).path()
  let base = match path.rev_split_once("/") {
    Some((_, base)) => base.to_owned()
    None => path
  }
  guard file_extension(base) is Some(ext) else { return false }
  // A `/` makes "this is a path" unambiguous, so any real extension counts
  // (`.pptx`, `.pdf`, …). A bare token needs a recognized type to avoid
  // lighting up prose like `self.value` or `obj.method`.
  path.contains("/") || is_known_extension(ext)
}

///|
/// The extension of `name` — the suffix after its last dot, with a non-empty
/// stem (so dotfiles like `.gitignore` do not count) and a plausible length.
/// `None` when there is no such suffix.
fn file_extension(name : String) -> String? {
  guard name.rev_split_once(".") is Some((stem, ext)) else { return None }
  guard !stem.is_empty() else { return None }
  let ext = ext.to_owned()
  guard ext.length() >= 1 && ext.length() <= 8 else { return None }
  Some(ext)
}

///|
/// Whether `ext` is a recognized source, config, document, or media file type.
/// Only consulted for bare filenames (no directory component); slash-bearing
/// paths accept any extension.
fn is_known_extension(ext : String) -> Bool {
  match ext {
    "mbt"
    | "mbti"
    | "c"
    | "h"
    | "cpp"
    | "cc"
    | "hpp"
    | "js"
    | "mjs"
    | "cjs"
    | "ts"
    | "tsx"
    | "jsx"
    | "json"
    | "md"
    | "markdown"
    | "toml"
    | "yaml"
    | "yml"
    | "lock"
    | "mod"
    | "pkg"
    | "rs"
    | "py"
    | "go"
    | "sh"
    | "css"
    | "scss"
    | "html"
    | "htm"
    | "txt"
    | "sql"
    | "wasm"
    | "xml"
    | "ini"
    | "cfg"
    | "conf"
    | "java"
    | "kt"
    | "rb"
    | "php"
    | "swift"
    | "cs"
    | "lua"
    | "pdf"
    | "png"
    | "jpg"
    | "jpeg"
    | "gif"
    | "svg"
    | "webp"
    | "csv"
    | "tsv"
    | "xlsx"
    | "xls"
    | "docx"
    | "doc"
    | "pptx"
    | "ppt"
    | "zip" => true
    _ => false
  }
}

///|
fn plain_text(inline : @cmark.Inline) -> String {
  let buf = StringBuilder()
  for line in inline.to_plain_text(break_on_soft=false) {
    for segment in line {
      buf.write_string(segment)
    }
  }
  buf.to_string()
}

///|
fn tights_text(tights : @cmark.Seq[@cmark.Tight]) -> String {
  let buf = StringBuilder()
  for tight in tights.iter() {
    buf.write_string(tight.to_string())
  }
  buf.to_string()
}

// Regression test for the streaming freeze: cmark can panic on some
// streaming-truncated inputs (observed: "Index out of bounds" in
// Parser::add_open_blocks while this answer streamed in). markdown_nodes
// must contain the panic and fall back to plain text, because view re-parses
// the accumulated text on every delta — one escaping panic freezes the
// transcript permanently.

///|
test "markdown survives every streaming prefix of a list-heavy answer" {
  let answer = "你好！😊 我是 SeekMoon，一个专注于 MoonBit 语言的 AI 编程助手。\n\n我可以帮你：\n\n- 🛠️ **写 MoonBit 代码**：函数、模块、测试\n- 🔍 **解释代码**：阅读和理解现有项目\n- 🐛 **修 bug**：定位并修复问题\n\n1. 第一步\n2. 第二步\n\n| 列 | 表 |\n|---|---|\n| a | b |\n"
  let buf = StringBuilder()
  for ch in answer {
    buf.write_char(ch)
    let nodes = markdown_nodes(buf.to_string())
    assert_true(nodes.length() > 0)
  }
}

///|
test "a bare list marker at end of input renders via the fallback" {
  // Minimal reproducers for the cmark panic: a list marker as the very last
  // character of the document, with nothing (not even a newline) after it.
  for text in ["-", "*", "+", "1.", "1)", "\n-", "- a\n-", "你可以：\n\n-"] {
    let nodes = markdown_nodes(text)
    assert_true(nodes.length() > 0)
  }
}
