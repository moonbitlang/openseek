// Missing Rabbita DOM bindings only. Menu policy and listener lifetimes live
// in MoonBit; these bindings do not own application state.

///|
#external
priv type BrowserSelection

///|
#external
priv type BrowserRange

///|
extern "js" fn browser_selection() -> @js.Nullable[BrowserSelection] =
  #| () => document.getSelection()

///|
extern "js" fn BrowserSelection::collapsed(self : BrowserSelection) -> Bool =
  #| selection => selection.isCollapsed

///|
extern "js" fn BrowserSelection::count(self : BrowserSelection) -> Int =
  #| selection => selection.rangeCount

///|
extern "js" fn BrowserSelection::text(self : BrowserSelection) -> String =
  #| selection => selection.toString()

///|
extern "js" fn BrowserSelection::range(
  self : BrowserSelection,
  index : Int,
) -> BrowserRange =
  #| (selection, index) => selection.getRangeAt(index)

///|
extern "js" fn BrowserRange::intersects(
  self : BrowserRange,
  element : @dom.Element,
) -> Bool =
  #| (range, element) => range.intersectsNode(element)

///|
extern "js" fn BrowserRange::rects(
  self : BrowserRange,
) -> FixedArray[@dom.DOMRect] =
  #| range => Array.from(range.getClientRects())

///|
extern "js" fn BrowserRange::bounds(self : BrowserRange) -> @dom.DOMRect =
  #| range => range.getBoundingClientRect()

///|
/// The element that contains the whole range.
extern "js" fn BrowserRange::container(
  self : BrowserRange,
) -> @js.Nullable[@dom.Element] =
  #| range => {
  #|   const node = range.commonAncestorContainer
  #|   return node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
  #| }

///|
/// Paint the current selection's range as the named CSS custom highlight, so
/// it stays visible after the native selection moves elsewhere.
extern "js" fn pin_selection_highlight(name : String) -> Unit =
  #| name => {
  #|   const selection = document.getSelection()
  #|   if (!globalThis.Highlight || !selection || selection.rangeCount === 0) {
  #|     return
  #|   }
  #|   CSS.highlights.set(name, new Highlight(selection.getRangeAt(0).cloneRange()))
  #| }

///|
extern "js" fn clear_selection_highlight(name : String) -> Unit =
  #| name => {
  #|   if (globalThis.Highlight) CSS.highlights.delete(name)
  #| }

///|
extern "js" fn viewport_width() -> Double =
  #| () => window.innerWidth

///|
extern "js" fn viewport_height() -> Double =
  #| () => window.innerHeight

///|
extern "js" fn anchor_href(anchor : @dom.Element) -> String =
  #| anchor => anchor.href

///|
extern "js" fn anchor_protocol(anchor : @dom.Element) -> String =
  #| anchor => anchor.protocol
