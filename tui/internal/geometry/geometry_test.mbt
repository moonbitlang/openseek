///|
test "@geometry.clamp_height clamps into 1..=rows" {
  let size = @terminal_size.TerminalSize::new(rows=10, cols=80)
  inspect(@geometry.clamp_height(size, height=0), content="1")
  inspect(@geometry.clamp_height(size, height=4), content="4")
  inspect(@geometry.clamp_height(size, height=99), content="10")
}

///|
test "@geometry.calculate_max_top leaves room for height and floors at row 1" {
  let size = @terminal_size.TerminalSize::new(rows=10, cols=80)
  inspect(@geometry.calculate_max_top(size, 4), content="7")
  inspect(@geometry.calculate_max_top(size, 10), content="1")
  // Live area taller than the screen still starts at row 1.
  inspect(@geometry.calculate_max_top(size, 20), content="1")
}

///|
test "@geometry.clamp_top clamps into 1..=@geometry.calculate_max_top" {
  let size = @terminal_size.TerminalSize::new(rows=10, cols=80)
  inspect(@geometry.clamp_top(size, height=4, top=0), content="1")
  inspect(@geometry.clamp_top(size, height=4, top=5), content="5")
  inspect(@geometry.clamp_top(size, height=4, top=99), content="7")
  // This is how the live area grows: holding `top` while the taller area still
  // fits, then raising it by just enough once it would overflow the bottom. On a
  // 12-row screen with the area at top 8, a height of 5 still fits (stays 8) but
  // a height of 6 does not (rises to 7).
  let screen = @terminal_size.TerminalSize::new(rows=12, cols=80)
  inspect(@geometry.clamp_top(screen, height=5, top=8), content="8")
  inspect(@geometry.clamp_top(screen, height=6, top=8), content="7")
}
