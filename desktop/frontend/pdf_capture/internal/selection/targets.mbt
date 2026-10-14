///|
/// A rendered PDF text run. Bounds are page-relative CSS pixels; index preserves
/// PDF content order even when visual sorting is needed for untagged documents.
pub(all) struct TextRun {
  bounds : Rect
  index : Int32
  text : String
  font : String
  marked_id : String?
  has_eol : Bool
  vertical : Bool
} derive(Eq, Debug)

///|
pub(all) struct Structure {
  role : String?
  content_id : String?
  children : Array[Structure]
} derive(Eq, Debug)

///|
pub(all) struct Target {
  bounds : Rect
  text : String
} derive(Eq, Debug)

///|
pub fn vertical_text(a : Double, b : Double, rotation : Double) -> Bool {
  let angle = @math.atan2(b, a) + rotation * @math.PI / 180
  @math.sin(angle).abs() > 0.5.sqrt()
}

///|
// Match ECMAScript trim/\s, including BOM but excluding NEL. This preserves the
// text that the previous browser implementation attached to Office selections.
const TEXT_SPACE : String = "\u0009\u000a\u000b\u000c\u000d \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"

///|
fn text_for(members : Array[TextRun]) -> String {
  let ordered = members.copy()
  ordered.sort_by_key(e => e.index)
  let result = StringBuilder()
  let mut previous : TextRun? = None
  for entry in ordered {
    if previous is Some(prev) &&
      !prev.has_eol &&
      prev.text.trim_end(chars=TEXT_SPACE).length() == prev.text.length() &&
      entry.text.trim_start(chars=TEXT_SPACE).length() == entry.text.length() {
      let b = entry.bounds
      let p = prev.bounds
      let size = if entry.vertical { b.width } else { b.height }
      let cross = if entry.vertical {
        (b.x - p.x).abs()
      } else {
        (b.y - p.y).abs()
      }
      let gap = if entry.vertical {
        Double::max(0, Double::max(b.y - p.y - p.height, p.y - b.y - b.height))
      } else {
        Double::max(0, Double::max(b.x - p.x - p.width, p.x - b.x - b.width))
      }
      if cross > size / 2 {
        result.write_string("\n")
      } else if gap > size * 0.15 {
        result.write_string(" ")
      }
    }
    result.write_string(entry.text)
    if entry.has_eol {
      result.write_string("\n")
    }
    previous = Some(entry)
  }
  result.to_string().trim(chars=TEXT_SPACE).to_owned()
}

///|
fn assign_structure(
  node : Structure,
  entries : Array[TextRun],
  assigned : Map[Int32, Bool],
  groups : Array[Array[TextRun]],
) -> Map[String, Bool] {
  let ids : Map[String, Bool] = Map([])
  if node.content_id is Some(id) {
    ids[id] = true
  }
  for child in node.children {
    for id, _ in assign_structure(child, entries, assigned, groups) {
      ids[id] = true
    }
  }
  if node.role
    is Some(
      "H"
      | "H1"
      | "H2"
      | "H3"
      | "H4"
      | "H5"
      | "H6"
      | "P"
      | "LI"
      | "Caption"
      | "TD"
      | "TH"
      | "BlockQuote"
    ) {
    let members = entries.filter(e => {
      e.marked_id is Some(id) && ids.contains(id) && !assigned.contains(e.index)
    })
    if !members.is_empty() {
      groups.push(members)
      for e in members {
        assigned[e.index] = true
      }
    }
  }
  ids
}

///|
fn same_line(entry : TextRun, previous : TextRun) -> Bool {
  let b = entry.bounds
  let p = previous.bounds
  let size = if entry.vertical { b.width } else { b.height }
  let last_size = if previous.vertical { p.width } else { p.height }
  let cross = if entry.vertical {
    b.x + b.width / 2
  } else {
    b.y + b.height / 2
  }
  let last_cross = if previous.vertical {
    p.x + p.width / 2
  } else {
    p.y + p.height / 2
  }
  let along = if entry.vertical { b.y } else { b.x }
  let end = if previous.vertical { p.y + p.height } else { p.x + p.width }
  entry.vertical == previous.vertical &&
  entry.font == previous.font &&
  size / last_size >= 0.8 &&
  size / last_size <= 1.25 &&
  (cross - last_cross).abs() <= size * 0.25 &&
  along - end >= -size * 0.25 &&
  along - end <= size * 1.5
}

///|
/// Prefer the smallest tagged block; otherwise join nearby runs on one visual
/// line with matching font/size. Never infer whole paragraphs across columns.
pub fn targets(
  entries : Array[TextRun],
  tree : Structure?,
  page : Rect,
) -> Array[Target] {
  let entries = entries.filter(e => {
    !e.text.trim(chars=TEXT_SPACE).is_empty() &&
    e.bounds.width > 0 &&
    e.bounds.height > 0
  })
  let groups : Array[Array[TextRun]] = []
  let assigned : Map[Int32, Bool] = Map([])
  if tree is Some(node) {
    ignore(assign_structure(node, entries, assigned, groups))
  }
  let remaining = entries.filter(e => !assigned.contains(e.index))
  remaining.sort_by((a, b) => {
    let orientation = a.vertical.compare(b.vertical)
    let cross = if a.vertical {
      a.bounds.x.compare(b.bounds.x)
    } else {
      a.bounds.y.compare(b.bounds.y)
    }
    let along = if a.vertical {
      a.bounds.y.compare(b.bounds.y)
    } else {
      a.bounds.x.compare(b.bounds.x)
    }
    if orientation != 0 {
      orientation
    } else if cross != 0 {
      cross
    } else if along != 0 {
      along
    } else {
      a.index.compare(b.index)
    }
  })
  let lines : Array[Array[TextRun]] = []
  for entry in remaining {
    if lines
      .iter()
      .find_first(line => line.last() is Some(last) && same_line(entry, last))
      is Some(line) {
      line.push(entry)
    } else {
      lines.push([entry])
    }
  }
  groups.append(lines)
  let result : Array[Target] = []
  for members in groups {
    if members is [first, .. rest] {
      let mut x = first.bounds.x
      let mut y = first.bounds.y
      let mut right = x + first.bounds.width
      let mut bottom = y + first.bounds.height
      for entry in rest {
        x = Double::min(x, entry.bounds.x)
        y = Double::min(y, entry.bounds.y)
        right = Double::max(right, entry.bounds.x + entry.bounds.width)
        bottom = Double::max(bottom, entry.bounds.y + entry.bounds.height)
      }
      x = Double::max(0, x - 2)
      y = Double::max(0, y - 2)
      result.push({
        bounds: {
          x,
          y,
          width: Double::min(page.width, right + 2) - x,
          height: Double::min(page.height, bottom + 2) - y,
        },
        text: text_for(members),
      })
    }
  }
  result
}

///|
pub fn hit_target(targets : Array[Target], point : Point) -> Target? {
  let mut best : Target? = None
  for target in targets {
    if target.bounds.contains(point, inclusive=true) {
      if best is Some(current) &&
        current.bounds.width * current.bounds.height <=
        target.bounds.width * target.bounds.height {
        continue
      }
      best = Some(target)
    }
  }
  best
}

///|
pub extend TextRun with Eq::{equal, not_equal}

///|
pub extend Structure with Eq::{equal, not_equal}

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend TextRun with @debug.Debug::{to_repr}

///|
pub extend Structure with @debug.Debug::{to_repr}

///|
pub extend Target with @debug.Debug::{to_repr}
