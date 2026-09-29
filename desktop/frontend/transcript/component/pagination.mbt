///|
/// Row bounds retain global indices so local turn anchors and assistant step
/// numbers do not change when a different page is mounted.
priv struct PageRows {
  page : @transcript_overview.Page
  start : Int
  end : Int
}

///|
fn Input::page_rows(self : Input, index : Int?) -> PageRows {
  let starts : Array[Int] = []
  for index, row in self.items {
    if row.item.kind is User(..) {
      starts.push(index)
    }
  }
  let page = @transcript_overview.Page::of(starts.length(), index?)
  {
    page,
    // Notices before the first prompt belong to the first page.
    start: if page.start == 0 {
      0
    } else {
      starts[page.start]
    },
    end: starts.get(page.end).unwrap_or(self.items.length()),
  }
}

///|
fn Input::page_for_turn(
  self : Input,
  key : @transcript_overview.TurnKey,
) -> Int? {
  let mut turn = 0
  for index, row in self.items {
    if row.item.kind is User(..) {
      if @transcript_overview.TurnKey::of(row.item, index~) == key {
        return Some(turn / @transcript_overview.TURNS_PER_PAGE)
      }
      turn += 1
    }
  }
  None
}

///|
/// Explicit navigation unpins even at an old page's bottom. The overview
/// stays complete; only the selected page's message branches are mounted.
fn Model::select_page(
  self : Model,
  input : Input,
  index : Int,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let rows = input.page_rows(Some(index))
  let active = input.items
    .get(rows.start)
    .bind(row => {
      if row.item.kind is User(..) {
        Some(@transcript_overview.TurnKey::of(row.item, index=rows.start))
      } else {
        None
      }
    })
  (
    {
      ..self,
      page: Some(rows.page.index),
      pinned: false,
      overview: { hover: None, active, },
    },
    @cmd.batch([
      render_rows_once_after_mount(),
      restore_scroll_after_render(0),
      report_visible_turn_after_render(emit, current=active),
      reveal_active_overview_tick(),
    ]),
  )
}
