///|
/// A canned Anthropic-style Messages response with two searched sources, one
/// carrying a citation excerpt, plus a duplicate result item to exercise the
/// URL dedup.
fn sample_response() -> Json {
  {
    "content": [
      {
        "type": "server_tool_use",
        "id": "srvtoolu_1",
        "name": "web_search",
        "input": { "query": "moonbit language" },
      },
      {
        "type": "web_search_tool_result",
        "tool_use_id": "srvtoolu_1",
        "content": [
          {
            "type": "web_search_result",
            "url": "https://example.com/a",
            "title": "Example A",
            "page_age": "January 5, 2026",
          },
          { "type": "web_search_result", "url": "https://example.org/b" },
          {
            "type": "web_search_result",
            "url": "https://example.com/a",
            "title": "Example A duplicate",
          },
        ],
      },
      {
        "type": "text",
        "text": "According to Example A, MoonBit is fast.",
        "citations": [
          {
            "type": "citations_web_search_result_location",
            "url": "https://example.com/a",
            "cited_text": "MoonBit is a fast language.",
          },
        ],
      },
    ],
  }
}

///|
test "parse_search_response cuts to max_results and flags the cut" {
  let outcome = parse_search_response(sample_response(), max_results=1)
  assert_eq(outcome.sources.length(), 1)
  assert_true(outcome.truncated)
  let rendered = format_output(outcome)
  assert_true(
    rendered.contains(
      "(Showing the first 1 sources. Refine the query for more.)",
    ),
  )
}

///|
test "parse_search_response joins citations, dedupes, and formats" {
  let outcome = parse_search_response(sample_response(), max_results=8)
  assert_eq(outcome.sources.length(), 2)
  assert_false(outcome.truncated)
  let rendered = format_output(outcome)
  assert_eq(
    rendered,
    (
      #|Sources:
      #|- [Example A](https://example.com/a) — MoonBit is a fast language. (January 5, 2026)
      #|- [example.org](https://example.org/b)
      #|
      #|Cite the relevant URLs above as markdown links in your answer.
    ),
  )
}
