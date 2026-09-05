///|
test "protected workspace source policy" {
  // The last two are files whose names merely START with a generated
  // directory's: only a whole path COMPONENT is treated as moon-managed.
  for
    guarded in [
      "/workspace/moon.mod", "/workspace/pkg/moon.pkg", "/workspace/pkg/main.mbt",
      "/workspace/pkg/_build.mbt", "/workspace/.mooncakes.mbt",
    ] {
    assert_true(
      @source_write_policy.is_protected_workspace_source_path(
        "/workspace", guarded,
      ),
      msg=guarded,
    )
  }
  assert_false(
    @source_write_policy.is_protected_workspace_source_path(
      "/workspace", "/workspace/backup-moon.mod",
    ),
  )
  for
    generated in [
      "/workspace/_build/wasm-gc/release/format/main.mbt", "/workspace/.mooncakes/moonbitlang/core/main.mbt",
      "/workspace/pkg/_build/main.mbt", "/workspace/scripts/.mooncakes/pkg/main.mbt",
    ] {
    assert_false(
      @source_write_policy.is_protected_workspace_source_path(
        "/workspace", generated,
      ),
    )
  }
  assert_true(
    @source_write_policy.is_protected_workspace_source_path(
      "C:\\repo", "C:\\repo\\main.mbt",
    ),
  )
  assert_false(
    @source_write_policy.is_protected_workspace_source_path(
      "C:\\repo", "C:\\repo\\_build\\main.mbt",
    ),
  )
}

///|
test "scratch lab containment policy" {
  assert_true(@source_write_policy.path_is_under_lab("/tmp/lab", "/tmp/lab"))
  assert_true(
    @source_write_policy.path_is_under_lab("/tmp/lab/pkg/main.mbt", "/tmp/lab"),
  )
  assert_false(@source_write_policy.path_is_under_lab("/tmp/lab2", "/tmp/lab"))
  assert_false(@source_write_policy.path_is_under_lab("/tmp/lab", "/"))
}
