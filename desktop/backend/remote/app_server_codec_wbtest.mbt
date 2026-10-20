///|
test "app-server announcement and response preserve the protocol wire format" {
  let announcement = AppServerAnnouncement::{ port: 1234, instance: "current", }
  assert_eq(@json.to_json(announcement), {
    "port": 1234,
    "instance": "current",
    "protocol": 1,
  })
  let response = AppServerInitializeResponse::{
    id: "request-1",
    instance: "current",
  }
  assert_eq(@json.to_json(response), {
    "jsonrpc": "2.0",
    "id": "request-1",
    "result": { "protocol": 1, "instance": "current" },
  })
}

///|
test "app-server initialize ignores extensions and echoes opaque request IDs" {
  for id in ([1, "request-1", Json::null(), { "opaque": true }] : Array[Json]) {
    let request : AppServerInitializeRequest = @json.from_json({
      "jsonrpc": "2.0",
      "id": id,
      "method": "initialize",
      "extension": true,
      "params": {
        "protocol": 1,
        "instance": "current",
        "extension": Json::null(),
      },
    })
    assert_eq(request.instance, "current")
    let response = AppServerInitializeResponse::{
      id: request.id,
      instance: request.instance,
    }
    assert_eq(@json.to_json(response), {
      "jsonrpc": "2.0",
      "id": id,
      "result": { "protocol": 1, "instance": "current" },
    })
  }
}

///|
test "app-server initialize rejects missing and malformed required fields" {
  let valid : Map[String, Json] = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": { "protocol": 1, "instance": "current" },
  }
  let invalid : Array[Json] = [Json::null(), [], "initialize"]
  for key in ["jsonrpc", "id", "method", "params"] {
    let fields = valid.copy()
    fields.remove(key)
    invalid.push(Json::object(fields))
  }
  for
    (key, values) in [
      ("jsonrpc", [Json::null(), 2, "1.0"]),
      ("method", [Json::null(), 1, "fs.browse"]),
      (
        "params",
        [Json::null(), [], {}, { "protocol": 1 }, { "instance": "current" }],
      ),
    ] {
    for value in values {
      let fields = valid.copy()
      fields[key] = value
      invalid.push(Json::object(fields))
    }
  }
  for
    (key, values) in [
      ("protocol", [Json::null(), "1", 2]),
      ("instance", [Json::null(), 1, {}]),
    ] {
    for value in values {
      let fields = valid.copy()
      let params : Map[String, Json] = { "protocol": 1, "instance": "current" }
      params[key] = value
      fields["params"] = Json::object(params)
      invalid.push(Json::object(fields))
    }
  }
  for value in invalid {
    try {
      let _ : AppServerInitializeRequest = @json.from_json(value)
    } catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed initialize: " + value.stringify())
    }
  }
}
