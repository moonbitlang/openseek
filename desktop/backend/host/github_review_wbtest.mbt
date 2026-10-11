///|
test "GitHub review comments preserve large IDs, deleted authors and permissions" {
  for id in [Json::number(9000000001.0), Json::string("9000000001")] {
    let comment = github_review_comment({
      "fullDatabaseId": id,
      "bodyHTML": "<p><strong>test</strong></p>",
      "url": "https://github.com/o/r/pull/1#discussion_r9000000001",
      "author": Json::null(),
      "createdAt": "2026-09-20T01:00:00Z",
      "viewerCanDelete": true,
    })
    assert_eq(comment.id, "9000000001")
    assert_eq(comment.body_html, "<p><strong>test</strong></p>")
    assert_eq(comment.author, None)
    assert_eq(comment.avatar_url, None)
    assert_true(comment.can_delete)
  }
  let thread : @protocol.GithubReviewThread = @json.from_json({
    "id": "thread",
    "path": "old.mbt",
    "side": "LEFT",
    "line": Json::null(),
    "original_line": 3,
    "resolved": true,
    "outdated": true,
    "can_reply": true,
    "can_resolve": false,
    "can_unresolve": true,
    "comments": [],
  })
  assert_eq(thread.line, None)
  assert_eq(thread.original_line, Some(3))
  assert_true(thread.resolved && thread.outdated && thread.can_unresolve)
}

///|
test "review mutations use the requested host, side, revision and literal body" {
  let identity = github_review_identity(
    "https://github.example/owner/repo/pull/42",
  )
  let body = "@file.txt\n$(echo no) `literal` \"quoted\""
  let args = github_review_mutation_args(
    identity,
    Post(
      path="src/a b.mbt",
      side="LEFT",
      line=12,
      body~,
      head="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
  )
  assert_true(args.contains("github.example"))
  assert_true(args.contains("repos/owner/repo/pulls/42/comments"))
  assert_true(args.contains("side=LEFT") && args.contains("line=12"))
  assert_true(args.contains("body=" + body))
  assert_true(
    args.contains("commit_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let reply = github_review_mutation_args(
    identity,
    Reply(comment="9000000001", body~),
  )
  assert_true(
    reply.contains("repos/owner/repo/pulls/42/comments/9000000001/replies"),
  )
  let deletion = github_review_mutation_args(
    identity,
    Delete(comment="9000000001"),
  )
  assert_true(
    deletion.contains("DELETE") &&
    deletion.contains("repos/owner/repo/pulls/comments/9000000001"),
  )
  let resolve = github_review_mutation_args(
    identity,
    Resolve(thread="thread-id", resolved=true),
  )
  assert_true(resolve.contains("id=thread-id"))
  assert_true(
    resolve.any(arg => arg.contains("resolveReviewThread(input:{threadId:$id})")),
  )
}

///|
test "review pagination cannot mistake a missing cursor for a complete discussion" {
  assert_eq(
    github_review_page({
      "nodes": [],
      "pageInfo": { "hasNextPage": false, "endCursor": Json::null() },
    }).1,
    None,
  )
  assert_eq(
    github_review_page({
      "nodes": [],
      "pageInfo": { "hasNextPage": true, "endCursor": "next" },
    }).1,
    Some("next"),
  )
  let malformed = try {
    github_review_page({
      "nodes": [],
      "pageInfo": { "hasNextPage": true, "endCursor": Json::null() },
    })
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(malformed)
}

///|
async test "review file snapshots use pinned local commits across renames additions and deletions" {
  let dir = @fs.tmpdir(prefix="openseek-review-files-")
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    @fs.write_file(
      "\{dir}/old name.mbt",
      "original\n".repeat(20),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/removed.mbt",
      "removed\n",
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["add", "."])
    git_test_commit(dir, "base")
    let base = github_checkout_git(dir, ["rev-parse", "HEAD"]).trim().to_owned()
    git_test_run(dir, ["mv", "old name.mbt", "new name.mbt"])
    @fs.write_file(
      "\{dir}/new name.mbt",
      "original\n".repeat(20) + "changed\n",
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["rm", "removed.mbt"])
    @fs.write_file("\{dir}/added.mbt", "added\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "."])
    git_test_commit(dir, "head")
    let head = github_checkout_git(dir, ["rev-parse", "HEAD"]).trim().to_owned()
    @fs.write_file(
      "\{dir}/new name.mbt",
      "uncommitted\n",
      create_mode=CreateOrTruncate,
    )
    for
      (path, original, modified) in [
        (
          "new name.mbt",
          Some("original\n".repeat(20)),
          Some("original\n".repeat(20) + "changed\n"),
        ),
        ("added.mbt", None, Some("added\n")),
        ("removed.mbt", Some("removed\n"), None),
      ] {
      let reply = github_review_file_op({ cwd: dir, path, base, head, })
      assert_true(
        reply is ReviewFileLoaded(Some(file)) &&
        file.path == path &&
        file.original == original &&
        file.modified == modified,
      )
    }
    let missing = github_review_file_op({
      cwd: dir,
      path: "absent.mbt",
      base,
      head,
    })
    assert_true(missing is ReviewFileLoaded(None))
    let unavailable = github_review_file_op({
      cwd: dir,
      path: "new name.mbt",
      base,
      head: "ffffffffffffffffffffffffffffffffffffffff",
    })
    assert_true(unavailable is ReviewFileFailed(_))
  }
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "review snapshots distinguish an absent side from an empty blob" {
  for added in [true, false] {
    let dir = @fs.tmpdir(prefix="openseek-review-empty-")
    let _ = {
      defer git_test_cleanup(dir)
      git_test_run(dir, ["init", "--quiet"])
      @fs.write_file("\{dir}/seed.txt", "seed\n", create_mode=CreateOrTruncate)
      if !added {
        @fs.write_file("\{dir}/empty.mbt", "", create_mode=CreateOrTruncate)
      }
      git_test_run(dir, ["add", "."])
      git_test_commit(dir, "base")
      let base = github_checkout_git(dir, ["rev-parse", "HEAD"])
        .trim()
        .to_owned()
      if added {
        @fs.write_file("\{dir}/empty.mbt", "", create_mode=CreateOrTruncate)
      } else {
        git_test_run(dir, ["rm", "empty.mbt"])
      }
      git_test_run(dir, ["add", "."])
      git_test_commit(dir, "head")
      let head = github_checkout_git(dir, ["rev-parse", "HEAD"])
        .trim()
        .to_owned()
      let reply = github_review_file_op({
        cwd: dir,
        path: "empty.mbt",
        base,
        head,
      })
      guard reply is ReviewFileLoaded(Some(file)) else {
        fail("expected the empty file's revision snapshot")
      }
      let expected : Json = if added {
        { "path": "empty.mbt", "modified": "" }
      } else {
        { "path": "empty.mbt", "original": "" }
      }
      assert_true(file.to_json() == expected)
      let decoded : @protocol.GithubReviewFile = @json.from_json(expected)
      assert_true(decoded == file)
    }
  }
}
