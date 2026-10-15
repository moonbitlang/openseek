///|
test "tagged messages preserve body and attribute values" {
  let message = @message_context.Message(
    source_session="chat \"A\" & <B>\nsecond line",
    message_id="literal &quot;",
    text="  中文 `code` & <script>text</script>\n</agent_message>\nlast line  ",
  )
  assert_eq(@message_context.parse(message.encode()), Some(message))
  assert_true(message.encode().has_prefix("<agent_message "))
  assert_false(message.encode().contains("user approved"))
  let result = @message_context.DeliveryResult(
    message_id="msg-1",
    request_id="request-1",
    target="chat-B",
    status="sent",
    error=None,
  )
  assert_eq(@message_context.parse(result.encode()), Some(result))
  let failure = @message_context.DeliveryResult(
    message_id="msg-2",
    request_id="request-2",
    target="chat-B",
    status="failed",
    error=Some("Unavailable\n</session_message_result>\nRetry later"),
  )
  assert_eq(@message_context.parse(failure.encode()), Some(failure))
}

///|
test "incomplete or quoted envelopes remain ordinary text" {
  for
    text in [
      "plain message", "<agent_message source_session=\"chat-A\" message_id=\"msg-1\">\nunfinished",
      "Please inspect:\n<agent_message source_session=\"chat-A\" message_id=\"msg-1\">\nhello\n</agent_message>",
      "<agent_message source_session=\"chat-A\" extra=\"field\" message_id=\"msg-1\">\nhello\n</agent_message>",
    ] {
    assert_eq(@message_context.parse(text), None)
  }
}

///|
test "attribute entities are escaped and decoded exactly once" {
  let message = @message_context.Message(
    source_session="\"&<>\r\n中文🙂",
    message_id="&amp;&quot;&lt;&gt;&#13;&#10;",
    text="body",
  )
  let encoded =
    #|<agent_message source_session="&quot;&amp;&lt;&gt;&#13;&#10;中文🙂" message_id="&amp;amp;&amp;quot;&amp;lt;&amp;gt;&amp;#13;&amp;#10;">
    #|body
    #|</agent_message>
  assert_eq(message.encode(), encoded)
  assert_eq(@message_context.parse(encoded), Some(message))
  let unknown =
    #|<agent_message source_session="&unknown; &#xA; &quot &amp" message_id="">
    #|
    #|</agent_message>
  assert_eq(
    @message_context.parse(unknown),
    Some(
      @message_context.Message(
        source_session="&unknown; &#xA; &quot &amp",
        message_id="",
        text="",
      ),
    ),
  )
}
