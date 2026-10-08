///|
test "prepared folding shares structural ranges but owns collapse state per view and invalidates by version/options" {
  let model = test_model(
    "fn f() -> Unit {\n  let x = 1\n}\ntail",
    language_id="moonbit",
  )
  let a = CodeEditorWidget::CodeEditorWidget()
  let b = CodeEditorWidget::CodeEditorWidget()
  a.set_model(Some(model))
  a.fold_top_level()
  assert_true(a.prepared_folding(model) is Some(_))
  b.set_model(Some(model))
  let a_regions = attached_folding_model(a).get_regions_inside(None)
  let b_regions = attached_folding_model(b).get_regions_inside(None)
  assert_true(a_regions[0].is_collapsed())
  assert_false(b_regions[0].is_collapsed())
  b.fold_top_level()
  assert_true(
    attached_folding_model(b).get_regions_inside(None)[0].is_collapsed(),
  )
  a.set_model(None)
  b.set_model(None)
  model.set_value("fn changed() -> Unit {\n  let y = 2\n}\ntail")
  assert_true(a.prepared_folding(model) is None)
  a.set_model(Some(model))
  a.fold_top_level()
  assert_true(a.prepared_folding(model) is Some(_))
  b.update_options(b.get_options().with_tab_size(8))
  assert_true(b.prepared_folding(model) is None)
  a.set_model(None)
  b.set_model(None)
  model.dispose()
  assert_true(prepared_folding.get(model.identity()) is None)
  a.dispose()
  b.dispose()
}
