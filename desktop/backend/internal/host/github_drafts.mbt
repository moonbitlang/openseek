///|
fn github_drafts_path(runtime_dir : String?, url : String) -> @pathx.Path raise {
  guard runtime_dir is Some(dir) else {
    raise HostError("Local comment draft storage is unavailable.")
  }
  github_review_identity(url) |> ignore
  // Encoding makes the complete PR URL the identity without treating URL
  // segments as filesystem paths. Bound each component for long enterprise URLs.
  let encoded = @base64.encode(@utf8.encode(url), padding=false)
    .replace_all(old="/", new="_")
    .replace_all(old="+", new="-")
  let mut path : @pathx.Path = dir
  path = path.join("github-comment-drafts")
  for offset = 0; offset < encoded.length(); offset = offset + 100 {
    path = path.join(
      encoded[offset:(offset + 100).min(encoded.length())].to_owned(),
    )
  }
  path.join("drafts.json")
}

///|
pub async fn read_github_drafts(
  runtime_dir : String?,
  key : @protocol.GithubDraftsKey,
) -> @protocol.GithubDrafts {
  let path = github_drafts_path(runtime_dir, key.url)
  guard @fsx.read_text_if_exists(path) is Some(text) else {
    return { url: key.url, drafts: [], }
  }
  let saved : @protocol.GithubDrafts = @json.from_json(@json.parse(text))
  guard saved.url == key.url else {
    raise HostError("Local comment drafts belong to a different pull request.")
  }
  saved
}

///|
pub async fn write_github_drafts(
  runtime_dir : String?,
  drafts : @protocol.GithubDrafts,
) -> @protocol.EmptyReply {
  let path = github_drafts_path(runtime_dir, drafts.url)
  if drafts.drafts.is_empty() {
    @fsx.remove_if_exists(path)
    return Acknowledged
  }
  let parent = path.dirname()
  @fsx.ensure_dir(parent)
  let unique = @fs.tmpdir(prefix="github-drafts-")
  defer @fs.rmdir(unique)
  let unique_path : @pathx.Path = unique
  let temp = parent.join(unique_path.basename().to_owned())
  defer @fsx.remove_if_exists(temp)
  @fs.write_file(
    temp.to_string(),
    drafts.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  @fs.rename(temp.to_string(), path.to_string(), replace=true)
  Acknowledged
}
