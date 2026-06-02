///|
test "input doc renders prompt prefixes" {
  inspect(
    @doc.ToDoc::to_doc(@core.TranscriptItem::Input(Prompt("hello\nworld")))
    .layout(width=20)
    .map(line => line.text())
    .join("|"),
    content="> hello|  world",
  )
  inspect(
    @doc.ToDoc::to_doc(@core.TranscriptItem::Input(Command("pwd")))
    .layout(width=20)
    .map(line => line.text())
    .join("|"),
    content="$ pwd",
  )
}

///|
test "transcript response renders bullet and continuation prefix" {
  inspect(
    @doc.ToDoc::to_doc(@core.TranscriptItem::Response("hello\nworld"))
    .layout(width=20)
    .map(line => line.text())
    .join("|"),
    content="• hello|  world",
  )
}

///|
test "transcript tool call renders detail texts without caller-side joining" {
  inspect(
    @doc.ToDoc::to_doc(
      @core.TranscriptItem::ToolCall(
        ToolCall(@doc.Text::plain("Ran moon test"), status=Completed, details=[
          @doc.Text::plain("one"),
          @doc.Text::plain("two\nthree"),
        ]),
      ),
    )
    .layout(width=40)
    .map(line => line.text())
    .join("|"),
    content="• Ran moon test|  └ one|    two|    three",
  )
}
