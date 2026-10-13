///|
/// Count the non-overlapping occurrences of `needle` in `content`. An empty
/// `needle` counts as zero rather than matching every position.
pub fn count_occurrences(content : String, needle : String) -> Int32 {
  if needle == "" {
    return 0
  }
  content.split(needle).count() - 1
}

///|
/// Count the lines of `content` (split on `\n`) that contain every string in
/// `needles`. With an empty `needles` every line qualifies.
pub fn count_lines_containing_all(
  content : String,
  needles : Array[String],
) -> Int32 {
  content
  .split("\n")
  .count_if(line => needles.all(needle => line.contains(needle)))
}
