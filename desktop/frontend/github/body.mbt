///|
/// Mount only GitHub's rendered bodyHTML, never authored Markdown or local
/// drafts. Rabbita owns the wrapper; its opaque HTML children retain their DOM
/// state until GitHub returns different HTML.
#warnings("-alert_xss_vulnerable")
pub fn body_view(
  body_html : String,
  source_url : String,
  class? : String,
) -> @html.Html {
  let base_class = "github-html-body msg-content markdown"
  @html.div(
    class=match class {
      Some(extra) => base_class + " " + extra
      None => base_class
    },
    attrs=@html.Attrs::build().inner_html(
      body_html_with_absolute_links(body_html, source_url),
    ),
    ([] : Array[@html.Html]),
  )
}

///|
/// Relative anchors must keep their GitHub base for every browser action,
/// including modified clicks, copying a link and the context menu. This only
/// resolves hrefs; GitHub owns the markup, sanitization and media URLs.
extern "js" fn body_html_with_absolute_links(
  body_html : String,
  source_url : String,
) -> String =
  #| (html, sourceURL) => {
  #|   const template = document.createElement("template");
  #|   template.innerHTML = html;
  #|   let changed = false;
  #|   for (const anchor of template.content.querySelectorAll("a[href]")) {
  #|     const href = anchor.getAttribute("href");
  #|     if (/^[a-z][a-z0-9+.-]*:/i.test(href.trim())) continue;
  #|     try {
  #|       anchor.setAttribute("href", new URL(href, sourceURL).href);
  #|       changed = true;
  #|     } catch (_) {
  #|       // GitHub supplied this href; leave malformed destinations as-is.
  #|     }
  #|   }
  #|   return changed ? template.innerHTML : html;
  #| }
