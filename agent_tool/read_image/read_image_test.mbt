///|
async test "read_image retains bytes independently of the source and detects extension-less formats" {
  let root = @fs.tmpdir(prefix="openseek-read-image-")
  defer @fs.rmdir(root, recursive=true)
  let bytes = @fs.read_file("deepseek/client/testdata/two-colors.png").binary()
  @fs.write_file("\{root}/picture", bytes)
  let tools = @agent_tool.Tools([@read_image.definition(workspace_root=root)])
  tools.set_image_input_supported(true)
  let action = @agent_tool.execute_tool_call(
    @agent_tool.AgentToolCall::from_arguments("read_image", {
      "path": "picture",
    }),
    tools,
  )
  guard action is Respond(output) else { fail("expected image response") }
  assert_false(output.is_error, msg=output.content.text())
  @fs.remove("\{root}/picture")
  assert_true(
    output.content.0 is [Text(_), Image(saved)] &&
    saved == @protocol.Image::from_bytes(bytes),
  )
  assert_true(output.data is Some({ "media_type": "image/png", .. }))
  assert_false(output.content.contains("base64"))
  tools.set_image_input_supported(false)
  let blocked = @agent_tool.execute_tool_call(
    @agent_tool.AgentToolCall::from_arguments("read_image", {
      "path": "picture",
    }),
    tools,
  )
  guard blocked is Respond(output) else { fail("expected refusal") }
  assert_true(output.is_error)
  assert_true(output.content.contains("model route"))
  assert_true(output.content.is_text_only())
}

///|
async test "read_image reports missing paths directories invalid bytes and oversize files" {
  let root = @fs.tmpdir(prefix="openseek-image-errors-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file("\{root}/invalid.png", "not an image")
  @fs.write_file("\{root}/large.png", Bytes::make(5 * 1024 * 1024 + 1, b'\x00'))
  let tools = @agent_tool.Tools([@read_image.definition(workspace_root=root)])
  tools.set_image_input_supported(true)
  for path in ["missing.png", ".", "invalid.png", "large.png", " "] {
    let action = @agent_tool.execute_tool_call(
      @agent_tool.AgentToolCall::from_arguments("read_image", { "path": path }),
      tools,
    )
    guard action is Respond(output) else { fail("expected failure response") }
    assert_true(output.is_error, msg=path)
    assert_true(output.content.is_text_only())
  }
}
