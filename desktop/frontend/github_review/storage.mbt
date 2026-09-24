///|
fn drafts_storage_key(url : String) -> String {
  "seekmoon.github-comment-drafts.v1:" + url
}

///|
async fn load_drafts_unlocked(
  url : String,
) -> Result[Array[GithubDraft], Failure] {
  if @interop.openseek_api() is None {
    return load_browser_drafts(url)
  }
  try {
    let reply = @interop.bridge_request(
      @interop.Local,
      @commands.github_drafts_get,
      { url, },
    )
    guard reply.url == url else { return Err(WrongDraftPullRequest) }
    Ok(reply.drafts)
  } catch {
    error => Err(RestoreDraftsFailed(@interop.bridge_error_text(error)))
  }
}

///|
async fn store_drafts_unlocked(
  url : String,
  drafts : Array[GithubDraft],
) -> Result[Unit, Failure] {
  if @interop.openseek_api() is None {
    return store_browser_drafts(url, drafts)
  }
  try {
    @interop.bridge_request(@interop.Local, @commands.github_drafts_set, {
      url,
      drafts,
    })
    |> ignore
    Ok(())
  } catch {
    error => Err(SaveDraftsFailed(@interop.bridge_error_text(error)))
  }
}

///|
async fn load_drafts(url : String) -> Result[Array[GithubDraft], Failure] {
  @interop.in_ordered_lane(drafts_storage_key(url), () => {
    load_drafts_unlocked(url)
  })
}

///|
async fn store_drafts(
  url : String,
  drafts : Array[GithubDraft],
) -> Result[Unit, Failure] {
  @interop.in_ordered_lane(drafts_storage_key(url), () => {
    store_drafts_unlocked(url, drafts)
  })
}

///|
async fn remove_sent_draft(
  url : String,
  sent : GithubDraft,
) -> Result[Unit, Failure] {
  // Hold the same lane across read/modify/write so a send completion cannot
  // race a newer edit or restore a previously cancelled draft.
  @interop.in_ordered_lane(drafts_storage_key(url), () => {
    match load_drafts_unlocked(url) {
      Ok(drafts) =>
        store_drafts_unlocked(url, drafts.filter(item => item != sent))
      Err(error) => Err(error)
    }
  })
}

///|
fn load_browser_drafts(url : String) -> Result[Array[GithubDraft], Failure] {
  let raw = match @base_browser.local_storage_get(drafts_storage_key(url)) {
    Ok(raw) => raw
    Err(Unavailable) => return Err(StorageUnavailable)
    Err(AccessFailed(message)) => return Err(RestoreDraftsFailed(message))
  }
  Ok(
    match raw {
      None => []
      Some(raw) => @json.from_json(@json.parse(raw))
    },
  ) catch {
    error => Err(RestoreDraftsFailed(error.to_string()))
  }
}

///|
fn store_browser_drafts(
  url : String,
  drafts : Array[GithubDraft],
) -> Result[Unit, Failure] {
  let result = if drafts.is_empty() {
    @base_browser.local_storage_remove(drafts_storage_key(url))
  } else {
    @base_browser.local_storage_set(
      drafts_storage_key(url),
      drafts.to_json().stringify(),
    )
  }
  match result {
    Ok(_) => Ok(())
    Err(Unavailable) => Err(StorageUnavailable)
    Err(AccessFailed(message)) => Err(SaveDraftsFailed(message))
  }
}
