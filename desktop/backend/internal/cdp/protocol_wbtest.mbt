///|
test "runtime null, missing value, and exceptions remain distinct" {
  let null_result = decode_evaluation({
    "result": { "type": "object", "subtype": "null", "value": null },
  })
  let value : Json = null_result.decode_value()
  assert_eq(value, Json::null())
  let missing = decode_evaluation({ "result": { "type": "undefined" } })
  let rejected = try {
    let _ : Json = missing.decode_value()
    false
  } catch {
    MissingValue => true
    error => raise error
  }
  assert_true(rejected)
  let thrown = decode_evaluation({
    "result": { "type": "object", "objectId": "exception-object" },
    "exceptionDetails": { "text": "Uncaught", "exceptionId": 1 },
  })
  let rejected = try {
    let _ : Json = thrown.decode_value()
    false
  } catch {
    JavaScriptException(message) => message == "Uncaught"
    error => raise error
  }
  assert_true(rejected)
}

///|
test "supported events validate fields while unknown events are ignored" {
  let selected = decode_event({
    "method": "Overlay.inspectNodeRequested",
    "params": { "backendNodeId": 42, "future": true },
  })
  assert_eq(selected, Some(InspectNodeRequested(BackendNodeId(42))))
  assert_eq(decode_event({ "method": "DOM.documentUpdated" }), None)
  assert_eq(
    decode_event({ "method": "Overlay.inspectModeCanceled", "params": {} }),
    Some(InspectModeCanceled),
  )
  for
    params in [
      ({} : Json),
      ({ "backendNodeId": null } : Json),
      ({ "backendNodeId": "42" } : Json),
    ] {
    let rejected = try {
      ignore(
        decode_event({
          "method": "Overlay.inspectNodeRequested",
          "params": params,
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "resolve node returns a typed handle and call function encodes it" {
  let object = decode_resolved_node({
    "object": { "type": "object", "objectId": "node-42", "future": true },
  })
  guard object.object_id is Some(id) else { fail("missing object handle") }
  let params : CallFunction = {
    object_id: id,
    declaration: "function() { return this.tagName; }",
  }
  assert_eq(
    ToJson::to_json(params),
    (
      {
        "objectId": "node-42",
        "functionDeclaration": "function() { return this.tagName; }",
        "returnByValue": true,
      } : Json),
  )
  for
    result in [
      ({} : Json),
      ({ "object": { "type": "object", "objectId": 42 } } : Json),
    ] {
    let rejected = try {
      ignore(decode_resolved_node(result))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
