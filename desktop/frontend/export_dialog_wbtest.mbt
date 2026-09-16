///|
/// Native browser views z-order above all HTML, so the export dialog must
/// count as a covering overlay while it is open. The browser harness has no
/// native views, so only this predicate can prove they get hidden.
test "export modal covers native browser views while open" {
  let source : @protocol.SessionExportPayload = {
    session: "export-a",
    workspace: "/workspace",
    title: "Export A",
    archived: false,
  }
  let emit = test_dispatch()
  let base = test_model()
  assert_false(covering_overlay(base))
  let (_, opened) = update(emit, OpenExport(source), base)
  assert_true(covering_overlay(opened))
  let (_, closed) = update(emit, ExportDialog(Close), opened)
  assert_false(covering_overlay(closed))
}
