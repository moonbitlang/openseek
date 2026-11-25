// Sidebar pull-request status badges for durable conversations.
//
// Each session's attached PR URLs arrive in `session.list` and stay current
// via `session.artifacts_changed` (MCP `artifacts_attach`) and overview
// removals. PR states are fetched in batches via `github.pull_request_summaries`
// and cached in `model.changes`, so the sidebar and overview share one source
// of truth without redundant GitHub CLI calls.

///|
fn extract_pull_request_urls(
  artifacts : Array[@protocol.SessionArtifact],
) -> Array[String] {
  let urls : Array[String] = []
  for artifact in artifacts {
    if artifact.type_ is PullRequest &&
      !artifact.url.is_blank() &&
      !urls.contains(artifact.url) {
      urls.push(artifact.url)
    }
  }
  urls
}

///|
fn DeviceState::pull_requests_for(
  self : DeviceState,
  session : String,
) -> Array[String] {
  if self.session_pull_requests.get(session) is Some(urls) {
    return urls
  }
  for item in self.sessions {
    if item.id == session {
      return item.pull_requests
    }
  }
  []
}

///|
fn DeviceState::with_session_pull_requests(
  self : DeviceState,
  session : String,
  urls : Array[String],
) -> DeviceState {
  let session_pull_requests = self.session_pull_requests.copy()
  session_pull_requests[session] = urls
  let sessions = self.sessions.map(item => {
    if item.id == session {
      { ..item, pull_requests: urls, }
    } else {
      item
    }
  })
  { ..self, sessions, session_pull_requests, }
}

///|
fn sidebar_pr_tone_rank(tone : @conversation.PullRequestTone) -> Int32 {
  match tone {
    Open => 4
    Draft => 3
    Merged => 2
    Closed => 1
    Unknown => 0
  }
}

///|
fn sidebar_pr_tone_of(
  state : @session_changes.PullRequestState,
) -> @conversation.PullRequestTone {
  match state {
    Open => Open
    Draft => Draft
    Merged => Merged
    Closed => Closed
  }
}

///|
fn sidebar_pr_fallback_label(url : String) -> String {
  let path = url.split("#").collect()[0].split("?").collect()[0]
  let trimmed = match path.strip_prefix("https://") {
    Some(rest) => rest.to_owned()
    None => path.to_owned()
  }
  let parts = trimmed.split("/").map(part => part.to_owned()).collect()
  match parts {
    [_, owner, repo, "pull", number, ..] => "\{owner}/\{repo} #\{number}"
    _ => trimmed
  }
}

///|
/// Build the sidebar PR status badge for `session_id` on `channel`.
///
/// When multiple PRs are attached, the most actionable state wins:
/// `Open > Draft > Merged > Closed > Unknown`, and `count` carries the total
/// number of attached PRs so the row displays the count beside the icon.
fn Model::sidebar_pull_request_badge(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> @conversation.PullRequestBadge? {
  guard self.device_state(channel) is Some(dev) else { return None }
  let urls = dev.pull_requests_for(session_id)
  guard !urls.is_empty() else { return None }
  let mut tone : @conversation.PullRequestTone = Unknown
  let lines : Array[String] = []
  for url in urls {
    match self.changes.summary(url) {
      Some(pr) => {
        let next = sidebar_pr_tone_of(pr.state)
        if sidebar_pr_tone_rank(next) > sidebar_pr_tone_rank(tone) {
          tone = next
        }
        let state_label = pr.state.label(locale=self.locale)
        lines.push("#\{pr.number} \{pr.title} (\{state_label})")
      }
      None => lines.push(sidebar_pr_fallback_label(url))
    }
  }
  Some({ tone, count: urls.length(), title: lines.join("\n"), })
}

///|
fn sync_session_artifacts_cmd(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
) -> @cmd.Cmd {
  @cmd.attempt(
    result => {
      dispatch(
        FromDevice(
          channel,
          SessionArtifactsSynced(
            session~,
            result.map_err(@interop.bridge_error_text),
          ),
        ),
      )
    },
    () => {
      @interop.bridge_request(channel, @commands.session_artifacts_list, {
        session,
      })
    },
  )
}

///|
fn batch_lookup_pull_requests(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  urls : Array[String],
  force~ : Bool,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard !urls.is_empty() else { return (@cmd.none, model) }
  let (cmd, changes) = @session_changes.update(
    dispatch.map(msg => Changes(msg)),
    BatchLookup(channel~, urls~, force~),
    model.changes,
  )
  (cmd, { ..model, changes, })
}

///|
fn collect_session_pull_requests(
  items : Array[@transcript.SessionListItem],
  overrides : Map[String, Array[String]],
) -> Array[String] {
  let urls : Array[String] = []
  let push_unique = (list : Array[String]) => {
    for url in list {
      if !url.is_blank() && !urls.contains(url) {
        urls.push(url)
      }
    }
  }
  for item in items {
    match overrides.get(item.id) {
      Some(list) => push_unique(list)
      None => push_unique(item.pull_requests)
    }
  }
  for _, list in overrides {
    push_unique(list)
  }
  urls
}
