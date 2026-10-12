///|
/// Text content for the first element matching `selector`.
pub fn query_text(selector : String) -> String? {
  if query_count(selector) == 0 {
    None
  } else {
    Some(query_text_present(selector))
  }
}

///|
extern "js" fn query_text_present(selector : String) -> String =
  #| (selector) => document.querySelector(selector).textContent ?? ""

///|
/// Number of elements matching `selector`.
pub extern "js" fn query_count(selector : String) -> Int32 =
  #| (selector) => document.querySelectorAll(selector).length

///|
/// Attribute value for the first element matching `selector`.
pub fn query_attribute(selector : String, name : String) -> String? {
  if query_has_attribute(selector, name) {
    Some(query_attribute_present(selector, name))
  } else {
    None
  }
}

///|
extern "js" fn query_has_attribute(selector : String, name : String) -> Bool =
  #| (selector, name) => document.querySelector(selector)?.hasAttribute(name) ?? false

///|
extern "js" fn query_attribute_present(
  selector : String,
  name : String,
) -> String =
  #| (selector, name) => document.querySelector(selector).getAttribute(name)

///|
/// Browser timer helper for MoonBit-authored test code.
pub extern "js" fn set_timeout(callback : () -> Unit, ms : Int32) -> Unit =
  #| (callback, ms) => {
  #|   globalThis.setTimeout(callback, Number(ms) || 0);
  #| }

///|
/// Monotonic browser timestamp in milliseconds.
pub extern "js" fn now_ms() -> Double =
  #| () => globalThis.performance?.now() ?? Date.now()
