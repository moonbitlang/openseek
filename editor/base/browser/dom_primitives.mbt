///|
/// Reads the element's inner layout width, including padding but excluding
/// borders and scrollbars. This is the `clientWidth` used by Monaco's
/// `ElementSizeObserver`; unlike a bounding rect it ignores CSS transforms.
pub extern "js" fn element_client_width(element : @rdom.Element) -> Double =
  #| (element) => element?.clientWidth ?? 0

///|
/// Reads the element's inner layout height with `clientHeight` semantics.
pub extern "js" fn element_client_height(element : @rdom.Element) -> Double =
  #| (element) => element?.clientHeight ?? 0

///|
/// Reads the element's unscaled layout width. This intentionally remains
/// distinct from `get_bounding_client_rect`, whose dimensions include CSS
/// transforms.
pub extern "js" fn element_offset_width(element : @rdom.Element) -> Double =
  #| (element) => element?.offsetWidth ?? 0

///|
/// Reads the element's unscaled layout height.
pub extern "js" fn element_offset_height(element : @rdom.Element) -> Double =
  #| (element) => element?.offsetHeight ?? 0

///|
/// Whether the element currently participates in an attached document tree.
pub extern "js" fn element_is_connected(element : @rdom.Element) -> Bool =
  #| (element) => element?.isConnected === true

///|
/// Writes one inline CSS property without replacing sibling properties.
pub extern "js" fn set_style_property(
  element : @rdom.Element,
  name : String,
  value : String,
) -> Unit =
  #| (element, name, value) => { element.style.setProperty(name, value); }

///|
/// Reads one inline CSS property without requiring an `HTMLElement` downcast.
/// This is useful for SVG-capable containers and narrow DOM test doubles.
pub extern "js" fn element_style_value(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => element?.style?.getPropertyValue?.(name) ?? ''

///|
/// Reads the priority associated with one inline CSS property.
pub extern "js" fn element_style_priority(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => element?.style?.getPropertyPriority?.(name) ?? ''

///|
/// Removes one inline CSS property while preserving sibling declarations.
pub extern "js" fn remove_style_property(
  element : @rdom.Element,
  name : String,
) -> Unit = "(element, name) => { element?.style?.removeProperty?.(name); }"

///|
/// Writes one inline CSS property together with its explicit priority.
pub extern "js" fn set_style_property_with_priority(
  element : @rdom.Element,
  name : String,
  value : String,
  priority : String,
) -> Unit =
  #| (element, name, value, priority) => {
  #|   element?.style?.setProperty?.(name, value, priority);
  #| }

///|
/// Removes an element if attached. `HTMLElement.remove()` is idempotent; the
/// parent-node fallback preserves that behavior for narrow test DOMs.
pub extern "js" fn remove_element(element : @rdom.Element) -> Unit =
  #| (element) => {
  #|   if (typeof element?.remove === "function") element.remove();
  #|   else element?.parentNode?.removeChild(element);
  #| }

///|
/// Focuses an element without allowing the browser to scroll it into view.
pub extern "js" fn focus_prevent_scroll(element : @rdom.Element) -> Unit =
  #| (element) => element?.focus?.({ preventScroll: true })

///|
/// Whether `child` is the container itself or one of its descendants.
pub extern "js" fn element_contains(
  container : @rdom.Element,
  child : @rdom.Element,
) -> Bool =
  #| (container, child) => Boolean(container?.contains?.(child))

///|
/// Whether the element's owner document currently focuses the element.
pub extern "js" fn element_has_focus(element : @rdom.Element) -> Bool =
  #| (element) => Boolean(element?.ownerDocument?.activeElement === element)

///|
/// Whether the active element from this element's owner document is contained
/// by the element. Using the owner document preserves iframe/document seams.
pub extern "js" fn element_contains_active_element(
  element : @rdom.Element,
) -> Bool =
  #| (element) => {
  #|   const active = element?.ownerDocument?.activeElement;
  #|   return Boolean(active && element.contains(active));
  #| }

///|
/// Whether this DOM event originated exactly at `element`. This is stricter
/// than listener placement: a listener on `element` also receives events that
/// bubble from descendants.
pub extern "js" fn event_target_is(
  event : @rdom.Event,
  element : @rdom.Element,
) -> Bool =
  #| (event, element) => event?.target === element

///|
pub fn event_target_has_matching_ancestor(
  event : @rdom.Event,
  boundary : @rdom.Element,
  selector : String,
) -> Bool {
  node_has_matching_ancestor(
    @js.Value::cast_from(event).get_with_string("target"),
    boundary,
    selector,
  )
}

///|
pub fn native_selection_has_endpoint_in_matching_ancestor(
  boundary : @rdom.Element,
  selector : String,
) -> Bool {
  let selection = owner_native_selection(boundary)
  guard selection.to_option() is Some(selection) else { return false }
  let collapsed : Bool = selection.get_with_string("isCollapsed")
  if collapsed {
    return false
  }
  node_has_matching_ancestor(
    selection.get_with_string("anchorNode"),
    boundary,
    selector,
  ) ||
  node_has_matching_ancestor(
    selection.get_with_string("focusNode"),
    boundary,
    selector,
  )
}

///|
extern "js" fn owner_native_selection(
  boundary : @rdom.Element,
) -> @js.Nullable[@js.Value] = "boundary => boundary?.ownerDocument?.getSelection?.()"

///|
extern "js" fn node_has_matching_ancestor(
  node : @js.Value,
  boundary : @rdom.Element,
  selector : String,
) -> Bool =
  #| (node, boundary, selector) => {
  #|   const element = node?.nodeType === 1 ? node : node?.parentElement;
  #|   try {
  #|     const match = element?.closest?.(selector);
  #|     return Boolean(match && boundary?.contains?.(match));
  #|   } catch { return false; }
  #| }

///|
#external
priv type NativeResizeObserver

///|
extern "js" fn native_resize_observer_disconnect(
  observer : NativeResizeObserver,
) -> Unit = "observer => observer.disconnect()"

///|
extern "js" fn resize_observer_class(
  target : @rdom.Element,
) -> @js.Nullable[@js.Value] =
  #| target => {
  #|   const ctor = target?.ownerDocument?.defaultView?.ResizeObserver ?? globalThis.ResizeObserver;
  #|   return typeof ctor === 'function' ? ctor : null;
  #| }

///|
#external
priv type BrowserStorage

///|
extern "js" fn browser_local_storage() -> @js.Nullable[BrowserStorage] = "() => globalThis.localStorage ?? null"

///|
extern "js" fn BrowserStorage::get_item(
  self : BrowserStorage,
  key : String,
) -> @js.Nullable[String] = "(storage, key) => storage.getItem(key)"

///|
extern "js" fn BrowserStorage::set_item(
  self : BrowserStorage,
  key : String,
  value : String,
) -> Unit = "(storage, key, value) => storage.setItem(key, value)"

///|
extern "js" fn BrowserStorage::remove_item(
  self : BrowserStorage,
  key : String,
) -> Unit = "(storage, key) => storage.removeItem(key)"

///|
#external
priv type BrowserUrl

///|
extern "js" fn browser_url(
  raw : String,
  base : @js.Optional[String],
) -> BrowserUrl = "(raw, base) => new URL(raw, base)"

///|
extern "js" fn BrowserUrl::href(self : BrowserUrl) -> String = "url => url.href"

///|
extern "js" fn BrowserUrl::protocol(self : BrowserUrl) -> String = "url => url.protocol"
