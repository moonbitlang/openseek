///|
fn auto_fold_policy_model(
  display_name : String,
  language_id : String,
) -> @model.TextModel {
  TextModel(
    try! @common.Uri::from(
      scheme="inmemory",
      authority="auto-fold-policy",
      path="/fixture",
    ),
    display_name,
    language_id,
    1,
    "revision-1",
    "root\n  child",
  )
}

///|
test "auto-fold policy is limited to ordinary MoonBit source files" {
  assert_true(
    should_auto_fold_top_level(auto_fold_policy_model("main.mbt", "moonbit")),
  )
  assert_false(
    should_auto_fold_top_level(
      auto_fold_policy_model("pkg.generated.mbti", "moonbit"),
    ),
  )
  assert_false(
    should_auto_fold_top_level(
      auto_fold_policy_model("README.mbt.md", "moonbit"),
    ),
  )
  assert_false(
    should_auto_fold_top_level(auto_fold_policy_model("source", "moonbit")),
  )
  assert_false(
    should_auto_fold_top_level(auto_fold_policy_model("main.mbt", "plaintext")),
  )
}
