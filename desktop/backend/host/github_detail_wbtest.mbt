///|
fn github_detail_fixture() -> Json {
  {
    "number": 42,
    "title": "HTML details",
    "url": "https://github.example/owner/repo/pull/42",
    "author": { "login": "author" },
    "isDraft": false,
    "state": "OPEN",
    "mergeable": "MERGEABLE",
    "baseRefName": "main",
    "headRefName": "feature",
    "additions": 1,
    "deletions": 0,
    "changedFiles": 1,
    "statusCheckRollup": null,
    "createdAt": "2026-09-22T00:00:00Z",
    "reviewRequests": [],
    "latestReviews": [],
    "assignees": [],
    "labels": [],
    "milestone": null,
  }
}

///|
fn github_content_fixture(comments : Array[Json], page_info : Json) -> Json {
  {
    "data": {
      "repository": {
        "pullRequest": {
          "bodyHTML": "<p>Rendered <strong>by GitHub</strong></p>",
          "comments": { "nodes": comments.to_json(), "pageInfo": page_info },
        },
      },
    },
  }
}

///|
async test "pull request details preserve GitHub HTML across all comment pages and hosts" {
  let mut pages = 0
  let detail = github_pull_request(
    {
      cwd: "/workspace",
      repository_url: "https://github.example/owner/repo",
      number: 42,
    },
    args => {
      if args[0] == "pr" {
        return github_detail_fixture()
      }
      assert_true(args.contains("github.example"))
      assert_true(args.contains("owner=owner") && args.contains("repo=repo"))
      assert_true(args.contains("number=42"))
      assert_true(args.any(arg => arg.contains("bodyHTML")))
      pages = pages + 1
      assert_eq(args.contains("after=next"), pages == 2)
      github_content_fixture(
        [
          {
            "author": if pages == 1 {
              ({ "login": "reviewer" } : Json)
            } else {
              Json::null()
            },
            "bodyHTML": "<p>Comment <em>\{pages}</em></p>",
            "url": "https://github.example/owner/repo/pull/42#issuecomment-\{pages}",
            "createdAt": "2026-09-22T00:00:00Z",
          },
        ],
        if pages == 1 {
          { "hasNextPage": true, "endCursor": "next" }
        } else {
          { "hasNextPage": false, "endCursor": null }
        },
      )
    },
  )
  assert_eq(pages, 2)
  assert_eq(detail.body_html, "<p>Rendered <strong>by GitHub</strong></p>")
  assert_eq(detail.comments.map(comment => comment.body_html), [
    "<p>Comment <em>1</em></p>", "<p>Comment <em>2</em></p>",
  ])
  assert_eq(detail.comments[1].author, None)
  assert_eq(detail.item.number, 42)
  assert_eq(detail.changed_files, 1)
}

///|
async test "pull request HTML failures never return a truncated or raw Markdown discussion" {
  let identity = github_review_identity(
    "https://github.example/owner/repo/pull/42",
  )
  let partial = github_content_fixture([], {
    "hasNextPage": false,
    "endCursor": null,
  })
  guard partial is Object(partial_fields) else {
    fail("expected a response object")
  }
  partial_fields["errors"] = [{ "message": "denied" }]
  for
    response in [
      github_content_fixture([], { "hasNextPage": true, "endCursor": null }),
      github_content_fixture([], {
        "hasNextPage": true,
        "endCursor": "repeated",
      }),
      partial,
      ({ "data": { "repository": { "pullRequest": null } } } : Json),
      (
        {
          "data": {
            "repository": {
              "pullRequest": {
                "body": "raw markdown",
                "comments": {
                  "nodes": [],
                  "pageInfo": { "hasNextPage": false, "endCursor": null },
                },
              },
            },
          },
        } : Json),
      github_content_fixture(
        [
          {
            "author": null,
            "body": "raw markdown",
            "url": "https://github.example/comment/1",
            "createdAt": "2026-09-22T00:00:00Z",
          },
        ],
        { "hasNextPage": false, "endCursor": null },
      ),
    ] {
    let mut requests = 0
    let rejected = try {
      github_pull_request_content(identity, _args => {
        requests = requests + 1
        if requests > 2 {
          fail("repeated pagination was not rejected")
        }
        response
      })
      |> ignore
      false
    } catch {
      HostError(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}
