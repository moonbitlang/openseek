// The page's accessibility tree, as the Accessibility domain reports it.

///|
/// How large a tree a page may report. A long page's tree runs to several
/// megabytes, well past what other replies are allowed.
const MaxTreeBytes : Int32 = 32 * 1024 * 1024

///|
pub struct AxNodeId(String) derive(Debug, Eq, Hash)

///|
/// One node of the tree. An `AXValue`'s own `value` is all that is kept of
/// it: its type and sources say how the browser arrived at it.
pub struct AxNode {
  id : AxNodeId
  // A node the browser leaves out of what assistive technology sees. Its
  // children may still be seen.
  ignored : Bool
  role : String?
  name : String?
  // What a control holds: a text field's text, a slider's number.
  value : Json?
  // The node's states and attributes (`focused`, `checked`, `level`, ...),
  // by name, in the order the browser gave them.
  properties : Map[String, Json]
  children : Array[AxNodeId]
  // The DOM node this one stands for. Nodes the browser makes up, such as
  // the boxes of a line of text, stand for none.
  dom_node : BackendNodeId?
} derive(Debug, Eq)

///|
/// The `value` of the `AXValue` at `key`, when there is one: either can be
/// missing.
fn ax_value(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> Json? raise @json.JsonDecodeError {
  match fields.get(key) {
    None => None
    Some(Object(value)) => value.get("value")
    Some(_) => raise JsonDecodeError((path.add_key(key), "expected an AXValue"))
  }
}

///|
/// The text an `AXValue` at `key` holds, when there is one.
fn ax_text(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> String? raise @json.JsonDecodeError {
  match ax_value(fields, key, path) {
    None => None
    Some(String(text)) => Some(text)
    Some(_) => raise JsonDecodeError((path.add_key(key), "expected text"))
  }
}

///|
/// An `AXNode`. Fields the tree does not use are ignored; a field it uses
/// that is present and malformed is an error.
impl @json.FromJson for AxNode with fn from_json(json, path) {
  guard json is Object(fields) &&
    fields.get("nodeId") is Some(String(id)) &&
    fields.get("ignored") is Some(True | False as ignored) else {
    raise JsonDecodeError(
      (path, "expected an AXNode with `nodeId` and `ignored`"),
    )
  }
  let properties = Map([])
  match fields.get("properties") {
    None => ()
    Some(Array(listed)) =>
      for i, property in listed {
        let at = path.add_key("properties").add_index(i)
        guard property is Object(property) &&
          property.get("name") is Some(String(name)) else {
          raise JsonDecodeError((at, "expected an AXProperty"))
        }
        if ax_value(property, "value", at) is Some(value) {
          properties[name] = value
        }
      }
    Some(_) =>
      raise JsonDecodeError((path.add_key("properties"), "expected an array"))
  }
  let children : Array[String] = match fields.get("childIds") {
    None => []
    Some(ids) => @json.from_json(ids, path=path.add_key("childIds"))
  }
  let dom_node = match fields.get("backendDOMNodeId") {
    None => None
    Some(id) =>
      Some(
        BackendNodeId(
          @json.from_json(id, path=path.add_key("backendDOMNodeId")),
        ),
      )
  }
  {
    id: AxNodeId(id),
    ignored: ignored is True,
    role: ax_text(fields, "role", path),
    name: ax_text(fields, "name", path),
    value: ax_value(fields, "value", path),
    properties,
    children: children.map(child => AxNodeId(child)),
    dom_node,
  }
}

///|
fn decode_ax_tree(json : Json) -> Array[AxNode] raise {
  required(json, "nodes")
}

///|
/// The accessibility tree of the page's main frame, in no promised order. The
/// documents of the page's frames are not part of it.
pub async fn Connection::accessibility_tree(self : Connection) -> Array[AxNode] {
  decode_ax_tree(
    self.request("Accessibility.getFullAXTree", {}, max_bytes=MaxTreeBytes),
  )
}

///|
pub extend AxNodeId with Debug::{to_repr}

///|
pub extend AxNodeId with Eq::{equal, not_equal}

///|
pub extend AxNodeId with Hash::{hash, hash_combine}

///|
pub extend AxNode with Debug::{to_repr}

///|
pub extend AxNode with Eq::{equal, not_equal}
