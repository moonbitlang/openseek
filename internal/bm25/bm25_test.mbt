///|
test "rank prefers the rarer matching term and drops non-matches" {
  let documents = [
    "list calendar events", "list repository issues", "list files", "send email",
  ]
  // Only document 0 has the rare `calendar`; of the `list`-only matches the
  // shorter document scores higher.
  assert_eq(@bm25.rank(query="calendar list", documents~, limit=10), [0, 2, 1])
  assert_eq(@bm25.rank(query="issues", documents~, limit=10), [1])
  assert_eq(@bm25.rank(query="weather", documents~, limit=10), [])
  assert_eq(@bm25.rank(query="the of", documents~, limit=10), [])
}

///|
test "rank keeps document order on ties and honors the limit" {
  let documents = ["open file", "open url", "open tab"]
  assert_eq(@bm25.rank(query="open", documents~, limit=10), [0, 1, 2])
  assert_eq(@bm25.rank(query="open", documents~, limit=2), [0, 1])
  assert_eq(@bm25.rank(query="open", documents~, limit=0), [])
  assert_eq(@bm25.rank(query="open", documents=[], limit=3), [])
}

///|
test "rank discounts a match in a long document" {
  let documents = [
    "event " + "padding words that dilute the single match ".repeat(10),
    "event short",
  ]
  assert_eq(@bm25.rank(query="event", documents~, limit=10), [1, 0])
}
