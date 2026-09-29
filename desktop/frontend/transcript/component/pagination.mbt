///|
/// Row bounds retain global indices so local turn anchors and assistant step
/// numbers do not change when a different page is mounted.
priv struct PageRows {
  page : @transcript_overview.Page
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
fn TurnIndex::page_rows(self : TurnIndex, index : Int?) -> PageRows {
  let page = @transcript_overview.Page::of(self.starts.length(), index?)
  {
    page,
    // Notices before the first prompt belong to the first page.
    start: if page.start == 0 {
      0
    } else {
      self.starts[page.start]
    },
    end: self.starts.get(page.end).unwrap_or(self.row_count),
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

///|
/// Explicit navigation unpins even at an old page's bottom. The overview
/// stays complete; only the selected page's message branches are mounted.
fn Model::select_page(
  self : Model,
  turns : TurnIndex,
  index : Int,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let rows = turns.page_rows(Some(index))
  let active = turns.keys.get(rows.page.start)
  (
    {
      ..self,
      page: Some(rows.page.index),
      pinned: false,
      overview: { hover: None, active, },
    },
    @cmd.batch([
      measure_page_after_render(),
      restore_scroll_after_render(0),
      report_visible_turn_after_render(emit, current=active),
      reveal_active_overview_tick(),
    ]),
  )
}
