// Browser geometry primitives, including owner-window fallbacks.

///|
/// Monaco `_getMaxWidth`: use the widget node's owner document/window, never
/// the ambient global window. JavaScript `||` intentionally treats a zero
/// `innerWidth` as unavailable before the two offset-width fallbacks.
extern "js" fn owner_document_max_width(
  element : @rdom.Element,
  allow_editor_overflow : Bool,
  content_width : Double,
) -> Double =
  #| (element, allowOverflow, contentWidth) => {
  #|   if (!allowOverflow) return contentWidth;
  #|   const doc = element.ownerDocument;
  #|   const win = doc?.defaultView;
  #|   return (win?.innerWidth || doc?.documentElement?.offsetWidth || doc?.body?.offsetWidth || 0);
  #| }

///|
/// Owner-window page scroll with the source's exact `defaultView ?? 0`
/// fallback for detached documents.
extern "js" fn owner_window_scroll_x(element : @rdom.Element) -> Double =
  #| (element) => element?.ownerDocument?.defaultView?.scrollX ?? 0

///|
extern "js" fn owner_window_scroll_y(element : @rdom.Element) -> Double =
  #| (element) => element?.ownerDocument?.defaultView?.scrollY ?? 0

///|
extern "js" fn dom_helper_window_scroll_x(element : @rdom.Element) -> Double =
  #| (element) => (element?.ownerDocument?.defaultView ?? globalThis.window)?.scrollX ?? 0

///|
extern "js" fn dom_helper_window_scroll_y(element : @rdom.Element) -> Double =
  #| (element) => (element?.ownerDocument?.defaultView ?? globalThis.window)?.scrollY ?? 0

///|
extern "js" fn unavailable_client_area() -> Double = "() => { throw new Error('Unable to figure out browser width and height'); }"
