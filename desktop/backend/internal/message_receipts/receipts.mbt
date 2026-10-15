///|
struct Receipts[T] {
  pending : Map[String, Receipt[T]]
}

///|
struct Receipt[T] {
  owner : Receipts[T]
  id : String
  notify : (T) -> Unit
  mut result : T?
}

///|
pub fn[T] Receipts::Receipts() -> Receipts[T] {
  { pending: Map([]), }
}

///|
pub fn[T] Receipts::watch(
  self : Receipts[T],
  id : String,
  notify : (T) -> Unit,
) -> Receipt[T] {
  let receipt = { owner: self, id, notify, result: None, }
  self.pending[id] = receipt
  receipt
}

///|
pub fn[T] Receipt::result(self : Receipt[T]) -> T? {
  self.result
}

///|
pub fn[T] Receipt::close(self : Receipt[T]) -> Unit {
  if self.owner.pending.get(self.id) is Some(current) &&
    physical_equal(self, current) {
    self.owner.pending.remove(self.id)
  }
}

///|
/// Receipts settle once, independently of turn-finished notifications. Keeping
/// the outcome on the subscription also permits recovery after an inbox gap.
pub fn[T] Receipts::settle(
  self : Receipts[T],
  id : String,
  outcome : T,
) -> Unit {
  if self.pending.get(id) is Some(receipt) {
    self.pending.remove(id)
    receipt.result = Some(outcome)
    (receipt.notify)(outcome)
  }
}

///|
/// The stdout consumer owns this boundary, after its final durable drain.
pub fn[T] Receipts::close(self : Receipts[T], outcome : T) -> Unit {
  for id in self.pending.keys().to_array() {
    self.settle(id, outcome)
  }
}
