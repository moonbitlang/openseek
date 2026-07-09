///|
/// Full reset before a from-scratch redraw: drop any scroll region and text
/// style, then erase both the visible screen and the scrollback, leaving the
/// cursor at the home position.
async fn clear_screen_and_scrollback(tty : @tty.Tty) -> Unit {
  tty.reset_top_bottom_margins()
  tty.reset_style()
  tty.set_cursor_position(1, 1)
  tty.erase_display()
  tty.erase_scrollback()
  tty.set_cursor_position(1, 1)
}

///|
struct Viewport {
  mut size : @terminal_size.TerminalSize
  size_source : SizeSource
  // The live area's placement. Set once by `enter` (which anchors it at the
  // terminal cursor) and re-clamped on resize; a `Viewport` only exists once
  // its area has been placed.
  mut geometry : @geometry.Geometry
  // Diff/clear state for the live area: the last drawn surface (for row diffing)
  // or, once dropped, the footprint it left behind (for clearing). See
  // `FrameCache`.
  mut cache : FrameCache
}

///|
priv enum SizeSource {
  Ioctl
  Protocol
}

///|
priv struct EnterGeometry {
  size : @terminal_size.TerminalSize
  cursor_row : Int
  source : SizeSource
}

///|
/// The live area's start row.
fn Viewport::top(self : Viewport) -> Int {
  self.geometry.top()
}

///|
/// The live area's height in rows.
fn Viewport::height(self : Viewport) -> Int {
  self.geometry.height()
}

///|
/// Current trusted terminal width in columns.
pub fn Viewport::cols(self : Viewport) -> Int {
  self.size.cols()
}

///|
/// Current trusted terminal height in rows. The live area can never exceed this,
/// so the composer view uses it to bound previews.
pub fn Viewport::rows(self : Viewport) -> Int {
  self.size.rows()
}

///|
fn Viewport::bottom(self : Viewport) -> Int {
  self.geometry.bottom()
}

///|
fn Viewport::set_size(
  self : Viewport,
  size : @terminal_size.TerminalSize,
) -> Unit {
  if size.rows() != self.size.rows() || size.cols() != self.size.cols() {
    // Terminal resize can reflow rows away from their old physical footprint.
    // Resize rebuilds from semantic rows, so the cached frame must be dropped.
    self.cache = self.cache.invalidate(live_top=self.top())
  }
  self.size = size
  // Re-clamp the live area against the new dimensions so it stays on screen.
  self.set_geometry(top=self.geometry.top(), height=self.geometry.height())
}

///|
fn Viewport::set_geometry(self : Viewport, top~ : Int, height~ : Int) -> Unit {
  // Store the clamped values, never the caller's desired ones: a desired
  // `top`/`height` that no longer fits (terminal shrank, composer grew near the
  // bottom) is raised/shrunk to fit, so `bottom()` stays within `size.rows()`.
  let clamped_height = @geometry.clamp_height(self.size, height~)
  let clamped_top = @geometry.clamp_top(self.size, height=clamped_height, top~)
  self.geometry = @geometry.Geometry::new(
    top=clamped_top,
    height=clamped_height,
  )
}

///|
/// Read the ioctl terminal window size, falling back to the default if it can't
/// be queried (for example before the first `ioctl`). The value type itself
/// stays free of terminal IO.
pub fn read_terminal_size(tty : @tty.Tty) -> @terminal_size.TerminalSize {
  try tty.window_size() catch {
    _ => @terminal_size.default
  } noraise {
    size => TerminalSize(rows=size.rows, cols=size.cols)
  }
}

///|
fn cursor_position_fits_size(
  size : @terminal_size.TerminalSize,
  row~ : Int,
  col~ : Int,
) -> Bool {
  row >= 1 && row <= size.rows() && col >= 1 && col <= size.cols()
}

///|
fn terminal_geometry_error_message(
  ioctl_size : @terminal_size.TerminalSize,
  cursor_row~ : Int,
  cursor_col~ : Int,
  protocol_size? : @terminal_size.TerminalSize,
) -> String {
  let ioctl_rows = ioctl_size.rows()
  let ioctl_cols = ioctl_size.cols()
  if protocol_size is Some(size) {
    let protocol_rows = size.rows()
    let protocol_cols = size.cols()
    "terminal geometry is inconsistent: CPR cursor=\{cursor_row}x\{cursor_col}, ioctl=\{ioctl_rows}x\{ioctl_cols}, protocol=\{protocol_rows}x\{protocol_cols}"
  } else {
    "terminal geometry is inconsistent: CPR cursor=\{cursor_row}x\{cursor_col}, ioctl=\{ioctl_rows}x\{ioctl_cols}, protocol probe failed"
  }
}

///|
fn choose_enter_geometry_for_cursor(
  ioctl_size : @terminal_size.TerminalSize,
  cursor_row~ : Int,
  cursor_col~ : Int,
  protocol_size? : @terminal_size.TerminalSize,
) -> EnterGeometry raise {
  if cursor_position_fits_size(ioctl_size, row=cursor_row, col=cursor_col) {
    { size: ioctl_size, cursor_row, source: Ioctl }
  } else if protocol_size is Some(size) &&
    cursor_position_fits_size(size, row=cursor_row, col=cursor_col) {
    { size, cursor_row, source: Protocol }
  } else {
    fail(
      terminal_geometry_error_message(
        ioctl_size,
        cursor_row~,
        cursor_col~,
        protocol_size?,
      ),
    )
  }
}

///|
const SaveCursor : String = "\u{1b}7"

///|
const RestoreCursor : String = "\u{1b}8"

///|
const ProtocolProbeRow : Int = 9999

///|
const ProtocolProbeCol : Int = 9999

///|
async fn probe_terminal_protocol_size(
  tty : @tty.Tty,
  timeout_ms~ : Int,
) -> @terminal_size.TerminalSize? {
  tty.write(SaveCursor)
  try {
    tty.set_cursor_position(ProtocolProbeRow, ProtocolProbeCol)
    tty.query_cursor_position(timeout_ms~)
  } catch {
    error => {
      tty.write(RestoreCursor)
      raise error
    }
  } noraise {
    position => {
      tty.write(RestoreCursor)
      if position is Some(position) && position.row >= 1 && position.col >= 1 {
        Some(TerminalSize(rows=position.row, cols=position.col))
      } else {
        None
      }
    }
  }
}

///|
async fn resolve_enter_geometry(
  tty : @tty.Tty,
  ioctl_size : @terminal_size.TerminalSize,
  timeout_ms~ : Int,
) -> EnterGeometry {
  if tty.query_cursor_position(timeout_ms~) is Some(position) {
    if cursor_position_fits_size(ioctl_size, row=position.row, col=position.col) {
      { size: ioctl_size, cursor_row: position.row, source: Ioctl }
    } else {
      let protocol_size = probe_terminal_protocol_size(tty, timeout_ms~)
      choose_enter_geometry_for_cursor(
        ioctl_size,
        cursor_row=position.row,
        cursor_col=position.col,
        protocol_size?,
      )
    }
  } else {
    { size: ioctl_size, cursor_row: ioctl_size.rows(), source: Ioctl }
  }
}

///|
/// Re-query the ioctl terminal window size and re-clamp the live area to it when
/// this viewport still trusts ioctl.
///
/// When the dimensions actually change the cached frame is invalidated (a resize
/// can reflow rows off their old footprint) and the live area is re-clamped to
/// stay on screen. Protocol-sized viewports deliberately skip this synchronous
/// path because the ioctl value is already known stale for their terminal chain.
pub fn Viewport::refresh_size(self : Viewport, tty : @tty.Tty) -> Unit {
  match self.size_source {
    Ioctl => self.set_size(read_terminal_size(tty))
    Protocol => ()
  }
}

///|
/// Refresh terminal dimensions after an explicit resize event.
///
/// Ioctl-sized viewports can trust the size carried by the event. Protocol-sized
/// viewports cannot: that event is still ioctl-derived, so they probe through
/// the same coordinated `Tty` reader. `read_tty_events` is blocked on the command
/// queue while handling this resize, and `Tty::query_cursor_position` preserves
/// user input it reads while waiting for the terminal response.
pub async fn Viewport::refresh_size_after_resize(
  self : Viewport,
  tty : @tty.Tty,
  rows~ : Int,
  cols~ : Int,
  timeout_ms~ : Int,
) -> Unit {
  match self.size_source {
    Ioctl => self.set_size(TerminalSize(rows~, cols~))
    Protocol =>
      if probe_terminal_protocol_size(tty, timeout_ms~) is Some(size) {
        self.set_size(size)
      } else {
        fail(
          "terminal geometry is inconsistent: protocol viewport resize could not probe screen size",
        )
      }
  }
}

///|
async fn erase_cursor_row(tty : @tty.Tty) -> Unit {
  // `erase_line_all` clears the row but leaves the cursor column unchanged.
  //
  // Without the carriage return:
  //
  //   before: |old prompt text              |
  //                         ^
  //   clear:  |                             |
  //                         ^
  //   write:  |                   > new text|
  //
  // `\r` moves the cursor to column 1 first, so the next render is anchored at
  // the left edge:
  //
  //   after \r: |                             |
  //             ^
  //   write:    |> new text                   |
  tty.write("\r")
  tty.erase_line_all()
}

///|
async fn apply_style(tty : @tty.Tty, style : @style.Style) -> Unit {
  if style.foreground != Default {
    tty.set_foreground(style.foreground)
  }
  if style.background != Default {
    tty.set_background(style.background)
  }
  if style.underline {
    tty.set_underline()
  }
}

///|
async fn write_span(tty : @tty.Tty, span : @surface.Span) -> Unit {
  apply_style(tty, span.style())
  tty.write(span.text())
  tty.reset_style()
}

///|
/// Run `body` with terminal auto-wrap disabled, restoring it even if drawing
/// raises.
async fn without_auto_wrap(tty : @tty.Tty, body : async () -> Unit) -> Unit {
  tty.disable_auto_wrap()
  try body() catch {
    error => {
      tty.enable_auto_wrap()
      raise error
    }
  } noraise {
    _ => tty.enable_auto_wrap()
  }
}

///|
/// Draw one surface line at the current cursor. Auto-wrap is controlled by the
/// caller: live redraw batches disable it around their loops, while scrollback
/// insertion leaves normal terminal wrapping in place.
async fn draw_surface_line_at_cursor(
  tty : @tty.Tty,
  line : @surface.Line?,
) -> Unit {
  erase_cursor_row(tty)
  if line is Some(line) {
    for span in line.spans() {
      write_span(tty, span)
    }
  }
}

///|
async fn draw_surface_line_at(
  tty : @tty.Tty,
  row : Int,
  line : @surface.Line?,
) -> Unit {
  tty.set_cursor_position(row, 1)
  draw_surface_line_at_cursor(tty, line)
}

///|
/// Repaint every terminal row in `top..=bottom` straight from `frame`, with no
/// diffing. Rows past the frame's own height resolve to `None` and are cleared.
/// The caller controls auto-wrap around the batch.
async fn draw_frame_rows(
  tty : @tty.Tty,
  frame : PlacedSurface,
  top~ : Int,
  bottom~ : Int,
) -> Unit {
  for row in top..<=bottom {
    draw_surface_line_at(tty, row, frame.line_at_terminal_row(row~))
  }
}

///|
/// Run `body` with the terminal's scroll region (DECSTBM margins) temporarily
/// restricted to rows `top..=bottom`, then restore the full-screen region.
///
/// Inside the region, line feeds and reverse-indexes scroll only those rows and
/// leave everything outside the margins fixed. This is the primitive every
/// scrollback trick below is built on. The margins are always reset, even if
/// `body` raises, so a failed write can never leave the terminal in a clipped
/// scroll region.
async fn with_scroll_region(
  tty : @tty.Tty,
  top : Int,
  bottom : Int,
  body : async () -> Unit,
) -> Unit {
  tty.set_top_bottom_margins(top, bottom)
  try body() catch {
    error => {
      tty.reset_top_bottom_margins()
      raise error
    }
  } noraise {
    _ => tty.reset_top_bottom_margins()
  }
}

///|
/// Make room for a taller live area by scrolling committed rows up into the
/// terminal's native scrollback.
///
/// With the region restricted to `1..=scrollback_bottom`, writing one newline at
/// its bottom row pushes the whole region up by one line — the top row leaves
/// the region into scrollback. Repeating `rows` times frees `rows` rows directly
/// above the new (higher) live-area top.
///
/// Returns whether it scrolled the whole screen (the fallback when there are
/// fewer than two rows above the live area, where a scroll region is invalid),
/// which shifts the live frame and so requires the caller to repaint uncached.
async fn scroll_scrollback_up_for_growth(
  tty : @tty.Tty,
  old : @geometry.Geometry,
  new_top~ : Int,
  screen_bottom~ : Int,
) -> Bool {
  // old:                                     new:
  //
  // +------------+                           +------------+
  // | scrollback |                           | scrollback |
  // | scrollback |                           | scrollback |
  // | scrollback |                           +------------+
  // | scrollback |                new top -> +------------+
  // +------------+ <- scrollback_bottom      | composer   |
  // +------------+ <- old.top                | composer   |
  // | composer   |                           | composer   |
  // +------------+                           +------------+
  //
  // Here we need to make rooms for 2 rows. Since top is 1-based line number from the top
  // of the terminal, we can obtain the number of rows to make by old.top - new_top.
  //
  let rows = old.top() - new_top
  guard rows > 0 else { return false }
  let scrollback_bottom = old.top() - 1
  if scrollback_bottom >= 2 {
    // At least two rows above: scroll them up within a DECSTBM region so the
    // oldest spills into native scrollback and the live frame stays put.
    with_scroll_region(tty, 1, scrollback_bottom, () => {
      tty.set_cursor_position(scrollback_bottom, 1)
      tty.write("\r\n".repeat(rows))
    })
    false
  } else {
    // One row above (a region of < 2 rows is an invalid DECSTBM, silently
    // ignored): scroll the whole screen up to push that row into native
    // scrollback. This also shifts the live frame, so report it — the caller
    // must repaint uncached rather than diff against the old position.
    tty.set_cursor_position(screen_bottom, 1)
    tty.write("\r\n".repeat(rows))
    true
  }
}

///|
/// Paint the first frame: draw every row of the new area (there is nothing on
/// screen yet to diff against) and place the cursor. The area comes straight
/// from `set_geometry`, so it already fits the screen — no span clamping needed.
async fn enter_placed_surface_rows(
  tty : @tty.Tty,
  frame : PlacedSurface,
) -> Unit {
  let height = frame.surface.height()
  // No need to hide cursor + show cursor if there is nothing new to draw.
  guard height > 0 else { return }
  tty.hide_cursor()
  // Pair the hide with a guaranteed show. This is the first frame, so a draw
  // failure here unwinds before any viewport exists for `leave` to restore —
  // leaving the cursor hidden would break `with_ui`'s restore-on-error promise.
  try {
    without_auto_wrap(tty, () => {
      draw_frame_rows(tty, frame, top=frame.top, bottom=frame.top + height - 1)
    })
    place_cursor(tty, frame)
  } catch {
    error => {
      tty.show_cursor()
      raise error
    }
  }
}

///|
/// Redraw over a previous frame: repaint only the rows that changed within the
/// union of the old and new footprints, then move the cursor.
async fn Viewport::redraw_placed_surface_rows(
  self : Viewport,
  tty : @tty.Tty,
  old_frame : PlacedSurface,
  new_frame : PlacedSurface,
) -> Unit {
  let draw_top = @cmp.maximum(@cmp.minimum(old_frame.top, new_frame.top), 1)
  let old_bottom = old_frame.top + old_frame.surface.height() - 1
  let new_bottom = new_frame.top + new_frame.surface.height() - 1
  let draw_bottom = @cmp.minimum(
    @cmp.maximum(old_bottom, new_bottom),
    self.size.rows(),
  )
  guard draw_top <= draw_bottom else { return }
  let mut rows_changed = false
  without_auto_wrap(tty, () => {
    for row in draw_top..<=draw_bottom {
      let old_line = old_frame.line_at_terminal_row(row~)
      let new_line = new_frame.line_at_terminal_row(row~)
      if old_line != new_line {
        if !rows_changed {
          tty.hide_cursor()
          rows_changed = true
        }
        draw_surface_line_at(tty, row, new_line)
      }
    }
  })
  let cursor_changed = !old_frame.same_terminal_cursor(new_frame)
  if rows_changed {
    place_cursor(tty, new_frame)
  } else if cursor_changed {
    tty.set_cursor_position(
      new_frame.cursor_terminal_row(),
      new_frame.cursor_terminal_col(),
    )
  }
}

///|
/// Redraw when the previous frame content is unknown: repaint the whole required
/// span, including rows below the new frame that may still contain stale text.
async fn Viewport::redraw_uncached_placed_surface_rows(
  self : Viewport,
  tty : @tty.Tty,
  old : @geometry.Geometry,
  new_frame : PlacedSurface,
) -> Unit {
  let draw_top = @cmp.maximum(@cmp.minimum(old.top(), new_frame.top), 1)
  let draw_bottom = self.size.rows()
  guard draw_top <= draw_bottom else { return }
  tty.hide_cursor()
  without_auto_wrap(tty, () => {
    draw_frame_rows(tty, new_frame, top=draw_top, bottom=draw_bottom)
  })
  place_cursor(tty, new_frame)
}

///|
/// Place the terminal cursor at a placed surface's cursor.
async fn place_cursor(tty : @tty.Tty, frame : PlacedSurface) -> Unit {
  tty.show_cursor()
  tty.set_cursor_position(
    frame.cursor_terminal_row(),
    frame.cursor_terminal_col(),
  )
}

///|
/// Rebuilds the DECSTBM screen after resize from semantic transcript rows.
///
/// The primary-screen scrollback is treated as a terminal cache here. Resize can
/// reflow that cache, so this path clears it, draws the live frame at the top,
/// then lets transcript insertion push it down until the screen is full.
pub async fn Viewport::replay_scrollback(
  self : Viewport,
  tty : @tty.Tty,
  scrollback~ : Array[@surface.Line],
  surface~ : @surface.Surface,
) -> Unit {
  tty.hide_cursor()
  clear_screen_and_scrollback(tty)
  // `set_geometry` clamps the height to the screen itself.
  self.set_geometry(top=1, height=surface.height())
  let surface = surface.with_max_rows(self.height())
  let frame = PlacedSurface::{ surface, top: self.top() }
  let bottom = self.bottom()
  without_auto_wrap(tty, () => {
    draw_frame_rows(tty, frame, top=self.top(), bottom~)
    if bottom < self.size.rows() {
      for row in (bottom + 1)..<=self.size.rows() {
        draw_surface_line_at(tty, row, None)
      }
    }
  })
  self.cache = Drawn(frame.surface)
  self.insert_before(tty, scrollback)
  // `insert_before` shifts the live area down to open room for the transcript
  // rows — and when the rebuilt area leaves < 2 rows above it, it scrolls the
  // live frame off its drawn position and drops the cache. So repaint the frame
  // at its current position rather than only moving the cursor; `redraw` does a
  // full repaint when the cache was invalidated and a no-op diff otherwise.
  self.redraw(tty, surface)
}

///|
/// Build and draw the live area for the first time, anchoring it at the
/// terminal cursor. The surface is built only after the trusted size is known,
/// so the first frame uses the same geometry that `enter` places on screen.
///
/// Anchor at the row the cursor currently sits on — where the shell left it when
/// the app started — so committed output above stays put. When the cursor is
/// near the bottom (say row 23 of 24 while the area needs 7 rows) the live area
/// would run off the screen, so we first scroll the existing content up into the
/// terminal's native scrollback to open room beneath the anchor, then place the
/// area at `calculate_max_top` (here 18). Without that scroll the area would be
/// drawn straight over the lines above the cursor, destroying them. When the
/// cursor position can't be queried, assume the worst case (cursor on the last
/// row). If the cursor position contradicts the ioctl size, probe the terminal
/// protocol for a trustworthy screen size and fail clearly if that also cannot
/// explain the cursor. The cursor queries are the blocking reads, hence
/// `timeout_ms`.
pub async fn Viewport::enter(
  tty : @tty.Tty,
  size~ : @terminal_size.TerminalSize,
  surface~ : (Int, Int) -> @surface.Surface,
  timeout_ms~ : Int,
) -> Viewport {
  let enter_geometry = resolve_enter_geometry(tty, size, timeout_ms~)
  let size = enter_geometry.size
  let surface = surface(size.cols(), size.rows())
  let height = @geometry.clamp_height(size, height=surface.height())
  let cursor_row = enter_geometry.cursor_row
  let top = @geometry.clamp_top(size, height~, top=cursor_row)
  // The live area spans `cursor_row ..= cursor_row + height - 1`; anything past
  // the last row must be made by scrolling, not by drawing over the lines above.
  let overflow = cursor_row + height - 1 - size.rows()
  if overflow > 0 {
    tty.set_cursor_position(size.rows(), 1)
    tty.write("\r\n".repeat(overflow))
  }
  let geometry = @geometry.Geometry::new(top~, height~)
  let surface = surface.with_max_rows(geometry.height())
  let frame = PlacedSurface::{ surface, top: geometry.top() }
  enter_placed_surface_rows(tty, frame)
  { size, size_source: enter_geometry.source, geometry, cache: Drawn(surface) }
}

///|
/// Redraw `surface` in place over the previous frame, holding the previous `top`.
///
/// Readline-style ownership: growth uses the blank rows below first and only
/// pushes upward once the taller area would overflow the screen bottom;
/// shrinking holds `top` too. Clamping the old top to `calculate_max_top` is
/// exactly that — it keeps `top` put while the area fits and raises it by just
/// enough when it would not.
pub async fn Viewport::redraw(
  self : Viewport,
  tty : @tty.Tty,
  surface : @surface.Surface,
) -> Unit {
  // The previous frame/cache must be read before set_geometry moves the live
  // area.
  let old_top = self.top()
  let old_cache = self.cache
  let height = @geometry.clamp_height(self.size, height=surface.height())
  let top = @geometry.clamp_top(self.size, height~, top=self.top())
  self.set_geometry(top~, height~)
  let surface = surface.with_max_rows(self.height())
  let new_frame = PlacedSurface::{ surface, top: self.top() }
  match old_cache {
    Drawn(old_surface) => {
      let old_frame = PlacedSurface::{ surface: old_surface, top: old_top }
      let old = @geometry.Geometry::new(
        top=old_top,
        height=old_surface.height(),
      )
      let scrolled_screen = scroll_scrollback_up_for_growth(
        tty,
        old,
        new_top=new_frame.top,
        screen_bottom=self.size.rows(),
      )
      // A whole-screen growth scroll shifts the live frame off its cached
      // position, so a row-level diff would compare against the wrong screen
      // contents — repaint uncached in that case.
      if scrolled_screen {
        self.redraw_uncached_placed_surface_rows(tty, old, new_frame)
      } else {
        self.redraw_placed_surface_rows(tty, old_frame, new_frame)
      }
    }
    Stale(top~, height~) => {
      let old = @geometry.Geometry::new(top~, height~)
      let _ = scroll_scrollback_up_for_growth(
        tty,
        old,
        new_top=new_frame.top,
        screen_bottom=self.size.rows(),
      )
      self.redraw_uncached_placed_surface_rows(tty, old, new_frame)
    }
  }
  self.cache = Drawn(new_frame.surface)
}

///|
/// Open blank rows directly above the live area by scrolling it down, bounded by
/// the blank space below it so committed scrollback is never overwritten.
/// Returns the live-area top from before the shift.
///
/// With the region restricted to `top..=size.rows`, a reverse-index at the top
/// margin scrolls those rows down by one, inserting a blank row at `top`.
/// Repeating opens the requested space; the live area then sits `shift` rows
/// lower.
async fn Viewport::shift_down_for_insert(
  self : Viewport,
  tty : @tty.Tty,
  lines~ : Int,
) -> Int {
  let top = self.top()
  let space = self.size.rows() - self.bottom()
  let available = @cmp.maximum(space, 0)
  let shift = @cmp.minimum(lines, available)
  if shift > 0 {
    with_scroll_region(tty, top, self.size.rows(), () => {
      tty.set_cursor_position(top, 1)
      for _ in 0..<shift {
        tty.reverse_index()
      }
    })
    self.set_geometry(top=top + shift, height=self.height())
  }
  top
}

///|
/// Insert rendered transcript rows above the viewport.
///
/// `cursor_row` controls where the first line feed starts. Normal append uses
/// the row above the old viewport so new blank space is filled. Resize replay
/// uses the row above the rebuilt viewport so transcript rows are bottom-aligned
/// before the live frame is redrawn.
async fn Viewport::insert_lines_before(
  self : Viewport,
  tty : @tty.Tty,
  lines : Array[@surface.Line],
  cursor_row~ : Int,
) -> Unit {
  guard lines.length() > 0 else { return }
  tty.enable_auto_wrap()
  let scrollback_bottom = self.top() - 1
  if scrollback_bottom >= 2 {
    // At least two rows above the live area: draw the rows inside a
    // `1..=scrollback_bottom` region so each `\r\n` scrolls earlier transcript up
    // into native scrollback as new rows arrive.
    with_scroll_region(tty, 1, scrollback_bottom, () => {
      let start = if cursor_row < 1 {
        if lines.get(0) is Some(line) {
          tty.set_cursor_position(1, 1)
          draw_surface_line_at_cursor(tty, Some(line))
          1
        } else {
          0
        }
      } else {
        tty.set_cursor_position(cursor_row, 1)
        0
      }
      for index in start..<lines.length() {
        tty.write("\r\n")
        draw_surface_line_at_cursor(tty, Some(lines[index]))
      }
    })
  } else if scrollback_bottom == 1 {
    // Exactly one row above the live area (e.g. `shift_down_for_insert` opened a
    // row and moved the area to row 2). A 1-row scroll region is an invalid
    // DECSTBM, so scroll the earlier rows off the top of the screen into native
    // scrollback, but keep the last row drawn at row 1 so the newest appended
    // item stays visible just above the composer. The displaced live rows are
    // restored by the caller's redraw (the cache is invalidated for `top <= 2`).
    for index in 0..<(lines.length() - 1) {
      draw_surface_line_at(tty, 1, Some(lines[index]))
      tty.set_cursor_position(self.size.rows(), 1)
      tty.write("\r\n")
    }
    draw_surface_line_at(tty, 1, Some(lines[lines.length() - 1]))
  } else {
    // No row above the live area (`top == 1`, the composer fills the screen):
    // there is nowhere to show a committed row, so draw each at row 1 and scroll
    // the whole screen up to push it into native scrollback. The caller's redraw
    // repaints the displaced frame.
    for line in lines {
      draw_surface_line_at(tty, 1, Some(line))
      tty.set_cursor_position(self.size.rows(), 1)
      tty.write("\r\n")
    }
  }
}

///|
/// Commit transcript rows above the live area, scrolling earlier rows into
/// native scrollback.
///
/// The area is first shifted down to open blank rows above it, the lines are
/// drawn into a scroll region so older transcript spills into scrollback, then
/// the cursor is restored to the live frame.
pub async fn Viewport::insert_before(
  self : Viewport,
  tty : @tty.Tty,
  lines : Array[@surface.Line],
) -> Unit {
  let old_top = self.shift_down_for_insert(tty, lines=lines.length())
  self.insert_lines_before(tty, lines, cursor_row=old_top - 1)
  if self.cache.placed_surface(live_top=self.top()) is Some(frame) {
    place_cursor(tty, frame)
  }
  // With fewer than two rows above the live area (`top <= 2`, e.g. a screen
  // nearly filled by the composer), `insert_lines_before` used the full-screen
  // scroll path, which shifts the live rows up off their cached positions. The
  // cached surface no longer matches the screen, so drop it: the next redraw
  // must repaint the whole span instead of diffing against it, otherwise the
  // displaced rows are skipped and transcript text stays embedded in the live
  // area.
  if self.top() <= 2 && lines.length() > 0 {
    self.cache = self.cache.invalidate(live_top=self.top())
  }
}

///|
/// Tear down the live area and hand the terminal back to the shell.
///
/// Restores the full-screen scroll region, default text style, autowrap, and
/// cursor visibility, then moves the cursor below the area and emits a newline
/// so the shell prompt starts on a fresh line beneath the committed output.
pub async fn Viewport::leave(self : Viewport, tty : @tty.Tty) -> Unit {
  tty.reset_top_bottom_margins()
  tty.reset_style()
  tty.enable_auto_wrap()
  tty.show_cursor()
  tty.set_cursor_position(self.bottom(), 1)
  tty.write("\r\n")
}
