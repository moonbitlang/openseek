///|
/// A page covers whole user turns. Its range refers to the complete overview,
/// never to a filtered set of ticks. Appending turns leaves older pages stable.
pub(all) struct TranscriptPage {
  index : Int32
  count : Int32
  start : Int32
  end : Int32
} derive(Eq, Debug)

///|
pub const TURNS_PER_PAGE : Int32 = 20

///|
pub fn TranscriptPage::of(turns : Int32, index? : Int32) -> TranscriptPage {
  let count = Int32::max(1, (turns + TURNS_PER_PAGE - 1) / TURNS_PER_PAGE)
  let index = Int32::max(0, Int32::min(index.unwrap_or(count - 1), count - 1))
  {
    index,
    count,
    start: index * TURNS_PER_PAGE,
    end: Int32::min((index + 1) * TURNS_PER_PAGE, turns),
  }
}

///|
pub fn TranscriptPage::is_latest(self : TranscriptPage) -> Bool {
  self.index == self.count - 1
}

///|
pub extend TranscriptPage with Eq::{equal, not_equal}

///|
pub extend TranscriptPage with Debug::{to_repr}
