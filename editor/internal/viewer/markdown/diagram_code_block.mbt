///|
/// Wraps package-owned exact lowercase diagram fences before any caller
/// override. `d2`/`diago` fences are Diago diagrams and `uml`/`plantuml`
/// fences are UML diagrams. The wrapper holds the escaped source as its
/// fallback; the browser renderer replaces it with SVG once a diagram renderer
/// compiles the source.
///
/// ```d2
/// direction: right
///
/// fence: fenced block
/// language: supported diagram fence?
/// wrapper: diagram wrapper with source fallback
/// code: ordinary code HTML
///
/// fence -> language
/// language -> wrapper: yes
/// language -> code: no
/// ```
fn render_diagram_code_block(code_block : MarkdownCodeBlock) -> String? {
  guard code_block.language_id is Some(language) &&
    @diagrams.DiagramKind::from_fence(language) is Some(kind) else {
    return None
  }
  let source_attribute = match code_block.node_id {
    Some(_) => markdown_source_attributes(code_block.block_source_range)
    None => ""
  }
  Some(
    (
      $|<div class="moonbit-viewer-markdown-diagram" data-diagram-language="\{kind.name()}" data-diagram-state="fallback"\{source_attribute}><pre><code class="language-\{language}">\{@common.escape_html(code_block.code)}</code></pre></div>
      $|
    ),
  )
}
