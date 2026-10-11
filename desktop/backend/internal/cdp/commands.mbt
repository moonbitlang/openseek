// Typed CDP methods. Wire names and codecs stay inside this package.

///|
fn empty_result(json : Json) -> Unit raise {
  guard json is Object(_) else {
    raise Protocol("Expected a CDP result object")
  }
}

///|
pub async fn Connection::enable_dom(self : Connection) -> Unit {
  empty_result(self.request("DOM.enable", {}))
}

///|
pub async fn Connection::enable_overlay(self : Connection) -> Unit {
  empty_result(self.request("Overlay.enable", {}))
}

///|
pub async fn Connection::hide_highlight(self : Connection) -> Unit {
  empty_result(self.request("Overlay.hideHighlight", {}))
}

///|
pub async fn Connection::add_binding(self : Connection, name : String) -> Unit {
  empty_result(self.request("Runtime.addBinding", { "name": Json(name) }))
}

///|
pub async fn Connection::evaluate(
  self : Connection,
  expression : String,
) -> Evaluation {
  decode_evaluation(
    self.request("Runtime.evaluate", {
      "expression": Json(expression),
      "returnByValue": true,
    }),
  )
}

///|
fn decode_resolved_node(json : Json) -> RemoteObject raise {
  decode_remote_object(required(json, "object"))
}

///|
pub async fn Connection::resolve_node(
  self : Connection,
  node : BackendNodeId,
) -> RemoteObject {
  decode_resolved_node(
    self.request("DOM.resolveNode", { "backendNodeId": Json(node.0) }),
  )
}

///|
pub(all) struct CallFunction {
  object_id : RemoteObjectId
  declaration : String
}

///|
impl ToJson for CallFunction with fn to_json(self) {
  {
    "objectId": Json(self.object_id.0),
    "functionDeclaration": Json(self.declaration),
    "returnByValue": true,
  }
}

///|
pub async fn Connection::call_function_on(
  self : Connection,
  params : CallFunction,
) -> Evaluation {
  decode_evaluation(
    self.request("Runtime.callFunctionOn", ToJson::to_json(params)),
  )
}

///|
pub async fn Connection::release_object(
  self : Connection,
  object : RemoteObjectId,
) -> Unit {
  empty_result(
    self.request("Runtime.releaseObject", { "objectId": Json(object.0) }),
  )
}

///|
impl ToJson for InspectMode with fn to_json(self) {
  match self {
    Disabled => { "mode": "none", "highlightConfig": {} }
    SearchForNode(config) =>
      { "mode": "searchForNode", "highlightConfig": ToJson::to_json(config) }
  }
}

///|
pub async fn Connection::set_inspect_mode(
  self : Connection,
  mode : InspectMode,
) -> Unit {
  empty_result(self.request("Overlay.setInspectMode", ToJson::to_json(mode)))
}
