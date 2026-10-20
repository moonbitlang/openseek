///|
/// Explicit, format-specific destinations carried in local Markdown links.
pub(all) enum Target {
  PdfPage(Int32)
  WordHeading(String)
  WordParagraph(String)
  ExcelRange(sheet~ : String, range~ : String)
} derive(Eq, Debug)

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Target with Debug::{to_repr}

///|
pub(all) struct Reference {
  path : String
  target : Target
} derive(Eq, Debug)

///|
pub extend Reference with Eq::{equal, not_equal}

///|
pub extend Reference with Debug::{to_repr}

///|
fn positive(value : StringView, maximum~ : Int32) -> Int32? {
  guard value =~ re"^[1-9][0-9]*$" else { return None }
  let number = @string.parse_int(value) catch { _ => return None }
  if number <= maximum {
    Some(number)
  } else {
    None
  }
}

///|
fn cell(value : String) -> (Int32, Int32)? {
  guard value =~ re"^[A-Z]{1,3}[1-9][0-9]*$" else { return None }
  let mut column = 0
  let mut offset = 0
  for letter in value {
    if letter < 'A' || letter > 'Z' {
      break
    }
    column = column * 26 + letter.to_int() - 64
    offset += 1
  }
  guard positive(value[offset:], maximum=1048576) is Some(row) else {
    return None
  }
  if column <= 16384 {
    Some((row, column))
  } else {
    None
  }
}

///|
fn range_bounds(value : String) -> ((Int32, Int32), (Int32, Int32))? {
  let (first, last) = match value.split_once(":") {
    Some((first, last)) => (first.to_owned(), last.to_owned())
    None => (value, value)
  }
  guard cell(first) is Some((r1, c1)) &&
    cell(last) is Some((r2, c2)) &&
    r1 <= r2 &&
    c1 <= c2 else {
    return None
  }
  Some(((r1, c1), (r2, c2)))
}

///|
/// Only documented fragments on Office paths are interpreted. Unrelated
/// fragments, web URLs, code positions and literal filenames retain their route.
pub fn parse(reference : String) -> Reference? {
  guard !reference.contains("://") &&
    reference.rev_split_once("#") is Some((path, fragment)) else {
    return None
  }
  let fields : Map[String, String] = Map([])
  for field in fragment.split("&") {
    guard field.split_once("=") is Some((key, value)) &&
      !fields.contains(key.to_owned()) else {
      return None
    }
    let value = @uri.decode_component(value)
    guard !value.is_empty() && !value.contains_any(chars="\u0000\r\n\t") else {
      return None
    }
    fields[key.to_owned()] = value
  }
  let lower = path.to_owned().to_lower()
  let target = if lower.has_suffix(".pdf") &&
    fields.length() == 1 &&
    fields.get("page") is Some(page) &&
    positive(page, maximum=2147483647) is Some(page) {
    PdfPage(page)
  } else if lower.has_suffix(".docx") && fields.length() == 1 {
    if fields.get("heading") is Some(heading) && !heading.trim().is_empty() {
      WordHeading(heading)
    } else if fields.get("paragraph") is Some(selector) &&
      selector.has_prefix("/docx/body/") {
      WordParagraph(selector)
    } else {
      return None
    }
  } else if lower.has_suffix(".xlsx") &&
    fields.length() == 2 &&
    fields.get("sheet") is Some(sheet) &&
    fields.get("range") is Some(range) &&
    range_bounds(range) is Some(_) {
    ExcelRange(sheet~, range~)
  } else {
    return None
  }
  Some({ path: path.to_owned(), target, })
}

///|
/// Keep the original citation format's explicit PDF page labels useful in
/// saved answers. Other prose is presentation; new links carry explicit targets.
pub fn citation_destination(path : String, summary : String) -> String {
  guard !path.contains("#") && path.to_lower().has_suffix(".pdf") else {
    return path
  }
  let split = match summary.rev_split_once("—") {
    Some(_) as split => split
    None => summary.rev_split_once("–")
  }
  let metadata = match split {
    Some((_, after)) => after.trim().to_owned()
    None => return path
  }
  let chinese = metadata.has_prefix("第")
  let number = if chinese {
    metadata[1:].trim_start().to_owned()
  } else if metadata.to_lower().has_prefix("page ") {
    metadata[5:].trim_start().to_owned()
  } else if metadata.has_prefix("p.") {
    metadata[2:].trim_start().to_owned()
  } else {
    return path
  }
  let mut length = 0
  for ch in number {
    if ch < '0' || ch > '9' {
      break
    }
    length += 1
  }
  guard length > 0 else { return path }
  let tail = number[length:].trim_start()
  guard (if chinese {
    tail.has_prefix("页")
  } else {
    tail.is_empty() ||
    tail.has_prefix(",") ||
    tail.has_prefix("，") ||
    tail.has_prefix(".") ||
    tail.has_prefix("。")
  }) else {
    return path
  }
  let page = positive(number[:length], maximum=2147483647)
  match page {
    Some(page) => "\{path}#page=\{page}"
    None => path
  }
}
