///|
test "a compacted count never gains a digit it did not earn" {
  inspect(@labels.compact_count(0), content="0")
  inspect(@labels.compact_count(999), content="999")
  inspect(@labels.compact_count(1000), content="1k")
  inspect(@labels.compact_count(1049), content="1k")
  inspect(@labels.compact_count(1050), content="1.1k")
  inspect(@labels.compact_count(12345), content="12.3k")
  inspect(@labels.compact_count(999_949), content="999.9k")
  inspect(@labels.compact_count(999_950), content="1M")
  inspect(@labels.compact_count(1_230_000), content="1.2M")
}

///|
test "a duration never shows finer units than its own scale" {
  assert_eq(@labels.duration(-1500.0), "0s")
  assert_eq(@labels.duration(0.0), "0s")
  assert_eq(@labels.duration(950.0), "0s")
  assert_eq(@labels.duration(59_999.0), "59s")
  assert_eq(@labels.duration(60_000.0), "1m 0s")
  assert_eq(@labels.duration(134_000.0), "2m 14s")
  assert_eq(@labels.duration(3_599_000.0), "59m 59s")
  // Past an hour the seconds column is noise to anyone reading it.
  assert_eq(@labels.duration(3_600_000.0), "1h 0m")
  assert_eq(@labels.duration(87_240_000.0), "24h 14m")
}
