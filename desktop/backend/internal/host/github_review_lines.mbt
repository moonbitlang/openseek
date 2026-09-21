///|
fn github_review_patch_start(value : String, prefix : String) -> Int raise {
  guard value.has_prefix(prefix) &&
    value[1:].split(",").to_array() is [number, ..] else {
    raise HostError("GitHub returned an invalid diff hunk coordinate.")
  }
  let start = @string.parse_int(number)
  guard start >= 0 else {
    raise HostError("GitHub returned a negative diff hunk coordinate.")
  }
  start
}

///|
fn github_review_patch_lines(
  path : String,
  patch : String,
) -> @protocol.GithubCommentableFile raise {
  let left_lines : Array[Int] = []
  let right_lines : Array[Int] = []
  let mut cursor : (Int, Int)? = None
  for row in patch.split("\n") {
    if row.has_prefix("@@ ") {
      guard row.split(" ").to_array() is ["@@", old, new, "@@", ..] else {
        raise HostError("GitHub returned an invalid diff hunk header.")
      }
      cursor = Some(
        (
          github_review_patch_start(old.to_owned(), "-"),
          github_review_patch_start(new.to_owned(), "+"),
        ),
      )
      continue
    }
    guard cursor is Some((old, new)) else {
      if !row.is_empty() {
        raise HostError("GitHub returned diff lines without a hunk header.")
      }
      continue
    }
    if row.has_prefix("-") {
      guard old > 0 else {
        raise HostError("GitHub returned an invalid deleted line.")
      }
      left_lines.push(old)
      cursor = Some((old + 1, new))
    } else if row.has_prefix("+") {
      guard new > 0 else {
        raise HostError("GitHub returned an invalid added line.")
      }
      right_lines.push(new)
      cursor = Some((old, new + 1))
    } else if row.has_prefix(" ") {
      guard old > 0 && new > 0 else {
        raise HostError("GitHub returned an invalid context line.")
      }
      right_lines.push(new)
      cursor = Some((old + 1, new + 1))
    } else if !row.is_empty() && !row.has_prefix("\\ No newline at end of file") {
      raise HostError("GitHub returned an invalid diff line.")
    }
  }
  { path, left_lines, right_lines, }
}

///|
fn github_review_commentable_files(
  raw : Json,
) -> Array[@protocol.GithubCommentableFile] raise {
  guard raw is Array(pages) else {
    raise HostError("GitHub returned invalid PR file pagination.")
  }
  let files : Array[@protocol.GithubCommentableFile] = []
  for page in pages {
    guard page is Array(entries) else {
      raise HostError("GitHub returned an invalid PR file page.")
    }
    for entry in entries {
      guard entry is { "filename": String(path), .. } && entry is Object(fields) else {
        raise HostError("GitHub omitted a PR file path.")
      }
      // Binary, empty, and unavailable patches have no line-comment targets.
      // Existing conversations remain readable independently of these targets.
      let file : @protocol.GithubCommentableFile = match fields.get("patch") {
        None | Some(Null) => { path, left_lines: [], right_lines: [], }
        Some(String(patch)) => github_review_patch_lines(path, patch)
        _ => raise HostError("GitHub returned an invalid PR patch.")
      }
      files.push(file)
    }
  }
  files
}
