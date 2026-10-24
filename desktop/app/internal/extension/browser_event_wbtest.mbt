///|
async test "closed views still clear native loading state without notifying the frontend" {
  let views = BrowserViews()
  views.view_event(3, LoadingChanged(is_loading=true))
  assert_true(views.loading.contains(3))
  views.view_event(3, Closed)
  assert_false(views.loading.contains(3))
}
