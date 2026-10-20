// Demo answers for the console's relay routes: one fixed account with an
// online and an offline device. Pages render and navigate; connecting to a
// device or opening Cloud needs a relay.

///|
let demo_devices : Json = {
  "devices": [
    {
      "id": "demo-mac",
      "name": "Demo Mac",
      "hostname": "demo.local",
      "online": true,
    },
    {
      "id": "demo-office",
      "name": "Office computer",
      "hostname": "office.local",
      "online": false,
    },
  ],
}

///|
async fn demo_api(req : @moonback.Request, res : @moonback.Responder) -> Unit {
  let signed_in = req.headers.get("authorization") is Some(_)
  match (req.meth, req.path) {
    (Post, "/v2/auth/logout") => res.send_void(status=204)
    (_, "/v2/auth/me" | "/v2/auth/session" | "/v2/devices") if !signed_in =>
      res.send_void(status=401)
    (Get, "/v2/auth/me") => res.send_json(demo_user)
    (Post, "/v2/auth/session") => res.send_json(demo_account)
    (Get, "/v2/devices") => res.send_json(demo_devices)
    _ => demo_unavailable(res)
  }
}

///|
async fn demo_unavailable(res : @moonback.Responder) -> Unit {
  res.send_json(
    { "error": "not available in demo mode; run the proxy against a relay" },
    status=503,
  )
}
