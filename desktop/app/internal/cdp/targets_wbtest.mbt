///|
async test "target connection rejects missing or unrelated debugger endpoints" {
  for
    endpoint in [
      None,
      Some("ws://127.0.0.1:9223/devtools/page/other-port"),
      Some("ws://example.test:9222/devtools/page/remote"),
      Some("ws://127.0.0.1:9222/unrelated"),
      Some("ws://localhost:9222@remote.test/devtools/page/not-local"),
    ] {
    let target : Target = { kind: "page", debugger_url: endpoint, port: 9222, }
    let rejected = try {
      let connection = target.connect()
      connection.close()
      false
    } catch {
      Protocol(message) => {
        assert_eq(
          message,
          if endpoint is None {
            "CDP target has no debugger endpoint"
          } else {
            "CDP target endpoint does not belong to its debugging service"
          },
        )
        true
      }
      error => raise error
    }
    assert_true(rejected)
  }
}
