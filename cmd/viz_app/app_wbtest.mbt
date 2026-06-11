///|
test "parse_load reads a found envelope with header" {
  let text =
    #|{"found":true,"events":"{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n","header":{"version":1,"system_prompt":"SYS"}}
  match parse_load(text) {
    Loaded(parsed, system_prompt, header_present) => {
      inspect(parsed.events.length(), content="1")
      inspect(system_prompt, content="SYS")
      inspect(header_present, content="true")
    }
    _ => fail("expected Loaded")
  }
}

///|
test "parse_load treats a null header as events-only" {
  let text =
    #|{"found":true,"events":"","header":null}
  match parse_load(text) {
    Loaded(_, system_prompt, header_present) => {
      inspect(system_prompt, content="")
      inspect(header_present, content="false")
    }
    _ => fail("expected Loaded")
  }
}

///|
test "parse_load distinguishes not-found from malformed" {
  guard parse_load("{\"found\":false}") is NotFound else {
    fail("expected NotFound")
  }
  guard parse_load("not json") is Malformed else { fail("expected Malformed") }
  guard parse_load("{\"events\":\"x\"}") is Malformed else {
    fail("expected Malformed when found is missing")
  }
}

///|
test "parse_session_rows reads the listing, skipping malformed rows" {
  let text =
    #|[{"id":"a","last_active":1,"first_prompt":"hello"},{"first_prompt":"no id"},{"id":"b","first_prompt":""}]
  guard parse_session_rows(text) is Some(rows) else { fail("expected Some") }
  inspect(rows.length(), content="2")
  inspect(rows[0].id, content="a")
  inspect(rows[0].first_prompt, content="hello")
  inspect(rows[1].id, content="b")
}

///|
test "parse_session_rows distinguishes empty list from a non-array body" {
  guard parse_session_rows("[]") is Some(empty) else {
    fail("expected Some([])")
  }
  inspect(empty.length(), content="0")
  guard parse_session_rows("oops 500") is None else {
    fail("expected None for a non-JSON body")
  }
  guard parse_session_rows("{\"error\":\"x\"}") is None else {
    fail("expected None for a non-array body")
  }
}

///|
test "session_url percent-encodes the id" {
  inspect(session_url("a b/c"), content="/api/sessions/a%20b%2Fc")
}

///|
test "theme values map to the data-theme attribute" {
  inspect(Theme::value(Light), content="light")
  inspect(Theme::value(Dark), content="dark")
  inspect(Theme::value(System), content="system")
}
