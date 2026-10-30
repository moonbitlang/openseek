///|
test "artifact embeds resolve in Markdown order and never load an image URL" {
  let refs : Array[(String, String)] = []
  ignore(
    markdown_nodes(
      "Before\n\n![Second](artifact://chart_second)\n\nBetween ![First](artifact://chart_first) after.\n\n```text\n![Code](artifact://chart_code)\n```",
      artifact_view=(id, alt) => {
        refs.push((id, alt))
        @html.div(alt)
      },
    ),
  )
  assert_eq(refs, [("chart_second", "Second"), ("chart_first", "First")])
  // Provisional prose has no resolver; a completed embed remains invisible.
  ignore(markdown_nodes("![Pending](artifact://chart_first)"))
  assert_eq(safe_destination("artifact://chart_first"), None)
  assert_eq(
    pending_embed_text("Ready. ![Revenue](artifact://chart_"),
    "Ready. ",
  )
}
