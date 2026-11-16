///|
/// Renders diagrams with the module built from
/// `moonbitlang/editor/viewer/diagrams/module`, imported from `url` the first
/// time a diagram is rendered. A relative URL resolves against the document
/// base. A failed import or render passes `None`.
pub fn use_module(url : String) -> Unit {
  let load = diagram_module(url)
  renderer.val = Some((kind, source, wanted, on_result) => {
    render_with_module(
      load,
      kind.name(),
      source,
      wanted,
      svg => on_result(Some(svg)),
      () => on_result(None),
    )
  })
}

///|
/// Imports the module on first use; every later request settles from the
/// same promise.
#external
priv type DiagramModule

///|
extern "js" fn diagram_module(url : String) -> DiagramModule =
  #| (url) => {
  #|   let module;
  #|   return () => (module ??= import(new URL(url, document.baseURI).href));
  #| }

///|
extern "js" fn render_with_module(
  load : DiagramModule,
  kind : String,
  source : String,
  wanted : () -> Bool,
  on_svg : (String) -> Unit,
  on_failure : () -> Unit,
) -> Unit =
  #| (load, kind, source, wanted, onSvg, onFailure) => {
  #|   load().then(
  #|     (module) => {
  #|       if (!wanted()) return;
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
