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
extern "js" fn anchor_href(anchor : @dom.Element) -> String =
  #| anchor => anchor.href

///|
extern "js" fn anchor_protocol(anchor : @dom.Element) -> String =
  #| anchor => anchor.protocol
