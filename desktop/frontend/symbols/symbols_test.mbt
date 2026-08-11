///|
test "workspace symbols decode once into viewer coordinates" {
  let symbols = @symbols.decode({
    symbols: [
      {
        name: "parse_hover",
        kind: Some(12),
        container: Some("Lsp"),
        path: "a/b.mbt",
        range: { start: { line: 4, col: 2 }, end: { line: 4, col: 13 } },
      },
      {
        name: "",
        kind: None,
        container: None,
        path: "ignored.mbt",
        range: { start: { line: 0, col: 0 }, end: { line: 0, col: 0 } },
      },
    ],
  })
  assert_eq(symbols.length(), 1)
  assert_eq(symbols[0].name, "parse_hover")
  assert_eq(symbols[0].kind, Some(12))
  assert_eq(symbols[0].range, Range(5, 3, 5, 14))
  assert_eq(symbols[0].detail(), "Lsp · a/b.mbt:5")
}
