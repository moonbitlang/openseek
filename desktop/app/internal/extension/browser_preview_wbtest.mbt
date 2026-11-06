///|
async test "browser preview mappings follow tab close, page reload and window teardown" {
  let dir = @fs.tmpdir(prefix="seekmoon-browser-preview-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/index.html"
  @fs.write_file(path, "<h1>Local preview</h1>")
  let views = BrowserViews()
  @async.with_task_group(group => {
    group.spawn_bg(() => views.run_previews())
    let first = views.previews.open(1, path)
    let second = views.previews.open(2, path)
    let _ = views.close({ id: 1, })
    let (response, _) = @http.get(first)
    assert_eq(response.code, 404)
    let (response, _) = @http.get(second)
    assert_eq(response.code, 200)
    views.close_all()
    let (response, _) = @http.get(second)
    assert_eq(response.code, 404)
    let third = views.previews.open(3, path)
    views.window_closed()
    let (response, _) = @http.get(third)
    assert_eq(response.code, 404)
    group.return_immediately(())
  })
}
