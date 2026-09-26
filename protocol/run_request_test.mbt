///|
test "a request is exactly what to_json writes, and reads back" {
  let fixtures : Array[(String, @openseek_protocol.RunRequest)] = [
    (
      (
        #|{"version":1,"input":{"task":"Fix the parser"},"request_id":"parser-fix-1","limits":{"max_steps":100}}
      ),
      {
        request_id: Some("parser-fix-1"),
        kind: None,
        input: { "task": "Fix the parser" },
        max_steps: Some(100),
      },
    ),
    (
      (
        #|{"version":1,"input":{"query":"Explain the parser","hints":"Focus on recovery"},"kind":"explore"}
      ),
      {
        request_id: None,
        kind: Some("explore"),
        input: { "query": "Explain the parser", "hints": "Focus on recovery" },
        max_steps: None,
      },
    ),
  ]
  for fixture in fixtures {
    let (text, request) = fixture
    assert_eq(request.to_json().stringify(), text)
    assert_eq(@openseek_protocol.parse_run_request(@json.parse(text)), request)
  }
}

///|
fn run_request_error(
  text : String,
) -> @openseek_protocol.RunRequestError? raise {
  let json = @json.parse(text)
  let _ = @openseek_protocol.parse_run_request(json) catch {
    error => return Some(error)
  }
  None
}

///|
test "requests that cannot be run are refused, naming why" {
  let cases : Array[(String, @openseek_protocol.RunRequestError)] = [
    (
      (
        #|{"version":2,"input":{}}
      ),
      UnsupportedVersion(2),
    ),
    (
      (
        #|{"input":{}}
      ),
      Malformed("version"),
    ),
    (
      (
        #|{"version":1}
      ),
      Malformed("input"),
    ),
    (
      (
        #|{"version":1,"input":{},"kind":""}
      ),
      Malformed("kind"),
    ),
    (
      (
        #|{"version":1,"input":{},"request_id":7}
      ),
      Malformed("request_id"),
    ),
    (
      (
        #|{"version":1,"input":{},"limits":{"max_steps":0}}
      ),
      Malformed("limits.max_steps"),
    ),
    (
      (
        #|{"version":1,"input":{},"limits":{"max_steps":1.5}}
      ),
      Malformed("limits.max_steps"),
    ),
    (
      (
        #|{"version":1,"input":{},"limits":5}
      ),
      Malformed("limits"),
    ),
    // A schema this engine would silently ignore is refused instead.
    (
      (
        #|{"version":1,"input":{},"schema":{"type":"object"}}
      ),
      Unsupported("schema"),
    ),
  ]
  for case in cases {
    let (text, error) = case
    assert_eq(run_request_error(text), Some(error))
  }
}

///|
test "unknown request fields are ignored" {
  assert_eq(
    @openseek_protocol.parse_run_request(
      @json.parse(
        (
          #|{"version":1,"input":{"task":"t"},"priority":"high","limits":{"deadline_ms":5}}
        ),
      ),
    ),
    { request_id: None, kind: None, input: { "task": "t" }, max_steps: None, },
  )
}
