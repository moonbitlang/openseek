///|
test "full-diff comments cross the Desktop boundary without losing line identity" {
  let file = @pathx.Relative("src/main.mbt")
  let deletion = diff_comment_message(
    file,
    original_line_number=Some(4),
    modified_line_number=None,
    quote="obsolete()",
    comment="good removal",
  )
  assert_true(
    deletion
    is DiffCommentAdded(
      file=Relative("src/main.mbt"),
      original_line_number=Some(4),
      modified_line_number=None,
      quote="obsolete()",
      comment="good removal",
      resource=None,
      feedback_id=None
    ),
  )
  let context = diff_comment_message(
    file,
    original_line_number=Some(8),
    modified_line_number=Some(9),
    quote="shared()",
    comment="keep this",
  )
  assert_true(
    context
    is DiffCommentAdded(
      original_line_number=Some(8),
      modified_line_number=Some(9),
      quote="shared()",
      comment="keep this",
      ..
    ),
  )
  let original_editor = diff_comment_message(
    file,
    original_line_number=Some(12),
    modified_line_number=None,
    quote="removed()",
    comment="restore this",
    resource=ModelUri("openseek-review-original://workspace/src/main.mbt"),
    feedback_id="feedback-12",
  )
  assert_true(
    original_editor
    is DiffCommentAdded(
      original_line_number=Some(12),
      modified_line_number=None,
      resource=Some(
        ModelUri("openseek-review-original://workspace/src/main.mbt")
      ),
      feedback_id=Some("feedback-12"),
      ..
    ),
  )
}
