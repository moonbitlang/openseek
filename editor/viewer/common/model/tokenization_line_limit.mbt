///|
/// Model-owned lexical budget: shared views cannot disagree about token state.
/// The default matches VS Code's TextMate limit, including its >= boundary.
pub(all) enum TokenizationLineLimit {
  Unlimited
  Characters(Int)
} derive(Eq, Debug)

///|
pub extend TokenizationLineLimit with Eq::{equal, not_equal}

///|
pub extend TokenizationLineLimit with Debug::{to_repr}

///|
fn TokenizationLineLimit::allows(
  self : TokenizationLineLimit,
  length : Int,
) -> Bool {
  match self {
    Unlimited => true
    Characters(count) => length < count.max(1)
  }
}
