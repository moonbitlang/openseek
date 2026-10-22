///|
/// The tree a page reporting `nodes` gives, read through a CDP connection.
async fn tree_of(nodes : Array[Json]) -> Array[@cdp.AxNode] {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        serve_target_list(server, ["page"])
        let (conn, _) = server.accept()
        defer conn.close()
        let ws = @websocket.from_http_server(conn.read_request(), conn)
        defer ws.close()
        ignore(ws.recv().read_all())
        let reply : Json = { "id": 1, "result": { "nodes": Json(nodes) } }
        ws.send_text(reply.stringify())
      })
      let connection = @cdp.list_targets(server.addr.port())[0].connect()
      defer connection.close()
      connection.accessibility_tree()
    })
  })
}

///|
/// Run `f` against a page that answers its commands, in order, with
/// `replies` (each a CDP reply without its id), and give back the commands
/// it was sent: each one's method and params.
async fn scripted_page(
  replies : Array[Json],
  f : async (@cdp.Connection) -> Unit,
) -> Array[(String, Json)] {
  let sent : Array[(String, Json)] = []
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        serve_target_list(server, ["page"])
        let (conn, _) = server.accept()
        defer conn.close()
        let ws = @websocket.from_http_server(conn.read_request(), conn)
        defer ws.close()
        for reply in replies {
          guard @json.parse(ws.recv().read_all().text())
            is { "id": id, "method": String(method_), "params": params, .. } else {
            fail("malformed command")
          }
          sent.push((method_, params))
          guard reply is Object(fields) else { fail("malformed reply") }
          let answer = fields.copy()
          answer["id"] = id
          ws.send_text(Json::object(answer).stringify())
        }
      })
      let connection = @cdp.list_targets(server.addr.port())[0].connect()
      defer connection.close()
      f(connection)
    })
  })
  sent
}

///|
fn value_reply(value : Json) -> Json {
  { "result": { "result": { "type": "object", "value": value } } }
}

///|
/// The page's account of its document, as `document` asks for it.
fn document_reply(origin : Double, complete : Bool) -> Json {
  value_reply({
    "origin": Json(origin),
    "entry": null,
    "complete": Json(complete),
    "url": "https://example.com/",
    "title": "Example",
  })
}

///|
/// An accessibility node as the browser reports it.
fn ax(
  id : String,
  role : String,
  name? : String,
  children~ : Array[String] = [],
  dom? : Int32,
  ignored~ : Bool = false,
  properties~ : Array[(String, Json)] = [],
  value? : String,
) -> Json {
  let node : Map[String, Json] = {
    "nodeId": Json(id),
    "ignored": Json(ignored),
    "role": { "type": "role", "value": Json(role) },
    "childIds": Json(children.map(child => Json(child))),
    "properties": Json(
      properties.map(property => {
        (
          {
            "name": Json(property.0),
            "value": { "type": "x", "value": property.1 },
          } : Json)
      }),
    ),
  }
  if name is Some(name) {
    node["name"] = { "type": "computedString", "value": Json(name) }
  }
  if dom is Some(dom) {
    node["backendDOMNodeId"] = Json(dom)
  }
  if value is Some(value) {
    node["value"] = { "type": "string", "value": Json(value) }
  }
  Json::object(node)
}

///|
async test "a snapshot shows what a person perceives, with refs on what they can act on" {
  let nodes = tree_of([
    ax("1", "RootWebArea", name="Example", children=["2"], dom=1),
    // Layout the page used, which says nothing itself.
    ax("2", "generic", children=["3", "5", "7", "9", "11", "12"], dom=2),
    ax("3", "heading", name="Example Domain", children=["4"], dom=3, properties=[
      ("level", 1),
    ]),
    // The heading's own text repeats its name.
    ax("4", "StaticText", name="Example Domain", children=["41"]),
    ax("41", "InlineTextBox", name="Example Domain"),
    ax("5", "paragraph", children=["6"], dom=5),
    ax("6", "StaticText", name="This domain is for \"examples\".", dom=6),
    ax("7", "link", name="More information", children=["8"], dom=7, properties=[
      ("focusable", true),
      ("url", "https://www.iana.org/"),
    ]),
    ax("8", "StaticText", name="More information"),
    ax("9", "textbox", name="Search", dom=9, value="moon", properties=[
      ("focusable", true),
      ("focused", true),
      ("disabled", false),
    ]),
    // What the browser hides from assistive technology lifts its children.
    ax("11", "none", ignored=true, children=["13"]),
    ax("13", "checkbox", name="Agree", dom=13, properties=[("checked", "mixed")]),
    ax("12", "button", name="Menu", dom=12, properties=[
      ("focusable", true),
      ("expanded", "false"),
    ]),
  ])
  let document : Document = {
    origin: 1,
    entry: None,
    complete: false,
    url: "https://example.com/",
    title: "Example",
  }
  inspect(
    snapshot_text(document, nodes),
    content=(
      #|url: https://example.com/
      #|title: "Example"
      #|loading: true
      #|
      #|- heading "Example Domain" [level=1]
      #|- paragraph
      #|  - text "This domain is for \"examples\"."
      #|- link "More information" [url=https://www.iana.org/] [ref=7]
      #|- textbox "Search" [focused] [ref=9]: "moon"
      #|- checkbox "Agree" [checked=mixed] [ref=13]
      #|- button "Menu" [expanded=false] [ref=12]
      #|
    ),
  )
}

///|
async test "an unnamed wrapper that can be acted on is kept" {
  let nodes = tree_of([
    ax("1", "RootWebArea", children=["2"]),
    ax("2", "generic", children=["3"], dom=2, properties=[("focusable", true)]),
    ax("3", "StaticText", name="Drag me"),
  ])
  inspect(
    render_tree(nodes),
    content=(
      #|- generic [ref=2]
      #|  - text "Drag me"
      #|
    ),
  )
}

///|
async test "browser_snapshot refuses a call that names no tab of its conversation" {
  let views = BrowserViews()
  views.owners[1] = "s-other"
  guard refusal(views, "browser_snapshot", "s-1", {}) is Some(message) else {
    fail("a snapshot of no tab was not refused")
  }
  assert_true(message.contains("needs `tab`"))
  guard refusal(views, "browser_snapshot", "s-1", { "tab": 1 }) is Some(message) else {
    fail("a snapshot of another conversation's tab was not refused")
  }
  assert_true(message.contains("has no browser tab 1"))
}

///|
async test "a snapshot is read again when the page changes documents under it" {
  let tree : Json = {
    "result": {
      "nodes": [
        {
          "nodeId": "1",
          "ignored": false,
          "role": { "type": "role", "value": "RootWebArea" },
        },
      ],
    },
  }
  let mut text = ""
  // The first tree may be either document's: it is not answered.
  let sent = scripted_page(
    [
      document_reply(1, true),
      tree,
      document_reply(2, false),
      document_reply(2, true),
      tree,
      document_reply(2, true),
    ],
    connection => text = snapshot(connection, 4),
  )
  assert_eq(sent.length(), 6)
  assert_true(text.contains("loading: false"))
}
