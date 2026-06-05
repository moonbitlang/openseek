///|
test "viewport remembers stale frame footprint after resize invalidates frame" {
  let viewport = Viewport::{
    size: TerminalSize(rows=10, cols=80),
    geometry: @geometry.Geometry::new(top=6, height=4),
    cache: Drawn(
      @surface.Surface::new(
        width=80,
        rows=[
          @surface.Line::new([]),
          @surface.Line::new([]),
          @surface.Line::new([]),
          @surface.Line::new([]),
          @surface.Line::new([]),
        ],
        cursor=@surface.Cursor::new(row=1, col=0),
      ),
    ),
  }
  viewport.set_size(TerminalSize(rows=8, cols=40))
  let (stale_top, stale_height) = match viewport.cache {
    Stale(top~, height~) => (top, height)
    _ => (-1, -1)
  }
  inspect(stale_top, content="6")
  inspect(stale_height, content="5")
  inspect(viewport.top(), content="5")
  inspect(
    viewport.cache.placed_surface(live_top=viewport.top()) is None,
    content="true",
  )
}

///|
test "terminal cursor comparison includes viewport top" {
  let rows = [@surface.Line::new([]), @surface.Line::new([])]
  let left = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=1, col=3),
  )
  let same = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=0, col=3),
  )
  let moved_row = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=1, col=3),
  )
  let moved_col = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=0, col=4),
  )
  let left = PlacedSurface::{ surface: left, top: 4 }
  let same = PlacedSurface::{ surface: same, top: 5 }
  let moved_row = PlacedSurface::{ surface: moved_row, top: 5 }
  let moved_col = PlacedSurface::{ surface: moved_col, top: 5 }
  inspect(left.same_terminal_cursor(same), content="true")
  inspect(left.same_terminal_cursor(moved_row), content="false")
  inspect(left.same_terminal_cursor(moved_col), content="false")
}
