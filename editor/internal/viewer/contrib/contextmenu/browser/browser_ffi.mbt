// Browser capabilities not exposed by the current DOM bindings.

///|
extern "js" fn append_context_menu_to_body(element : @rdom.Element) -> Bool =
  #| (element) => {
  #|   const body = element?.ownerDocument?.body ?? globalThis.document?.body;
  #|   if (!body) return false;
  #|   body.appendChild(element);
  #|   return true;
  #| }

///|
extern "js" fn context_menu_active_element(
  element : @rdom.Element,
) -> @rdom.Element =
  #| (element) => element?.ownerDocument?.activeElement ?? element

///|
extern "js" fn context_menu_has_active_element(element : @rdom.Element) -> Bool =
  #| (element) => Boolean(element?.ownerDocument?.activeElement)

///|
extern "js" fn context_menu_event_inside(
  event : @rdom.Event,
  element : @rdom.Element,
) -> Bool =
  #| (event, element) => {
  #|   const target = event?.target;
  #|   return Boolean(target && element?.contains?.(target));
  #| }

///|
extern "js" fn context_menu_viewport_width(element : @rdom.Element) -> Double =
  #| (element) => {
  #|   const doc = element?.ownerDocument;
  #|   const win = doc?.defaultView ?? globalThis.window;
  #|   return win?.visualViewport?.width
  #|     ?? win?.innerWidth
  #|     ?? doc?.documentElement?.clientWidth
  #|     ?? doc?.body?.clientWidth
  #|     ?? 0;
  #| }

///|
extern "js" fn context_menu_viewport_height(element : @rdom.Element) -> Double =
  #| (element) => {
  #|   const doc = element?.ownerDocument;
  #|   const win = doc?.defaultView ?? globalThis.window;
  #|   return win?.visualViewport?.height
  #|     ?? win?.innerHeight
  #|     ?? doc?.documentElement?.clientHeight
  #|     ?? doc?.body?.clientHeight
  #|     ?? 0;
  #| }

///|
extern "js" fn context_menu_add_window_blur_listener(
  element : @rdom.Element,
  listener : () -> Unit,
) -> Unit =
  #| (element, listener) => {
  #|   (element?.ownerDocument?.defaultView ?? globalThis.window)
  #|     ?.addEventListener?.('blur', listener);
  #| }

///|
extern "js" fn context_menu_remove_window_blur_listener(
  element : @rdom.Element,
  listener : () -> Unit,
) -> Unit =
  #| (element, listener) => {
  #|   (element?.ownerDocument?.defaultView ?? globalThis.window)
  #|     ?.removeEventListener?.('blur', listener);
  #| }
