///|
/// Preserve the bounded normalized sources for programs. Optional source
/// fields are omitted, never replaced with empty-string sentinels.
fn SearchOutcome::to_data(self : SearchOutcome) -> Json {
  let sources : Array[Json] = self.sources.map(source => {
    let fields : Map[String, Json] = { "url": source.url.to_json() }
    if source.title is Some(value) {
      fields["title"] = value.to_json()
    }
    if source.snippet is Some(value) {
      fields["snippet"] = value.to_json()
    }
    if source.published_at is Some(value) {
      fields["published_at"] = value.to_json()
    }
    Json::object(fields)
  })
  { "sources": sources.to_json(), "truncated": self.truncated.to_json() }
}

///|
test "structured search preserves optional fields and truncation" {
  let outcome : SearchOutcome = {
    sources: [
      {
        url: "https://example.com",
        title: None,
        snippet: Some("excerpt"),
        published_at: None,
      },
    ],
    truncated: true,
  }
  json_inspect(outcome.to_data(), content={
    "sources": [{ "url": "https://example.com", "snippet": "excerpt" }],
    "truncated": true,
  })
}
