///|
/// Row bounds retain global indices so local turn anchors and assistant step
/// numbers do not change when a different page is mounted.
priv struct PageRows {
  page : @transcript_overview.TranscriptPage
  start : Int
  end : Int
} derive(Eq)

///|
/// Index only user-turn boundaries. Built from the rows once, independently
/// of hover, scroll position, live text and the selected page.
priv struct TurnIndex {
  starts : Array[Int]
  keys : Array[@transcript_overview.TurnKey]
  row_count : Int
} derive(Eq)

///|
fn TurnIndex::new(rows : Array[VisibleRow]) -> TurnIndex {
  let starts : Array[Int] = []
  let keys : Array[@transcript_overview.TurnKey] = []
  for index, row in rows {
    if row.item.kind is User(..) {
      starts.push(index)
      keys.push(@transcript_overview.TurnKey::of(row.item, index~))
    }
  }
  { starts, keys, row_count: rows.length(), }
}

///|
fn TurnIndex::page_rows(
  self : TurnIndex,
  index : Int?,
  overlap? : Int? = None,
) -> PageRows {
  let page = @transcript_overview.TranscriptPage::of(
    self.starts.length(),
    index?,
  )
  // A tail-following page can advance after new turns arrive. Never carry an
  // old overlap across intervening pages and accidentally mount the history.
  let start = if page.start > 0 && overlap == Some(page.start - 1) {
    page.start - 1
  } else {
    page.start
  }
  let end = if page.end < self.starts.length() && overlap == Some(page.end) {
    page.end + 1
  } else {
    page.end
  }
  {
    page,
    // Notices before the first prompt belong to the first page.
    start: if start == 0 {
      0
    } else {
      self.starts[start]
    },
    end: self.starts.get(end).unwrap_or(self.row_count),
  }
}

///|
fn TurnIndex::page_for_turn(
  self : TurnIndex,
  key : @transcript_overview.TurnKey,
) -> Int? {
  self.keys
  .search(key)
  .map(index => index / @transcript_overview.TURNS_PER_PAGE)
}
