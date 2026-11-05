///|
const UiFontSans : String = "font-family:var(--font-family-sans)"

///|
const UiBoxSizing : String = "box-sizing:border-box"

///|
const UiTextRendering : String = "-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility"

///|
const UiTransition : String = "transition:color 150ms ease,background-color 150ms ease,border-color 150ms ease,box-shadow 150ms ease,opacity 150ms ease,transform 150ms ease"

///|
const UiDisabled : String = "cursor:not-allowed;pointer-events:none;opacity:0.5"

///|
fn ui_disabled_style(disabled : Bool) -> String {
  if disabled {
    UiDisabled
  } else {
    ""
  }
}

///|
fn ui_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn ui_attrs(attrs : @html.Attrs?) -> @html.Attrs {
  if attrs is Some(attrs) {
    attrs.copy()
  } else {
    @html.Attrs::build()
  }
}

///|
fn ui_styles(parts : Array[String], extra : Array[String]) -> Array[String] {
  let styles : Array[String] = []
  for part in parts {
    if part != "" {
      styles.push(part)
    }
  }
  for part in extra {
    if part != "" {
      styles.push(part)
    }
  }
  styles
}
