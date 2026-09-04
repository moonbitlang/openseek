// Missing Rabbita DOM bindings only. Menu policy and listener lifetimes live
// in MoonBit; these bindings do not own application state.

///|
#external
priv type BrowserSelection

///|
#external
priv type BrowserRange

///|
#external
priv type TextControl

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
extern "js" fn TextControl::from_element(
  element : @dom.Element,
) -> @js.Nullable[TextControl] =
  #| element => element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement ? element : null

///|
extern "js" fn TextControl::element(self : TextControl) -> @dom.HTMLElement =
  #| input => input

///|
extern "js" fn TextControl::kind(self : TextControl) -> String =
  #| input => input.type

///|
extern "js" fn TextControl::value(self : TextControl) -> String =
  #| input => input.value

///|
extern "js" fn TextControl::disabled(self : TextControl) -> Bool =
  #| input => input.disabled

///|
extern "js" fn TextControl::read_only(self : TextControl) -> Bool =
  #| input => input.readOnly

///|
extern "js" fn TextControl::selection_start(
  self : TextControl,
) -> @js.Nullable[Int] =
  #| input => input.selectionStart

///|
extern "js" fn TextControl::selection_end(
  self : TextControl,
) -> @js.Nullable[Int] =
  #| input => input.selectionEnd

///|
extern "js" fn TextControl::selection_direction(
  self : TextControl,
) -> @js.Nullable[String] =
  #| input => input.selectionDirection

///|
extern "js" fn TextControl::set_selection(
  self : TextControl,
  start : Int,
  end : Int,
  direction : @js.Nullable[String],
) -> Unit =
  #| (input, start, end, direction) => input.setSelectionRange(start, end, direction)

///|
extern "js" fn focus_without_scroll(element : @dom.HTMLElement) -> Unit =
  #| element => element.focus({ preventScroll: true })

///|
extern "js" fn blur_event(
  related : @js.Nullable[@dom.EventTarget],
) -> @dom.Event =
  #| relatedTarget => new FocusEvent("blur", { relatedTarget })

///|
// Deprecated browser editing commands remain necessary for native undo
// history. Call through Error_::wrap when a command can throw.
extern "js" fn browser_edit_command(
  command : String,
  text : @js.Nullable[String],
) -> Bool =
  #| (command, text) => document.execCommand(command, false, text)

///|
extern "js" fn anchor_href(anchor : @dom.Element) -> String =
  #| anchor => anchor.href

///|
extern "js" fn anchor_protocol(anchor : @dom.Element) -> String =
  #| anchor => anchor.protocol

///|
extern "js" fn decode_uri_component(text : String) -> String =
  #| text => decodeURIComponent(text)
