///|
test "a workflow wasm engine uses moonrun with a module and argument fence" {
  let (command, prefix) = @setup.workflow_launch(
    "/cache/with spaces/openseek.wasm",
  )
  assert_eq(command, "moonrun")
  assert_eq(prefix, ["/cache/with spaces/openseek.wasm", "--"])
}

///|
test "other workflow executable paths need no launch prefix" {
  for
    exe in [
      "/usr/local/bin/openseek", "sh", "openseek", "/build/wasm/openseek", "/build/openseek.wasm.bak",
    ] {
    let (command, prefix) = @setup.workflow_launch(exe)
    assert_eq(command, exe)
    assert_eq(prefix, [])
  }
}
