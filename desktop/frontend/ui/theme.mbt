///|
fn ui_attrs(attrs : @html.Attrs?) -> @html.Attrs {
  if attrs is Some(attrs) {
    attrs.copy()
  } else {
    @html.Attrs::build()
  }
}
