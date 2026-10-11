///|
test "GitHub list queries keep author filtering separate from all open and issues" {
  let repository = "https://github.example.com/team/project"
  for kind in [@protocol.CreatedByMe, AllOpen, Issues] {
    let args = github_list_args(kind, repository, 30)
    assert_eq(args[0], if kind is Issues { "issue" } else { "pr" })
    assert_true(args.contains(repository))
    assert_true(args.contains("open"))
    assert_true(args.contains("31"))
    assert_eq(args.contains("--author"), kind is CreatedByMe)
    assert_eq(args.contains("@me"), kind is CreatedByMe)
  }
}

///|
fn github_list_fixture(args : Array[String]) -> Json {
  if args[0] == "repo" {
    { "nameWithOwner": "owner/repo", "url": "https://github.com/owner/repo" }
  } else {
    [
      {
        "number": 42,
        "title": "Pull request",
        "url": "https://github.com/owner/repo/pull/42",
        "author": { "id": "actor-id", "login": "author" },
        "isDraft": false,
      },
    ]
  }
}

///|
async test "avatar failures preserve inventory and remain distinct from absent actors" {
  let payload : @protocol.GithubListPayload = {
    cwd: "/workspace",
    kind: AllOpen,
    limit: 30,
  }
  for
    response in [
      None,
      Some(({} : Json)),
      Some(({ "data": { "nodes": [42] } } : Json)),
      Some(({ "data": { "nodes": [null] } } : Json)),
    ] {
    let reply = github_list(payload, args => {
      if args[0] != "api" {
        github_list_fixture(args)
      } else {
        match response {
          None => raise HostError("offline")
          Some(json) => json
        }
      }
    })
    assert_eq(reply.items[0].number, 42)
    assert_eq(reply.items[0].avatar_url, None)
    assert_eq(
      reply.avatar_error is None,
      response is Some({ "data": { "nodes": [Null], .. }, .. }),
    )
    let decoded : @protocol.GithubListReply = @json.from_json(reply.to_json())
    assert_true(decoded == reply)
  }
}

///|
async test "avatar lookup has its own deadline after inventory completes" {
  let payload : @protocol.GithubListPayload = {
    cwd: "/workspace",
    kind: AllOpen,
    limit: 30,
  }
  for avatar_timeout in [100, 1000] {
    let reply = github_list(
      payload,
      args => {
        if args[0] != "api" {
          github_list_fixture(args)
        } else {
          @async.sleep(200)
          {
            "data": {
              "nodes": [
                { "login": "author", "avatarUrl": "https://avatars.example/42" },
              ],
            },
          }
        }
      },
      inventory_timeout=100,
      avatar_timeout~,
    )
    assert_eq(reply.items[0].number, 42)
    if avatar_timeout == 100 {
      assert_true(reply.avatar_error is Some(_))
      assert_eq(reply.items[0].avatar_url, None)
    } else {
      assert_eq(reply.avatar_error, None)
      assert_eq(reply.items[0].avatar_url, Some("https://avatars.example/42"))
    }
  }
}
