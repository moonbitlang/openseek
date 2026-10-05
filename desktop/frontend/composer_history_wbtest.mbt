///|
fn user_item(text : String) -> @transcript.TranscriptItem {
  { kind: User(content=Content([Text(text)])), ts: None, sequence: None, }
}

///|
test "sent prompts are the user's own, in order, without shell results or repeats" {
  let conv = {
    ..running_conversation(),
    messages: [
      user_item("one"),
      user_item("one"),
      user_item(
        @command_context.encode(
          "ls",
          Ok({ exit_code: Some(0), text: "src", output_limit_reached: false, }),
        ),
      ),
      user_item("   "),
      user_item("two"),
    ],
  }
  assert_eq(conv.sent_prompts(), ["one", "two"])
}
