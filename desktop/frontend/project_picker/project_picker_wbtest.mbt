// Whitebox coverage is limited to the picker's pure helpers. The path
// editor's behavior — filtering, completion browses, fences, quiet
// failures, the composer — is exercised end to end against the real
// browser bundle by `e2e/tests/project_picker.spec.js`, and the shell-facing
// contract by `project_picker_test.mbt`.

///|
test "picker paths join with URI separators" {
  inspect("/home/u".picker_child_path("proj"), content="/home/u/proj")
  inspect("/".picker_child_path("etc"), content="/etc")
  inspect("/C:/code".picker_child_path("app"), content="/C:/code/app")
}

///|
test "a listing keeps its raw protocol path" {
  assert_true(
    reply_message(
      @interop.ChannelId::Local,
      @protocol.Listing(path="/C:/project", parent=Some("/C:/"), entries=[]),
      generation=7,
      drives=true,
    )
    is Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory("/C:/project"),
      entries=[],
      generation=7
    ),
  )
}
