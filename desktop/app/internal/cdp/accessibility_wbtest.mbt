///|
test "accessibility nodes keep the values of their AXValues" {
  let nodes = decode_ax_tree({
    "nodes": [
      {
        "nodeId": "1",
        "ignored": false,
        "role": { "type": "internalRole", "value": "RootWebArea" },
        "name": { "type": "computedString", "value": "Example", "sources": [] },
        "childIds": ["2", "3"],
        "backendDOMNodeId": 7,
        "frameId": "F",
      },
      {
        "nodeId": "2",
        "ignored": false,
        "role": { "type": "role", "value": "textbox" },
        "name": { "type": "computedString", "value": "Search" },
        "value": { "type": "string", "value": "moon" },
        "properties": [
          {
            "name": "focusable",
            "value": { "type": "booleanOrUndefined", "value": true },
          },
          {
            "name": "checked",
            "value": { "type": "tristate", "value": "mixed" },
          },
          {
            "name": "describedby",
            "value": { "type": "idrefList", "relatedNodes": [] },
          },
        ],
        "parentId": "1",
        "backendDOMNodeId": 9,
      },
      {
        "nodeId": "3",
        "ignored": true,
        "ignoredReasons": [],
        "role": { "type": "role" },
        "parentId": "1",
      },
    ],
  })
  assert_eq(nodes.length(), 3)
  assert_eq(nodes[0].role, Some("RootWebArea"))
  assert_eq(nodes[0].children, [AxNodeId("2"), AxNodeId("3")])
  assert_eq(nodes[1], {
    id: AxNodeId("2"),
    ignored: false,
    role: Some("textbox"),
    name: Some("Search"),
    value: Some("moon"),
    // A property whose AXValue holds no value has nothing to keep.
    properties: Map([("focusable", true), ("checked", "mixed")]),
    children: [],
    dom_node: Some(BackendNodeId(9)),
  })
  assert_eq(nodes[2].role, None)
  assert_eq(nodes[2].name, None)
  assert_eq(nodes[2].dom_node, None)
}

///|
test "a malformed field the tree uses is a decoding error" {
  for
    node in [
      ({ "ignored": false } : Json),
      { "nodeId": "1", "ignored": "no" },
      {
        "nodeId": "1",
        "ignored": false,
        "role": { "type": "role", "value": 3 },
      },
      { "nodeId": "1", "ignored": false, "name": "Search" },
      { "nodeId": "1", "ignored": false, "properties": {} },
      { "nodeId": "1", "ignored": false, "properties": [{ "value": {} }] },
      { "nodeId": "1", "ignored": false, "childIds": [2] },
      { "nodeId": "1", "ignored": false, "backendDOMNodeId": "9" },
    ] {
    let rejected = try {
      ignore(decode_ax_tree({ "nodes": [node] }))
      false
    } catch {
      @json.JsonDecodeError(_) => true
      error => raise error
    }
    assert_true(rejected, msg="accepted \{node.stringify()}")
  }
}

///|
async test "a page's tree may be larger than other replies" {
  // Past the two megabytes any other reply is allowed.
  let long_name = "x".repeat(3 * 1024 * 1024)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        let (conn, _) = server.accept()
        defer conn.close()
        let ws = @websocket.from_http_server(conn.read_request(), conn)
        defer ws.close()
        assert_eq(
          @json.parse(ws.recv().read_all().text()),
          (
            { "id": 1, "method": "Accessibility.getFullAXTree", "params": {} } :
            Json),
        )
        let reply : Json = {
          "id": 1,
          "result": {
            "nodes": [
              {
                "nodeId": "1",
                "ignored": false,
                "name": { "type": "computedString", "value": Json(long_name) },
              },
            ],
          },
        }
        ws.send_text(reply.stringify())
      })
      let connection = connect("ws://127.0.0.1:\{server.addr.port()}")
      defer connection.close()
      let nodes = connection.accessibility_tree()
      assert_eq(nodes.length(), 1)
      assert_eq(
        nodes[0].name.map(name => name.length()),
        Some(long_name.length()),
      )
    })
  })
}
