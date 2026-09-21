///|
test "GitHub patch coordinates keep deletions context and unavailable sides distinct" {
  let files = github_review_commentable_files([
    [
      {
        "filename": "renamed file.mbt",
        "patch": "@@ -10,3 +20,4 @@ fn example()\n context\n-removed\n+added\n+also added\n context\n\\ No newline at end of file\n@@ -40 +50 @@\n-before\n+after",
      },
    ],
    [
      { "filename": "empty.mbt" },
      { "filename": "added.mbt", "patch": "@@ -0,0 +1 @@\n+new" },
      { "filename": "deleted.mbt", "patch": "@@ -1 +0,0 @@\n-old" },
    ],
  ])
  assert_eq(files[0].left_lines, [11, 40])
  assert_eq(files[0].right_lines, [20, 21, 22, 23, 50])
  assert_true(files[1].left_lines.is_empty() && files[1].right_lines.is_empty())
  assert_eq(files[2].left_lines, [])
  assert_eq(files[2].right_lines, [1])
  assert_eq(files[3].left_lines, [1])
  assert_eq(files[3].right_lines, [])
  let review : @protocol.GithubReview = {
    url: "https://github.com/o/r/pull/1",
    base: "base",
    head: "head",
    threads: [],
    commentable: files,
  }
  assert_false(review.can_comment("renamed file.mbt", true, 10))
  assert_true(review.can_comment("renamed file.mbt", true, 11))
  assert_true(review.can_comment("renamed file.mbt", false, 20))
  assert_false(review.can_comment("renamed file.mbt", false, 24))
  assert_false(review.can_comment("empty.mbt", false, 1))
  assert_false(review.can_comment("absent.mbt", false, 1))
  let decoded : @protocol.GithubReview = @json.from_json(review.to_json())
  assert_true(decoded == review)
  let invalid : Array[Json] = [
    [[{ "filename": "bad.mbt", "patch": 3 }]],
    [[{ "filename": "bad.mbt", "patch": "@@ -bad +1 @@\n+x" }]],
    [[{ "patch": "@@ -1 +1 @@\n-x\n+y" }]],
  ]
  for raw in invalid {
    try github_review_commentable_files(raw) catch {
      _ => ()
    } noraise {
      _ =>
        fail(
          "malformed GitHub patches must not become a successful empty result",
        )
    }
  }
}
