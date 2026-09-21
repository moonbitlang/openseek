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
  try {
    let value = @js.Error_::wrap(
      () => @js.globalThis.get_with_string("localStorage"),
      map_ok=value => value,
    )
    guard !value.is_null() && !value.is_undefined() else {
      return Err(StorageUnavailable)
    }
    let storage = value
    let raw : String? = @js.Error_::wrap(
      () => {
        storage.apply_with_string("getItem", [
          @js.Value::cast_from(drafts_storage_key(url)),
        ])
      },
      map_ok=value => if value.is_null() { None } else { Some(value.cast()) },
    )
    Ok(
      match raw {
        None => []
        Some(raw) => @json.from_json(@json.parse(raw))
      },
    )
  } catch {
    error => Err(RestoreDraftsFailed(error.to_string()))
  }
}

///|
fn store_browser_drafts(
  url : String,
  drafts : Array[GithubDraft],
) -> Result[Unit, Failure] {
  try {
    let value = @js.Error_::wrap(
      () => @js.globalThis.get_with_string("localStorage"),
      map_ok=value => value,
    )
    guard !value.is_null() && !value.is_undefined() else {
      return Err(StorageUnavailable)
    }
    let storage = value
    @js.Error_::wrap(
      () => {
        if drafts.is_empty() {
          storage.apply_with_string("removeItem", [
            @js.Value::cast_from(drafts_storage_key(url)),
          ])
        } else {
          storage.apply_with_string("setItem", [
            @js.Value::cast_from(drafts_storage_key(url)),
            @js.Value::cast_from(drafts.to_json().stringify()),
          ])
        }
      },
      map_ok=_ => (),
    )
    Ok(())
  } catch {
    error => Err(SaveDraftsFailed(error.to_string()))
  }
}
