///|
async test "standalone script checks do not require or inherit a module" {
  let dir = @fs.tmpdir(prefix="openseek-script-scope-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir).resolve()
  let scripts = root.join("scripts")
  @fs.mkdir(scripts.to_string())
  let file = scripts.join("-run.mbtx")
  guard moon_cli_scope(root, file) is Some(script) else {
    fail("a standalone script must work without a module")
  }
  assert_true(script is Script(path) && path == file)
  assert_eq(script.cwd(), scripts)
  assert_eq(script.check_args(), ["check", "--output-json", file.to_string()])
  assert_true(moon_cli_scope(root, scripts.join("lib.mbt")) is None)
  @fs.write_file(
    root.join("moon.mod").to_string(),
    "name = \"test/module\"",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    scripts.join("moon.pkg").to_string(),
    "",
    create_mode=CreateOrTruncate,
  )
  assert_true(moon_cli_scope(root, file) == Some(script))
  guard moon_cli_scope(root, scripts.join("lib.mbt")) is Some(module_scope) else {
    fail("ordinary source must still check its module")
  }
  assert_eq(module_scope.cwd(), root)
  assert_eq(module_scope.check_args(), ["check", "--output-json"])
  // The actual diagnostic cache must distinguish all three check owners.
  let state = MoonCliState("unused")
  state.published.set(script, [file])
  state.published.set(module_scope, [scripts.join("lib.mbt")])
  guard moon_cli_scope(root, scripts.join("other.mbtx")) is Some(other) else {
    fail("expected sibling script scope")
  }
  state.published.set(other, [])
  assert_eq(state.published.get(script), Some([file]))
  assert_eq(state.published.get(module_scope), Some([scripts.join("lib.mbt")]))
}
