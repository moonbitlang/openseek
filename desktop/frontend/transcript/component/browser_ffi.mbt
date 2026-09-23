// Browser bindings not yet exposed by Rabbita. Keep foreign definitions
// together, separate from application state and interaction policy.

///|
extern "js" fn image_entry_intersects(
  entry : @dom.IntersectionObserverEntry,
) -> Bool = "entry => entry.isIntersecting"

///|
extern "js" fn image_entry_target(
  entry : @dom.IntersectionObserverEntry,
) -> @dom.Element = "entry => entry.target"

///|
extern "js" fn image_class_toggle(
  image : @dom.Element,
  name : String,
  enabled : Bool,
) -> Unit = "(image, name, enabled) => image.classList.toggle(name, enabled)"
