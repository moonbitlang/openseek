///|
/// A DOM-only annotation is unsupported only when it paints inside this crop.
/// Transparent link hit areas and hidden controls must not block screenshots.
fn annotation_visible(element : @js.Value, crop : @selection.Rect) -> Bool {
  if browser_bounds(element).intersection(crop) is None ||
    (browser_style(element).get_with_string("visibility") : String) != "visible" {
    return false
  }
  let mut ancestor = Some(element)
  while ancestor is Some(node) {
    if browser_number(browser_style(node).get_with_string("opacity")) == 0 {
      return false
    }
    let parent : @js.Nullable[@js.Value] = node.get_with_string("parentElement")
    ancestor = parent.to_option()
  }
  true
}

///|
fn visible_annotation_color(color : String) -> Bool {
  // Computed legacy rgba and modern color() serialize zero alpha this way.
  color != "transparent" &&
  !(color.has_prefix("rgba(") && color.has_suffix(", 0)")) &&
  !color.has_suffix(" / 0)")
}

///|
fn annotation_has_css_paint(style : @js.Value) -> Bool {
  if (style.get_with_string("backgroundImage") : String) != "none" ||
    visible_annotation_color(style.get_with_string("backgroundColor")) {
    return true
  }
  for side in ["Top", "Right", "Bottom", "Left"] {
    let border_style : String = style.get_with_string("border\{side}Style")
    let width : Double = @js.globalThis.apply_with_string("parseFloat", [
      (style.get_with_string("border\{side}Width") : String),
    ])
    if border_style != "none" &&
      border_style != "hidden" &&
      width > 0 &&
      visible_annotation_color(style.get_with_string("border\{side}Color")) {
      return true
    }
  }
  false
}

///|
fn has_unsupported_annotation(page : @js.Value, crop : @selection.Rect) -> Bool {
  // PDF.js line/shape/ink SVGs are transparent popup hit areas. Their visible
  // markup is painted in the page/annotation bitmap, including synthesized
  // appearances when /AP is absent. Rejecting every SVG would block valid crops.
  // The current viewer disables editable forms/XFA. Keep the boundary explicit
  // for native controls as well as the read-only HTML fallbacks PDF.js uses.
  for
    element in browser_elements(
      page, ".annotationLayer input, .annotationLayer select, .annotationLayer textarea, .annotationLayer button, .textWidgetAnnotation > div:not([hidden]), .annotationLayer .popup, .annotationLayer .mediaAnnotation, .xfaLayer",
    ) {
    if annotation_visible(element, crop) {
      return true
    }
  }
  // PDF.js may paint a widget or link border/background using CSS, even when
  // forms are disabled and an empty annotation canvas is present. A bitmap
  // child therefore does not establish that the entire annotation is captured.
  for element in browser_elements(page, ".annotationLayer section") {
    if annotation_visible(element, crop) &&
      annotation_has_css_paint(browser_style(element)) {
      return true
    }
  }
  false
}
