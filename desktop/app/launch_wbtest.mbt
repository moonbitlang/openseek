///|
test "release launches enable persistent browser state by default" {
  let matches = command.parse(argv=[])
  assert_true(single_instance_wanted(matches, development=false))
  assert_false(single_instance_wanted(matches, development=true))
}

///|
test "release single instance honors flags and environment without changing development launches" {
  for
    (argv, env, enabled) in [
      (["--single-instance"], {}, true),
      (["--no-single-instance"], {}, false),
      ([], { "OPENSEEK_DESKTOP_SINGLE_INSTANCE": "1" }, true),
      ([], { "OPENSEEK_DESKTOP_SINGLE_INSTANCE": "0" }, false),
      (["--single-instance"], { "OPENSEEK_DESKTOP_SINGLE_INSTANCE": "0" }, true),
      (
        ["--no-single-instance"],
        { "OPENSEEK_DESKTOP_SINGLE_INSTANCE": "1" },
        false,
      ),
    ] {
    let matches = command.parse(argv~, env~)
    assert_eq(single_instance_wanted(matches, development=false), enabled)
    assert_false(single_instance_wanted(matches, development=true))
  }
}
