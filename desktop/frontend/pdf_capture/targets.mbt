///|
fn read_structure(value : @js.Value) -> @selection.Structure {
  let kind : @js.Optional[String] = value.get_with_string("type")
  let role : @js.Optional[String] = value.get_with_string("role")
  let id : @js.Optional[String] = value.get_with_string("id")
  let children : @js.Optional[FixedArray[@js.Value]] = value.get_with_string(
    "children",
  )
  {
    role: role.to_option(),
    content_id: if kind.to_option() == Some("content") {
      id.to_option()
    } else {
      None
    },
    children: children
    .to_option()
    .map(xs => xs.iter().map(read_structure).collect())
    .unwrap_or([]),
  }
}

///|
fn index_page(
  values : FixedArray[@js.Value],
  tree : @js.Nullable[@js.Value],
  page : @selection.Rect,
  rotation : Double,
) -> Array[@selection.Target] {
  let entries : Array[@selection.TextRun] = []
  for value in values {
    let element : @js.Value = value.get_with_string("div")
    if !(element.get_with_string("isConnected") : Bool) {
      continue
    }
    let item : @js.Value = value.get_with_string("item")
    let transform : FixedArray[Double] = item.get_with_string("transform")
    let marked : @js.Nullable[String] = value.get_with_string("markedId")
    entries.push({
      bounds: browser_bounds(element).translated({ x: -page.x, y: -page.y, }),
      index: value.get_with_string("index"),
      text: item.get_with_string("str"),
      font: item.get_with_string("fontName"),
      marked_id: marked.to_option(),
      has_eol: item.get_with_string("hasEOL"),
      vertical: @selection.vertical_text(transform[0], transform[1], rotation),
    })
  }
  @selection.targets(entries, tree.to_option().map(read_structure), page)
}
