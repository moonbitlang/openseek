///|
test "relative dates retain locale formatting and time boundaries" {
  for
    (value, expected) in [
      ("invalid", "invalid"),
      ("2026-09-23T12:01:00Z", "now"),
      ("2026-09-23T11:59:01Z", "now"),
      ("2026-09-23T11:59:00Z", "1 minute ago"),
      ("2026-09-23T11:00:00Z", "1 hour ago"),
      ("2026-09-22T12:00:00Z", "1 day ago"),
      ("2026-09-17T12:00:00Z", "6 days ago"),
      ("2026-09-01T00:00:00", "Sep 1, 2026"),
    ] {
    assert_eq(
      with_relative_date_clock(() => relative_date(value, "en-US")),
      expected,
    )
  }
  assert_eq(
    with_relative_date_clock(() => relative_date("2026-09-23T11:59:00Z", "es")),
    "hace 1 minuto",
  )
}

///|
extern "js" fn with_relative_date_clock(compute : () -> String) -> String =
  #| compute => {
  #|   const original = Date.now;
  #|   Date.now = () => Date.parse('2026-09-23T12:00:00Z');
  #|   try { return compute(); } finally { Date.now = original; }
  #| }
