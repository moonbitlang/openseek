///|
test "level filter and record shape through the global logger" {
  let records : Array[Json] = []
  @logging.set_sink(record => records.push(record))
  @logging.set_level(Warn)
  @logging.debug() <? { "message": "debug dropped" }
  @logging.info() <? { "message": "info dropped" }
  @logging.warn(category="transport") <? { "message": "warn kept", "count": 2 }
  @logging.error() <? { "message": "error kept" }
  @logging.set_level(Debug)
  @logging.debug() <? { "message": "debug kept" }
  let summary = records.map(record => {
    guard record
      is Object(
        {
          "timestamp": String(timestamp),
          "level": String(level),
          "source": String(source),
          "message": String(message),
          ..
        }
      ) else {
      fail("unexpected record: \{record.stringify()}")
    }
    assert_eq(timestamp.length(), "2026-11-04T13:58:19.202Z".length())
    assert_true(timestamp.has_suffix("Z"))
    assert_true(source.contains("logging_test.mbt:"), msg=source)
    "\{level} \{message}"
  })
  assert_eq(summary, ["WARN warn kept", "ERROR error kept", "DEBUG debug kept"])
  guard records[0] is Object({ "category": "transport", "count": 2, .. }) else {
    fail("category or field missing: \{records[0].stringify()}")
  }
  assert_true(!(records[1] is Object({ "category": _, .. })))
}

///|
test "sink errors never reach the caller" {
  @logging.set_sink(_ => fail("sink is down"))
  @logging.set_level(Debug)
  @logging.error() <? { "message": "still returns" }
}
