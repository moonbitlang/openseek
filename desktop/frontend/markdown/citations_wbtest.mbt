///|
fn answer_citations(source : String) -> Array[Citation] {
  let doc = @cmark.Doc::from_string(source, strict=false)
  let render = MarkdownRender::{
    locale: English,
    defs: doc.defs,
    open_file: None,
    artifact_view: None,
    defer_artifacts: false,
    citations: [],
    in_sources: false,
  }
  ignore(render.block_nodes(doc.block))
  render.citations
}

///|
test "citations follow first use, deduplicate references, and ignore code and unused notes" {
  let source =
    #|Second[^2], first[^1], second again[^2]. `[^3]`
    #|
    #|```text
    #|[^3]
    #|```
    #|
    #|[^1]: [Report](/workspace/report.pdf) — p. 12.
    #|[^2]: [Docs](https://example.com/docs) — Overview.
    #|[^3]: Unused source.
  let citations = answer_citations(source)
  assert_eq(citations.map(c => c.number), ["2", "1"])
  assert_eq(citations[1].summary, "Report — p. 12.")
}

///|
test "citation actions use resolved source links and preserve existing destination rules" {
  let source =
    #|File[^1], web[^2], unfinished[^3], unsafe[^4], text[^5].
    #|
    #|[^1]: [Report](</workspace/My Report.pdf>) — p. 2.
    #|[^2]: [Guide][docs]
    #|[^3]: [Report](https://example.com/unfinished
    #|[^4]: [Blocked](javascript:alert%281%29)
    #|[^5]: A plain note.
    #|
    #|[docs]: https://example.com/docs
  let citations = answer_citations(source)
  assert_eq(citations.length(), 5)
  assert_true(citations[0].link is Some(_))
  assert_true(citations[1].link is Some(_))
  assert_true(citations[2].link is None)
  assert_true(citations[3].link is None)
  assert_true(citations[4].link is None)
}

///|
test "unresolved and nonnumeric footnotes do not become source citations" {
  assert_eq(answer_citations("Pending[^1]").length(), 0)
  assert_eq(answer_citations("Note[^note]\n\n[^note]: A note.").length(), 0)
  for key in ["^0", "^01", "^-1", "^note", "1", "^"] {
    assert_eq(citation_number(key), None)
  }
}
