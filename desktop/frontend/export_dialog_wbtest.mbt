///|
test "export modal opens once per click and covers native browser views" {
  let source : @protocol.SessionExportPayload = {
    session: "export-a",
    workspace: "/workspace",
    title: "Export A",
    archived: false,
  }
  let emit = test_dispatch()
  let base = test_model()
  let (_, first) = update(emit, OpenExport(source), base)
  let (_, again) = update(emit, OpenExport(source), base)
  assert_true(first.export_dialog == again.export_dialog)
  assert_true(first.export_dialog.is_open())
  assert_true(!base.export_dialog.is_open())
  assert_true(covering_overlay(first))
  let (_, closed) = update(emit, ExportDialog(Close), first)
  let (_, closed_again) = update(emit, ExportDialog(Close), first)
  assert_true(closed.export_dialog == closed_again.export_dialog)
  assert_true(!closed.export_dialog.is_open())
}
