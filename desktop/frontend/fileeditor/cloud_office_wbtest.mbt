///|
test "Cloud Office selections keep their URI identity and project workspace-relative model references" {
  let (base, _, old_path) = office_selection_fixture()
  let ctx = cloud_ctx("account", "session", 1)
  let path = ctx.resource(Relative("docs/report.docx")).unwrap()
  let ctx = { ..ctx, active_file: Some(path), open_files: [path], }
  let old = base.docs[old_path]
  let state = {
    ..base,
    owner: Some(ctx.owner),
    cloud_epoch: Some(1),
    docs: Map([(path, old)]),
  }
  let offered = state
    .offer_office_selection(
      ctx,
      office_selection_raw(path.path, "Selected passage"),
    )
    .unwrap()
  let preview = offered.pending_office_selection(ctx).unwrap()
  assert_eq(preview.owner, ctx.owner)
  assert_eq(preview.path, path)
  let materialized = @json.parse(
    preview.materialized_selection("Explain this").unwrap(),
  )
  assert_true(
    materialized
    is {
      "source": { "file": "docs/report.docx", .. },
      "comment": "Explain this",
      ..
    },
  )
  assert_eq(preview.summary.file, path.path)
  let other = {
    ..ctx,
    owner: @interop.Cloud(account="other", session="session"),
  }
  assert_true(offered.pending_office_selection(other) is None)
  let stale = {
    ..offered,
    cloud_surface_epoch: offered.cloud_surface_epoch + 1,
  }
  assert_true(stale.pending_office_selection(ctx) is None)
}
