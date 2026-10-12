///|
/// Display data from the bounded selection payload; the original JSON remains
/// the agent context so its source anchors and document identity stay intact.
pub(all) struct OfficeSelectionSummary {
  file : String
  text : String
  location : String?
} derive(Eq)

///|
pub extend OfficeSelectionSummary with Eq::{equal, not_equal}

///|
fn selection_page(value : Json) -> Int32? {
  guard value is Number(number, ..) &&
    !number.is_nan() &&
    !number.is_inf() &&
    number >= 1 &&
    number <= 2147483647 &&
    number == number.to_int().to_double() else {
    return None
  }
  Some(number.to_int())
}

///|
fn selection_pages(first : Int32, last : Int32) -> String {
  if first == last {
    "p. \{first}"
  } else {
    "pp. \{first}–\{last}"
  }
}

///|
pub fn office_selection_summary(
  materialized : String,
) -> OfficeSelectionSummary? {
  let value = @json.parse(materialized) catch { _ => return None }
  guard value
    is {
      "schema": String("office.selection.materialized.v1"),
      "selection": selection,
      "source": source,
      ..
    } &&
    selection is { "text": String(text), .. } else {
    return None
  }
  let file = match source {
    { "file": String(file), .. } => file
    { "reference": { "file": String(file), .. }, .. } => file
    _ => return None
  }
  guard !file.is_empty() else { return None }
  let location = match (selection, source) {
    ({ "sheet": String(sheet), "range": String(range_), .. }, _) =>
      Some("\{sheet}!\{range_}")
    (
      _,
      {
        "reference": {
          "start": { "page": first, .. },
          "end": { "page": last, .. },
          ..
        },
        ..
      },
    ) => {
      guard selection_page(first) is Some(first) &&
        selection_page(last) is Some(last) else {
        return None
      }
      Some(selection_pages(first, last))
    }
    ({ "pages": Array(pages), .. }, _) => {
      let pages = pages.filter_map(selection_page)
      if pages.is_empty() {
        None
      } else {
        Some(selection_pages(pages[0], pages[pages.length() - 1]))
      }
    }
    _ => None
  }
  Some({ file, text, location, })
}

///|
pub fn OfficeSelectionSummary::heading(self : OfficeSelectionSummary) -> String {
  let parts = self.file.split("/").to_array()
  let name = parts[parts.length() - 1].to_owned()
  match self.location {
    Some(location) => "\{name} · \{location}"
    None => name
  }
}

///|
fn selection_excerpt(text : String, limit : Int32) -> String {
  let out = StringBuilder()
  let mut count = 0
  let mut space = false
  for ch in text.iter() {
    if ch is (' ' | '\t' | '\n' | '\r') {
      space = count > 0
      continue
    }
    if count >= limit {
      out.write_string("…")
      break
    }
    if space {
      out.write_char(' ')
      space = false
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string()
}

///|
pub fn office_selection_label(materialized : String) -> String {
  guard office_selection_summary(materialized) is Some(summary) else {
    return "Office selection"
  }
  let excerpt = selection_excerpt(summary.text, 64)
  if excerpt.is_empty() {
    summary.heading()
  } else {
    "\{summary.heading()} · “\{excerpt}”"
  }
}

///|
pub fn office_selection_title(materialized : String) -> String {
  guard office_selection_summary(materialized) is Some(summary) else {
    return "Office selection"
  }
  let location = summary.location.map(value => " · " + value).unwrap_or("")
  "\{summary.file}\{location}\n\{summary.text}"
}
