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
