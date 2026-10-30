///|
/// An immutable chart carried in a tool result's display-only `data`. The
/// model receives its embed reference, never this payload.
pub struct Chart {
  id : String
  spec : Json
} derive(Eq, Debug)

///|
pub fn Chart::Chart(id~ : String, spec~ : Json) -> Chart {
  { id, spec, }
}

///|
fn valid_id(id : StringView) -> Bool {
  id.has_prefix("chart_") &&
  id.length() > 6 &&
  id.all(c => {
    ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c.is_ascii_digit()) ||
    c == '_' ||
    c == '-'
  })
}

///|
pub impl @json.ToJson for Chart with fn to_json(self) {
  { "id": self.id, "kind": "mathplotlib", "version": 1, "spec": self.spec }
}

///|
pub impl @json.FromJson for Chart with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "kind": "mathplotlib",
      "version": 1,
      "spec": Object(_) as spec,
      ..
    } &&
    valid_id(id) else {
    raise @json.JsonDecodeError((path, "Expected a version 1 chart artifact"))
  }
  { id, spec, }
}

///|
/// Unknown artifact kinds/versions and damaged entries remain unresolved. A
/// reader must never reinterpret their payload as another chart.
pub fn charts(data : Json?) -> Array[Chart] {
  guard data is Some({ "artifacts": Array(entries), .. }) else { return [] }
  let result = []
  for entry in entries {
    let chart : Chart = @json.from_json(entry) catch { _ => continue }
    result.push(chart)
  }
  result
}

///|
/// Merge into the existing structured output, retaining PTC and image metadata.
pub fn Chart::attach(self : Chart, data : Json?) -> Json {
  let fields = match data {
    Some(Object(fields)) => fields.copy()
    Some(other) => { "output": other }
    None => Map([])
  }
  let previous = match fields.get("artifacts") {
    Some(Array(entries)) => entries
    _ => []
  }
  fields["artifacts"] = Json::array([..previous, self.to_json()])
  Json::object(fields)
}

///|
pub fn Chart::embed(self : Chart) -> String {
  let title = match self.spec {
    { "title": String(title), .. } if !title.is_blank() => title
    _ => "Chart"
  }
  // Alt text is prose, including when a chart title contains Markdown syntax.
  let alt = title
    .replace_all(old="\\", new="\\\\")
    .replace_all(old="[", new="\\[")
    .replace_all(old="]", new="\\]")
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
  "![\{alt}](artifact://\{self.id})"
}

///|
pub fn Chart::receipt(self : Chart) -> String {
  Json::object({ "artifact_id": Json(self.id), "embed": Json(self.embed()) }).stringify()
}

///|
pub extend Chart with Eq::{equal, not_equal}

///|
pub extend Chart with @json.ToJson::{to_json}

///|
#deprecated("use @json.from_json")
pub extend Chart with @json.FromJson::{from_json}

///|
#deprecated("the derived Debug impl is the API")
pub extend Chart with Debug::{to_repr}
