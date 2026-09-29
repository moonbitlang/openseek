///|
/// A page covers whole user turns. Its range refers to the complete overview,
/// never to a filtered set of ticks. Appending turns leaves older pages stable.
pub(all) struct Page {
  index : Int
  count : Int
  start : Int
  end : Int
} derive(Eq, Debug)

///|
pub const TURNS_PER_PAGE : Int = 20

///|
pub fn Page::of(turns : Int, index? : Int) -> Page {
  let count = Int::max(1, (turns + TURNS_PER_PAGE - 1) / TURNS_PER_PAGE)
  let index = Int::max(0, Int::min(index.unwrap_or(count - 1), count - 1))
  {
    index,
    count,
    start: index * TURNS_PER_PAGE,
    end: Int::min((index + 1) * TURNS_PER_PAGE, turns),
  }
}

///|
pub fn Page::is_latest(self : Page) -> Bool {
  self.index == self.count - 1
}

///|
pub extend Page with Eq::{equal, not_equal}

///|
pub extend Page with Debug::{to_repr}
