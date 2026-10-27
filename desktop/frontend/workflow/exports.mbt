// Deliberate exports with no in-repo production consumer outside this
// package (see shrink_package.md): test seams. Each entry documents its
// reason and the consumer `moon ide analyze` counts.

///|
/// How many of a run's children are still running. The panel uses it inside
/// this package; it stays exported as a test seam for `desktop/frontend`'s
/// "a workflow's brackets and its children's brackets build the run's rows"
/// test, which asserts a run read back from the conversation's model.
pub fn Run::running(self : Run) -> Int32 {
  self.rows.count_if(row => row.status is None)
}

///|
/// Total cost across children that reported one; `None` when none did. The
/// panel uses it inside this package; it stays exported as a test seam for
/// `desktop/frontend`'s "a workflow entry refines the parent conversation's
/// run" test, which asserts the total a run reports through the model.
pub fn Run::cost_usd(self : Run) -> Double? {
  self.rows.fold(init=None, (total : Double?, row) => {
    match row.cost_usd {
      Some(cost) => Some(total.unwrap_or(0.0) + cost)
      None => total
    }
  })
}
