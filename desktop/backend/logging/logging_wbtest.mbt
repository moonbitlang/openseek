///|
test "format_timestamp renders UTC with millisecond precision" {
  assert_eq(format_timestamp(0), "1970-01-01T00:00:00.000Z")
  assert_eq(format_timestamp(1793800699202), "2026-11-04T13:58:19.202Z")
  assert_eq(format_timestamp(1709209845007), "2024-02-29T12:30:45.007Z")
  assert_eq(format_timestamp(951782400000), "2000-02-29T00:00:00.000Z")
  assert_eq(format_timestamp(253402300799999), "9999-12-31T23:59:59.999Z")
}

///|
test "MOON_XLOG spec sets the root level and category overrides" {
  guard Config::parse("warn, app.db=trace ,transport=error", level=Info)
    is Some(config) else {
    fail("valid spec rejected")
  }
  assert_true(config.effective_level(None) is Warn)
  assert_true(config.effective_level(Some("update")) is Warn)
  assert_true(config.effective_level(Some("transport")) is Error)
  assert_true(config.effective_level(Some("app.db")) is Trace)
  assert_true(config.effective_level(Some("app.db.query")) is Trace)
  assert_true(config.effective_level(Some("app")) is Warn)
}

///|
test "an empty MOON_XLOG spec keeps the default level" {
  guard Config::parse(" ", level=Info) is Some(config) else {
    fail("blank spec rejected")
  }
  assert_true(config.effective_level(None) is Info)
}

///|
test "a malformed MOON_XLOG spec is rejected as a whole" {
  for
    spec in [
      "verbose", "debug,", "a..b=info", ".a=info", "a.=info", "=info", "app=loud",
    ] {
    assert_true(Config::parse(spec, level=Info) is None, msg=spec)
  }
}

///|
#callsite(autofill(loc))
fn here(loc~ : SourceLoc) -> SourceLoc {
  loc
}

///|
test "record keeps xlog's key order and lets fields win on a clash" {
  let source = here()
  let record = record(
    level=Warn,
    category=Some("transport"),
    timestamp_ms=1793800699202,
    source~,
    fields={ "message": "kept", "level": "shadowed", "count": 2 },
  )
  assert_eq(
    record.stringify(),
    "{\"timestamp\":\"2026-11-04T13:58:19.202Z\",\"level\":\"shadowed\",\"category\":\"transport\",\"source\":\"\{source}\",\"message\":\"kept\",\"count\":2}",
  )
}

///|
test "record omits category when none is given" {
  let source = here()
  let record = record(level=Info, category=None, timestamp_ms=0, source~, fields={
    "message": "start",
  })
  assert_eq(
    record.stringify(),
    "{\"timestamp\":\"1970-01-01T00:00:00.000Z\",\"level\":\"INFO\",\"source\":\"\{source}\",\"message\":\"start\"}",
  )
}
