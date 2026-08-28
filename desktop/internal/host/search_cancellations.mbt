// File, text and semantic search share the same wire-level cancellation
// race: a cancel can arrive before the request carrying the same globally
// unique id.

///|
const MaxSearchCancellations : Int = 128

///|
/// A bounded insertion-ordered set of cancelled request ids. Re-recording an
/// id moves it to the newest position, so the oldest unmatched cancellation
/// is the one evicted when the connection stays alive for a long time.
priv struct CancelledRequests {
  values : Set[String]
}

///|
fn CancelledRequests::CancelledRequests() -> CancelledRequests {
  { values: Set([]), }
}

///|
fn CancelledRequests::contains(
  self : CancelledRequests,
  request_id : String,
) -> Bool {
  self.values.contains(request_id)
}

///|
fn CancelledRequests::record(
  self : CancelledRequests,
  request_id : String,
) -> Unit {
  self.values.remove(request_id)
  self.values.add(request_id)
  if self.values.length() > MaxSearchCancellations &&
    self.values.iter().next() is Some(oldest) {
    self.values.remove(oldest)
  }
}

///|
fn CancelledRequests::remove(
  self : CancelledRequests,
  request_id : String,
) -> Unit {
  self.values.remove(request_id)
}

///|
test "cancelled request ids stay bounded in insertion order" {
  let cancellations = CancelledRequests()
  for index in 0..<(MaxSearchCancellations + 5) {
    cancellations.record("request:\{index}")
  }
  assert_eq(cancellations.values.length(), MaxSearchCancellations)
  assert_false(cancellations.contains("request:0"))
  assert_true(cancellations.contains("request:\{MaxSearchCancellations + 4}"))
}
