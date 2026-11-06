///|
/// Renders diagrams with the module built from
/// `moonbitlang/editor/viewer/diagrams/module`, imported from `url` the first
/// time a diagram is rendered. A relative URL resolves against the document
/// base. A failed import or render passes `None`.
pub fn use_module(url : String) -> Unit {
  renderer.val = Some((kind, source, on_result) => {
    render_with_module(url, kind.name(), source, svg => on_result(Some(svg)), () => {
      on_result(None)
    })
  })
}

///|
extern "js" fn render_with_module(
  url : String,
  kind : String,
  source : String,
  on_svg : (String) -> Unit,
  on_failure : () -> Unit,
) -> Unit =
  #| (url, kind, source, onSvg, onFailure) => {
  #|   import(new URL(url, document.baseURI).href).then(
  #|     (module) => {
  #|       let svg;
  #|       try {
  #|         svg = module.render_diagram(kind, source);
  #|       } catch {
  #|         onFailure();
  #|         return;
  #|       }
  #|       if (typeof svg === "string") onSvg(svg);
  #|       else onFailure();
  #|     },
  #|     () => onFailure(),
  #|   );
  #| }
