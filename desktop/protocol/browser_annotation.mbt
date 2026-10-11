///|
/// A bounded snapshot, independent of the lifetime of a Chromium DOM node.
pub(all) struct BrowserElement {
  url : String
  title : String
  tag : String
  selector : String?
  text : String
  html : String
} derive(Debug, Eq)

///|
pub impl @json.FromJson for BrowserElement with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "browser element")
  {
    url: object.required_string("url"),
    title: object.required_string("title"),
    tag: object.required_string("tag"),
    selector: object.optional_string("selector"),
    text: object.required_string("text"),
    html: object.required_string("html"),
  }
}

///|
pub impl ToJson for BrowserElement with fn to_json(self) {
  let fields : Map[String, Json] = {
    "url": Json(self.url),
    "title": Json(self.title),
    "tag": Json(self.tag),
    "text": Json(self.text),
    "html": Json(self.html),
  }
  if self.selector is Some(selector) {
    fields["selector"] = Json(selector)
  }
  Json(fields)
}

///|
pub(all) struct BrowserPickPayload {
  id : Int
  request : String
} derive(Debug, Eq)

///|
pub impl @json.FromJson for BrowserPickPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "browser pick")
  { id: object.required_int("id"), request: object.required_string("request"), }
}

///|
pub impl ToJson for BrowserPickPayload with fn to_json(self) {
  { "id": Json(self.id), "request": Json(self.request) }
}

///|
/// Cancellation is distinct from capture failure, which rejects the command.
pub(all) enum BrowserPickReply {
  Selected(BrowserElement)
  Cancelled
} derive(Debug, Eq)

///|
pub impl @json.FromJson for BrowserPickReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "browser pick reply")
  match object.required_string("kind") {
    "selected" => Selected(@json.from_json(object.required_json("element")))
    "cancelled" => Cancelled
    _ => raise JsonDecodeError((path, "unknown browser pick reply kind"))
  }
}

///|
pub impl ToJson for BrowserPickReply with fn to_json(self) {
  match self {
    Selected(element) => { "kind": "selected", "element": element.to_json() }
    Cancelled => { "kind": "cancelled" }
  }
}

///|
pub extend BrowserElement with Debug::{to_repr}

///|
pub extend BrowserElement with Eq::{equal, not_equal}

///|
pub extend BrowserElement with ToJson::{to_json}

///|
pub extend BrowserElement with FromJson::{from_json}

///|
pub extend BrowserPickPayload with Debug::{to_repr}

///|
pub extend BrowserPickPayload with Eq::{equal, not_equal}

///|
pub extend BrowserPickPayload with ToJson::{to_json}

///|
pub extend BrowserPickPayload with FromJson::{from_json}

///|
pub extend BrowserPickReply with Debug::{to_repr}

///|
pub extend BrowserPickReply with Eq::{equal, not_equal}

///|
pub extend BrowserPickReply with ToJson::{to_json}

///|
pub extend BrowserPickReply with FromJson::{from_json}

///|
test "browser snapshot optional selector and required fields are explicit" {
  let json : Json = {
    "url": "https://example.test",
    "title": "",
    "tag": "button",
    "text": "",
    "html": "<button></button>",
  }
  let element : BrowserElement = @json.from_json(json)
  assert_eq(element.selector, None)
  assert_eq(element.to_json(), json)
  let with_null : Json = {
    "url": "https://example.test",
    "title": "",
    "tag": "button",
    "text": "",
    "html": "<button></button>",
    "selector": null,
    "future": true,
  }
  assert_eq(@json.from_json(with_null), element)
  let malformed : Json = {
    "url": "https://example.test",
    "title": "",
    "tag": "button",
    "text": "",
    "html": "<button></button>",
    "selector": 4,
  }
  let rejected = try {
    let _ : BrowserElement = @json.from_json(malformed)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let missing = try {
    let _ : BrowserElement = @json.from_json({})
    false
  } catch {
    _ => true
  }
  assert_true(missing)
  let reply = Selected(element)
  assert_eq(@json.from_json(reply.to_json()), reply)
  let cancelled : BrowserPickReply = @json.from_json({ "kind": "cancelled" })
  assert_eq(cancelled, Cancelled)
}
