///|
fn github_html_codec(kind : Int, value : Json) -> Json raise {
  match kind {
    0 => {
      let value : @protocol.GithubComment = @json.from_json(value)
      value.to_json()
    }
    1 => {
      let value : @protocol.GithubReviewComment = @json.from_json(value)
      value.to_json()
    }
    _ => {
      let value : @protocol.GithubPullRequestDetail = @json.from_json(value)
      value.to_json()
    }
  }
}

///|
test "GitHub display codecs require HTML and preserve it without a Markdown fallback" {
  let comment : Json = {
    "body_html": "<p><strong>server HTML</strong></p>",
    "url": "https://github.example/o/r/pull/1#issuecomment-1",
    "created_at": "2026-09-22T00:00:00Z",
  }
  let review : Json = {
    "id": "9000000001",
    "body_html": "<p><strong>server HTML</strong></p>",
    "url": "https://github.example/o/r/pull/1#discussion_r9000000001",
    "created_at": "2026-09-22T00:00:00Z",
    "can_delete": true,
  }
  let detail : Json = {
    "item": {
      "number": 1,
      "title": "PR",
      "url": "https://github.example/o/r/pull/1",
      "draft": false,
    },
    "state": "OPEN",
    "mergeable": "MERGEABLE",
    "body_html": "<p><strong>server HTML</strong></p>",
    "base": "main",
    "head": "feature",
    "additions": 1,
    "deletions": 0,
    "changed_files": 1,
    "comments": [comment],
    "checks": [],
    "created_at": "2026-09-22T00:00:00Z",
    "reviewers": [],
    "assignees": [],
    "labels": [],
  }
  for kind, fixture in [comment, review, detail] {
    assert_true(github_html_codec(kind, fixture) == fixture)
    guard fixture is Object(fields) else { fail("expected a fixture object") }
    let empty = fields.copy()
    empty["body_html"] = ""
    assert_true(github_html_codec(kind, Json(empty)) == Json(empty))
    for invalid in [None, Some(Json::null()), Some(Json::number(42.0))] {
      let fields = fields.copy()
      fields["body"] = "legacy raw Markdown is not a fallback"
      match invalid {
        None => fields.remove("body_html")
        Some(value) => fields["body_html"] = value
      }
      assert_true(
        refused(() => github_html_codec(kind, Json(fields)) |> ignore),
      )
    }
  }
}
