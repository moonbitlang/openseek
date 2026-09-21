///|
/// Positions present in GitHub's own PR patch, rather than the displayed file.
/// LEFT contains deletions; RIGHT contains additions and context lines.
pub(all) struct GithubCommentableFile {
  path : String
  left_lines : Array[Int]
  right_lines : Array[Int]
} derive(Eq, Debug)

///|
pub impl FromJson for GithubCommentableFile with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub commentable file")
  {
    path: object.required_string("path"),
    left_lines: @json.from_json(object.required_json("left_lines")),
    right_lines: @json.from_json(object.required_json("right_lines")),
  }
}

///|
pub impl ToJson for GithubCommentableFile with fn to_json(self) {
  {
    "path": self.path.to_json(),
    "left_lines": self.left_lines.to_json(),
    "right_lines": self.right_lines.to_json(),
  }
}

///|
pub fn GithubReview::can_comment(
  self : GithubReview,
  path : String,
  original : Bool,
  line : Int,
) -> Bool {
  line > 0 &&
  self.commentable
  .iter()
  .any(file => {
    file.path == path &&
    (if original { file.left_lines } else { file.right_lines }).contains(line)
  })
}

///|
pub extend GithubCommentableFile with Eq::{equal, not_equal}

///|
pub extend GithubCommentableFile with Debug::{to_repr}

///|
pub extend GithubCommentableFile with ToJson::{to_json}

///|
pub extend GithubCommentableFile with FromJson::{from_json}
