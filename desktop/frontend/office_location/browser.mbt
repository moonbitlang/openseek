///|
let lazy_highlights : Map[String, (@js.Value, () -> Unit)] = Map([])

///|
extern "js" fn observe_children(
  node : @js.Value,
  update : () -> Unit,
) -> () -> Unit = "(node, update) => { const observer = new MutationObserver(update); observer.observe(node, {childList:true, subtree:true}); return () => observer.disconnect(); }"

///|
extern "js" fn same_value(a : @js.Value, b : @js.Value) -> Bool = "(a, b) => a === b"

///|
fn elements(node : @js.Value, selector : String) -> Array[@js.Value] {
  let list : @js.Value = node.apply_with_string("querySelectorAll", [selector])
  let length : Int32 = list.get_with_string("length")
  Array::makei(length, i => list.get_with_index(i))
}

///|
fn attribute(node : @js.Value, name : String) -> String? {
  let value : @js.Nullable[String] = node.apply_with_string("getAttribute", [
    name,
  ])
  value.to_option()
}

///|
fn host(id : String) -> @js.Value? {
  let document : @js.Value = @js.globalThis.get_with_string("document")
  let value : @js.Nullable[@js.Value] = document.apply_with_string(
    "getElementById",
    [id],
  )
  value.to_option()
}

///|
fn clear(id : String) -> Unit {
  if lazy_highlights.get(id) is Some((_, dispose)) {
    dispose()
    lazy_highlights.remove(id)
  }
  guard host(id) is Some(host) else { return }
  for node in elements(host, ".office-citation-highlight") {
    node.apply_with_string("remove", ([] : FixedArray[@js.Value]))
  }
  for node in elements(host, ".office-citation-target") {
    let classes : @js.Value = node.get_with_string("classList")
    classes.apply_with_string("remove", ["office-citation-target"])
  }
}

///|
fn normalize(text : String) -> String {
  let out = StringBuilder()
  let mut space = false
  for ch in text.trim().to_owned() {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
      space = true
    } else {
      if space {
        out.write_char(' ')
      }
      out.write_char(ch)
      space = false
    }
  }
  out.to_string()
}

///|
fn paragraph_text(nodes : Array[@js.Value]) -> String {
  let out = StringBuilder()
  let mut end : Int32? = None
  for node in nodes {
    let start = attribute(node, "data-source-start").bind(source_offset)
    if start is Some(start) && end is Some(previous) && start > previous {
      out.write_char(' ')
    }
    out.write_string(node.get_with_string("textContent"))
    end = attribute(node, "data-source-end").bind(source_offset)
  }
  normalize(out.to_string())
}

///|
fn source_offset(value : String) -> Int32? {
  if value == "0" {
    Some(0)
  } else {
    positive(value, maximum=2147483647)
  }
}

///|
fn word_nodes(host : @js.Value, target : Target) -> Array[@js.Value] {
  let groups : Map[String, Array[@js.Value]] = Map([])
  for
    node in elements(
      host, ".word-page text[data-source-selector], .word-page text[data-comment-path]",
    ) {
    let selector = if attribute(node, "data-comment-part") is Some(part) &&
      attribute(node, "data-comment-path") is Some(path) {
      // The viewer can prove a physical paragraph's text even when it cannot
      // expose an actionable logical selector. Exact heading-text navigation
      // may use that context; canonical-selector navigation must not infer it.
      "physical:\{part}:\{path}"
    } else if attribute(node, "data-source-selector") is Some(selector) {
      selector
    } else {
      continue
    }
    let group = groups.get_or_default(selector, [])
    group.push(node)
    groups[selector] = group
  }
  match target {
    WordParagraph(selector) => {
      let nodes = elements(host, ".word-page text[data-source-selector]").filter(node => {
          attribute(node, "data-source-selector") == Some(selector)
        },
      )
      if !nodes.is_empty() {
        return nodes
      }
      // The renderer may expose a stable paraId selector alongside its proven
      // reader-order path. This maps the exact ordinal, never a visual index.
      guard selector.strip_prefix("/docx/body/") is Some(path) else {
        return []
      }
      elements(host, ".word-page text[data-source-path]").filter(node => {
        attribute(node, "data-source-path") == Some(path.to_owned())
      })
    }
    WordHeading(heading) => {
      let matches = groups
        .values()
        .to_array()
        .filter(nodes => paragraph_text(nodes) == normalize(heading))
      // Repeated headings cannot be disambiguated by their text alone.
      if matches.length() == 1 {
        matches[0]
      } else {
        []
      }
    }
    _ => []
  }
}

///|
fn excel_nodes(
  host : @js.Value,
  sheet : String,
  range : String,
) -> Array[@js.Value] {
  guard range_bounds(range) is Some(((r1, c1), (r2, c2))) else { return [] }
  // The lazy viewer validates full-sheet source coordinates and mounts the
  // target before DOM lookup. Older/static viewers keep the existing path.
  let prepare : @js.Nullable[(String, Int32, Int32) -> Bool] = host.get_with_string(
    "__officeRevealExcelCell",
  )
  let lazy_target = match prepare.to_option() {
    Some(reveal) => reveal(sheet, r2, c2) && reveal(sheet, r1, c1)
    None => false
  }
  let sections = elements(host, "section[data-sheet]").filter(node => {
    attribute(node, "data-sheet") == Some(sheet)
  })
  guard sections.length() == 1 else { return [] }
  let cells = elements(sections[0], "td[data-cell]").filter_map(node => {
    guard attribute(node, "data-cell").bind(cell) is Some((row, col)) else {
      return None
    }
    let rows = attribute(node, "rowspan")
      .bind(s => positive(s, maximum=1048576))
      .unwrap_or(1)
    let cols = attribute(node, "colspan")
      .bind(s => positive(s, maximum=16384))
      .unwrap_or(1)
    Some((node, row, col, row + rows - 1, col + cols - 1))
  })
  let covers = (row, col) => {
    cells.any(c => row >= c.1 && col >= c.2 && row <= c.3 && col <= c.4)
  }
  guard covers(r1, c1) && (lazy_target || covers(r2, c2)) else { return [] }
  let nodes = cells.filter_map(c => {
    if c.1 <= r2 && c.3 >= r1 && c.2 <= c2 && c.4 >= c1 {
      Some(c.0)
    } else {
      None
    }
  })
  let tabs = elements(host, "[data-excel-sheet-tab]").filter(node => {
    attribute(node, "data-excel-sheet-tab") == Some(sheet)
  })
  guard tabs.length() == 1 else { return [] }
  if !lazy_target {
    tabs[0].apply_with_string("click", ([] : FixedArray[@js.Value]))
  }
  nodes
}

///|
/// Navigate without setting a browser selection: highlighting a citation must
/// not create a new composer annotation. All values are compared as data, never
/// interpolated into selectors. The caller fences this effect to its active tab.
pub fn reveal(id : String, target : Target) -> Bool {
  clear(id)
  guard host(id) is Some(host) else { return false }
  let nodes = match target {
    PdfPage(page) =>
      elements(host, ".page[data-page-number]").filter(node => {
        attribute(node, "data-page-number") == Some(page.to_string())
      })
    WordHeading(_) | WordParagraph(_) => word_nodes(host, target)
    ExcelRange(sheet~, range~) => excel_nodes(host, sheet, range)
  }
  guard !nodes.is_empty() else { return false }
  for node in nodes {
    let classes : @js.Value = node.get_with_string("classList")
    classes.apply_with_string("add", ["office-citation-target"])
    if target is (WordHeading(_) | WordParagraph(_)) {
      let rect : @js.Value = node.apply_with_string(
        "getBBox",
        ([] : FixedArray[@js.Value]),
      )
      let document : @js.Value = @js.globalThis.get_with_string("document")
      let highlight : @js.Value = document.apply_with_string(
        "createElementNS",
        ["http://www.w3.org/2000/svg", "rect"],
      )
      highlight.apply_with_string("setAttribute", [
        "class", "office-citation-highlight",
      ])
      for name in ["x", "y", "width", "height"] {
        let value : Double = rect.get_with_string(name)
        highlight.apply_with_string("setAttribute", [name, value.to_string()])
      }
      let parent : @js.Value = node.get_with_string("parentNode")
      parent.apply_with_string("insertBefore", [highlight, node])
    }
  }
  if target is ExcelRange(sheet~, range~) &&
    !elements(host, "section.is-active table.office-virtual-table").is_empty() {
    keep_lazy_highlight(id, host, sheet, range)
  }
  let options = @js.Object::new()
  options.set("block", if target is PdfPage(_) { "start" } else { "center" })
  options.set("inline", "center")
  // Virtual cells already occupy the correct visible window. A native scroll
  // would reinterpret their compressed canvas position and lose the target.
  if !(target is ExcelRange(..)) ||
    elements(host, "section.is-active table.office-virtual-table").is_empty() {
    nodes[0].apply_with_string("scrollIntoView", [options.to_value()])
  }
  true
}

///|
/// Recycled cells receive the same citation marker. The viewer provider's
/// identity fences this observer to the installed document snapshot.
fn keep_lazy_highlight(
  id : String,
  host : @js.Value,
  sheet : String,
  range : String,
) -> Unit {
  guard range_bounds(range) is Some(((r1, c1), (r2, c2))) else { return }
  let provider : @js.Value = host.get_with_string("__officeRevealExcelCell")
  let dispose = observe_children(host, () => {
    let current : @js.Value = host.get_with_string("__officeRevealExcelCell")
    if !same_value(provider, current) ||
      elements(host, "table.office-virtual-table").is_empty() {
      if lazy_highlights.get(id) is Some((owner, dispose)) &&
        same_value(owner, provider) {
        dispose()
        lazy_highlights.remove(id)
      }
      return
    }
    for section in elements(host, "section[data-sheet]") {
      if attribute(section, "data-sheet") != Some(sheet) {
        continue
      }
      for node in elements(section, "td[data-cell]") {
        guard attribute(node, "data-cell").bind(cell) is Some((row, col)) else {
          continue
        }
        let rows = attribute(node, "rowspan")
          .bind(s => positive(s, maximum=1048576))
          .unwrap_or(1)
        let cols = attribute(node, "colspan")
          .bind(s => positive(s, maximum=16384))
          .unwrap_or(1)
        if row <= r2 &&
          row + rows - 1 >= r1 &&
          col <= c2 &&
          col + cols - 1 >= c1 {
          let classes : @js.Value = node.get_with_string("classList")
          classes.apply_with_string("add", ["office-citation-target"])
        }
      }
    }
  })
  lazy_highlights[id] = (provider, dispose)
}
