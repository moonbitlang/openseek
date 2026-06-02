///|
test "@terminal_size.TerminalSize::new falls back to defaults for unknown dimensions" {
  let normalized = @terminal_size.TerminalSize::new(rows=0, cols=-3)
  inspect(normalized.rows(), content="24")
  inspect(normalized.cols(), content="80")
  let kept = @terminal_size.TerminalSize::new(rows=30, cols=100)
  inspect(kept.rows(), content="30")
  inspect(kept.cols(), content="100")
  let fallback = @terminal_size.TerminalSize::default()
  inspect(fallback.rows(), content="24")
  inspect(fallback.cols(), content="80")
}
