// Browser capabilities not exposed by the current DOM bindings.

///|
extern "js" fn replace_hover_contents(
  contents : @rdom.Element,
  fragment : @rdom.DocumentFragment,
) -> Unit =
  #| (contents, fragment) => {
  #|   contents.style.paddingBottom = '';
  #|   contents.textContent = '';
  #|   contents.appendChild(fragment);
  #| }

///|
extern "js" fn hover_mousedown_is_interactive(event : @rdom.Event) -> Bool =
  #| (event) => {
  #|   const target = event?.target;
  #|   return Boolean(target?.closest?.("button, a, input, textarea, select, [role='button'], .hover-copy-button"));
  #| }

///|
/// Monaco `dom.getClientArea(editorDomNode.ownerDocument.body).height`
/// (`resizableContentWidget.ts:81`).
extern "js" fn body_client_height(node : @rdom.Element) -> Double =
  #| (node) => node.ownerDocument.body.clientHeight
