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
/// The `value` of an `AXValue`, which may itself be missing.
fn ax_value(json : Json, key : String) -> Json? raise {
  guard field(json, key) is Some(value) else { return None }
  field(value, "value")
}

///|
fn ax_text(json : Json, key : String) -> String? raise {
  match ax_value(json, key) {
    None => None
    Some(String(text)) => Some(text)
    Some(_) => raise Protocol("Expected text in the CDP field: \{key}")
  }
}

///|
fn decode_ax_node(json : Json) -> AxNode raise {
  let properties = Map([])
  let listed : Array[Json] = optional(json, "properties").unwrap_or([])
  for property in listed {
    let name : String = required(property, "name")
    if ax_value(property, "value") is Some(value) {
      properties[name] = value
    }
  }
  let children : Array[String] = optional(json, "childIds").unwrap_or([])
  let dom_node : Int32? = optional(json, "backendDOMNodeId")
  {
    id: AxNodeId(required(json, "nodeId")),
    ignored: required(json, "ignored"),
    role: ax_text(json, "role"),
    name: ax_text(json, "name"),
    value: ax_value(json, "value"),
    properties,
    children: children.map(child => AxNodeId(child)),
    dom_node: dom_node.map(node => BackendNodeId(node)),
  }
}

///|
fn decode_ax_tree(json : Json) -> Array[AxNode] raise {
  let nodes : Array[Json] = required(json, "nodes")
  nodes.map(decode_ax_node)
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
