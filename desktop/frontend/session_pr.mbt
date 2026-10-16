///|
priv struct SessionPrState {
  bindings : Array[@protocol.SessionPrBinding]
  details : Map[String, SessionPrCache]
  collapsed : Bool
  checks_url : String?
  generation : Int32
  error : String?
} derive(Eq)

///|
/// Last successful metadata can survive a failed refresh. Neither the
/// request URL nor the lookup error is part of the host's PR metadata.
priv struct SessionPrCache {
  detail : @protocol.GitPullRequest?
  error : String?
} derive(Eq)

///|
fn SessionPrState::empty() -> SessionPrState {
  {
    bindings: [],
    details: {},
    collapsed: false,
    checks_url: None,
    generation: 0,
    error: None,
  }
}

///|
fn probe_pr_bindings(
  emit : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
  session : String,
) -> (@cmd.Cmd, Model) {
  guard model.find_conversation(channel, session) is Some(conv) else {
    return (@cmd.none, model)
  }
  let (generation, model) = model.mint_git_request()
  let state = { ..conv.pr_bindings, generation, }
  (
    fetch_pr_bindings(emit, channel, session, generation),
    model.replace_conversation({ ..conv, pr_bindings: state, }),
  )
}

///|
fn fetch_pr_bindings(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  generation : Int32,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionPrBindings, String] = Ok(
        @interop.bridge_request(channel, @commands.session_pr_list, { session, }),
      ) catch {
        error => Err(error.to_string())
      }
      scheduler.add(
        emit(
          FromDevice(channel, PrBindingsLoaded(session~, generation~, result~)),
        ),
      )
    })
    |> ignore
  })
}

///|
fn fetch_pr_detail(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  binding : @protocol.SessionPrBinding,
  generation~ : Int32,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.GitPullRequest?, String] = Ok(
        @interop.bridge_request(channel, @commands.git_pr_detail, {
          url: binding.url,
        }).pull_request,
      ) catch {
        error => Err(error.to_string())
      }
      let url = binding.url
      let msg = PrBindingDetailLoaded(session~, generation~, url~, result~)
      scheduler.add(emit(FromDevice(channel, msg)))
    })
    |> ignore
  })
}

///|
fn remove_pr_bindings(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  urls : Array[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      try {
        for url in urls {
          ignore(
            @interop.bridge_request(channel, @commands.session_pr_remove, {
              session,
              url,
            }),
          )
        }
        scheduler.add(emit(FromDevice(channel, PrBindingsChanged(session~))))
      } catch {
        error =>
          scheduler.add(
            emit(
              FromDevice(
                channel,
                PrBindingRemoveFailed(session~, message=error.to_string()),
              ),
            ),
          )
      }
    })
    |> ignore
  })
}

///|
/// Project checkout facts and explicit associations into one list. Automatic
/// membership is never saved: changing branches replaces it immediately.
fn Conversation::session_pr_rows(
  self : Conversation,
) -> Array[@composer.SessionPrRow] {
  let probe = self.settled_probe()
  let current_pr = probe.bind(probe => probe.pull_request)
  let current_head = match current_pr.bind(pr => pr.head_url) {
    Some(url) => Some(url)
    None =>
      probe
      .bind(probe => probe.compare_url)
      .bind(url => {
        match url.split("/compare/").collect() {
          [repo, branch] =>
            Some(
              repo.to_owned() +
              "/tree/" +
              branch.strip_suffix("?expand=1").unwrap_or(branch).to_owned(),
            )
          _ => None
        }
      })
  }
  let details = self.pr_bindings.details
  let bindings = self.pr_bindings.bindings
  // A PR can be created and bound after the checkout probe answered with
  // only a published branch. Its exact head URL is sufficient evidence to
  // enrich that same row without waiting for another checkout probe.
  let bound_current = match current_head {
    Some(head) =>
      bindings
      .iter()
      .filter_map(binding => details.get(binding.url))
      .find_first(cache => cache.detail.bind(pr => pr.head_url) == Some(head))
    None => None
  }
  let current_error = if current_pr is None {
    bound_current.bind(cache => cache.error)
  } else {
    None
  }
  let current_pr = match current_pr {
    Some(pr) => Some(pr)
    None => bound_current.bind(cache => cache.detail)
  }
  let rows : Array[@composer.SessionPrRow] = []
  let consumed : Set[String] = Set([])
  if self.branch is Some(branch) && !branch.is_empty() {
    let urls = bindings
      .filter(binding => {
        Some(binding.url) == current_pr.map(pr => pr.url) ||
        Some(binding.url) == current_head ||
        (
          current_pr is Some(pr) &&
          details
          .get(binding.url)
          .bind(cache => cache.detail)
          .map(detail => detail.url) ==
          Some(pr.url)
        )
      })
      .map(binding => binding.url)
    for url in urls {
      consumed.add(url)
    }
    rows.push({
      url: match current_pr {
        Some(pr) => Some(pr.url)
        None => current_head
      },
      urls,
      current: true,
      branch: Some(branch),
      pull_request: current_pr,
      changes: self.diffstat.map(stat => {
        added: stat.added,
        removed: stat.removed,
        files: stat.files,
        base: stat.base,
        partial: stat.partial,
      }),
      error: current_error,
    })
  }
  for binding in bindings {
    if consumed.contains(binding.url) {
      continue
    }
    // Prefer the PR over its branch URL, irrespective of saved order.
    if bindings.any(other => {
        !consumed.contains(other.url) &&
        other.url != binding.url &&
        details
        .get(other.url)
        .bind(cache => cache.detail)
        .bind(pr => pr.head_url) ==
        Some(binding.url)
      }) {
      continue
    }
    let cache = details.get(binding.url)
    let pr = cache.bind(cache => cache.detail)
    let urls = bindings
      .filter(item => {
        !consumed.contains(item.url) &&
        (
          item.url == binding.url ||
          Some(item.url) == pr.bind(pr => pr.head_url) ||
          (
            pr is Some(pr) &&
            details
            .get(item.url)
            .bind(cache => cache.detail)
            .map(other => other.url) ==
            Some(pr.url)
          )
        )
      })
      .map(item => item.url)
    for url in urls {
      consumed.add(url)
    }
    rows.push({
      url: Some(binding.url),
      urls,
      current: false,
      branch: None,
      pull_request: pr,
      changes: None,
      error: cache.bind(cache => cache.error),
    })
  }
  rows
}

///|
test "session PR updates are pure and fence replies superseded by a notification" {
  let model = test_model()
  let emit = test_dispatch()
  let changed = FromDevice(Local, PrBindingsChanged(session="desktop-test"))
  let (_, first) = update_msg(emit, changed, model)
  let (_, repeated) = update_msg(emit, changed, model)
  assert_true(first.active().pr_bindings == repeated.active().pr_bindings)
  assert_eq(first.git_request_generation, repeated.git_request_generation)
  let generation = first.active().pr_bindings.generation
  let snapshot : @protocol.SessionPrBindings = @json.from_json({
    "bindings": [{ "url": "https://github.com/o/r/pull/1" }],
  })
  let loaded = FromDevice(
    Local,
    PrBindingsLoaded(session="desktop-test", generation~, result=Ok(snapshot)),
  )
  let (_, loaded1) = update_msg(emit, loaded, first)
  let (_, loaded2) = update_msg(emit, loaded, first)
  assert_true(loaded1.active().pr_bindings == loaded2.active().pr_bindings)
  assert_eq(first.active().pr_bindings.bindings.length(), 0)
  let (_, newer) = update_msg(emit, changed, loaded1)
  let stale = FromDevice(
    Local,
    PrBindingsLoaded(
      session="desktop-test",
      generation~,
      result=Ok(@protocol.SessionPrBindings::empty()),
    ),
  )
  let (_, kept) = update_msg(emit, stale, newer)
  assert_eq(kept.active().pr_bindings.bindings.length(), 1)
  let url = snapshot.bindings[0].url
  let result : Result[@protocol.GitPullRequest?, String] = Err("offline")
  for
    msg in [
      FromDevice(
        Local,
        PrBindingDetailLoaded(
          session="desktop-test",
          generation~,
          url~,
          result~,
        ),
      ),
      FromDevice(
        Local,
        PrBindingRemoveFailed(session="desktop-test", message="disk full"),
      ),
      FromDevice(
        Local,
        PrBindingsLoaded(
          session="desktop-test",
          generation~,
          result=Err("unreadable"),
        ),
      ),
    ] {
    let (_, a) = update_msg(emit, msg, loaded1)
    let (_, b) = update_msg(emit, msg, loaded1)
    assert_true(a.active().pr_bindings == b.active().pr_bindings)
    assert_eq(a.active().pr_bindings.bindings.length(), 1)
  }
  assert_true(loaded1.active().pr_bindings.details.is_empty())
}

///|
test "PR and exact branch URLs merge without confusing another repository" {
  let bindings : @protocol.SessionPrBindings = @json.from_json({
    "bindings": [
      { "url": "https://github.com/o/r/tree/topic" },
      { "url": "https://github.com/other/r/tree/topic" },
      { "url": "https://github.com/o/r/pull/1" },
    ],
  })
  let detail : @protocol.GitPullRequest = {
    ..test_session_pr(),
    head_url: Some("https://github.com/o/r/tree/topic"),
  }
  let conv = {
    ..test_model().active(),
    pr_bindings: {
      ..SessionPrState::empty(),
      bindings: bindings.bindings,
      details: Map::from_array([
        (bindings.bindings[2].url, { detail: Some(detail), error: None, }),
      ]),
    },
  }
  let rows = conv.session_pr_rows()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].urls, ["https://github.com/other/r/tree/topic"])
  assert_eq(rows[1].urls.length(), 2)
}

///|
fn test_session_pr() -> @protocol.GitPullRequest {
  {
    number: 1,
    title: "Example PR",
    state: "open",
    draft: false,
    url: "https://github.com/o/r/pull/1",
    base: "main",
    additions: 1,
    deletions: 0,
    changed_files: 1,
    checks: None,
    head_url: None,
  }
}

///|
test "PR lookup keeps request identity and cached metadata through failure and recovery" {
  let model = test_model()
  let emit = test_dispatch()
  // The requested URL can differ from the canonical URL returned by GitHub.
  let url = "https://github.com/old/r/pull/1"
  let snapshot : @protocol.SessionPrBindings = @json.from_json({
    "bindings": [{ "url": url }],
  })
  let generation = model.active().pr_bindings.generation
  let (_, model) = update_msg(
    emit,
    FromDevice(
      Local,
      PrBindingsLoaded(session="desktop-test", generation~, result=Ok(snapshot)),
    ),
    model,
  )
  let detail : @protocol.GitPullRequest = {
    ..test_session_pr(),
    head_url: Some("https://github.com/fork/r/tree/topic"),
  }
  fn reply(result) {
    FromDevice(
      Local,
      PrBindingDetailLoaded(session="desktop-test", generation~, url~, result~),
    )
  }
  let (_, ready) = update_msg(emit, reply(Ok(Some(detail))), model)
  assert_true(
    ready.active().pr_bindings.details.get(url)
    is Some({ detail: Some(_), error: None, }),
  )
  assert_true(ready.active().pr_bindings.details.get(detail.url) is None)
  let (_, failed) = update_msg(emit, reply(Err("offline")), ready)
  let rows = failed.active().session_pr_rows()
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].url, Some(url))
  assert_true(rows[0].pull_request == Some(detail))
  assert_true(rows[0].pull_request.bind(pr => pr.head_url) == detail.head_url)
  assert_true(rows[0].error == Some("offline"))
  assert_true(ready.active().session_pr_rows()[0].error is None)
  let (_, recovered) = update_msg(emit, reply(Ok(Some(detail))), failed)
  assert_true(recovered.active().session_pr_rows()[0].error is None)
  let (_, absent) = update_msg(emit, reply(Ok(None)), recovered)
  assert_true(absent.active().session_pr_rows()[0].pull_request is None)
  assert_true(absent.active().session_pr_rows()[0].error is None)
  assert_eq(absent.active().pr_bindings.bindings.length(), 1)
  let (_, newer) = update_msg(
    emit,
    FromDevice(Local, PrBindingsChanged(session="desktop-test")),
    recovered,
  )
  let (_, ignored) = update_msg(emit, reply(Ok(None)), newer)
  assert_true(ignored.active().pr_bindings == newer.active().pr_bindings)
}

///|
test "binding panel toggles are pure and fenced by composer identity" {
  let model = test_model()
  let emit = test_dispatch()
  let identity = model.composer_input().identity
  for
    action in [
      @composer.PrBindingsToggled(identity~),
      @composer.PrChecksToggled(identity~, url="https://github.com/o/r/pull/1"),
    ] {
    let (_, changed) = update_msg(emit, ComposerAction(action), model)
    let (_, repeated) = update_msg(emit, ComposerAction(action), model)
    assert_true(changed.active().pr_bindings == repeated.active().pr_bindings)
    assert_true(changed.active().pr_bindings != model.active().pr_bindings)
    let (_, restored) = update_msg(emit, ComposerAction(action), changed)
    assert_true(restored.active().pr_bindings == model.active().pr_bindings)
  }
  let retired = { ..model, composer_entry_retirements: [identity.owner], }
  let (_, ignored) = update_msg(
    emit,
    ComposerAction(@composer.PrBindingsToggled(identity~)),
    retired,
  )
  assert_true(ignored.active().pr_bindings == retired.active().pr_bindings)
}

///|
test "automatic checkout rows survive unbinding and follow branch changes" {
  let pr = {
    ..test_session_pr(),
    head_url: Some("https://github.com/fork/r/tree/topic"),
  }
  let bindings : @protocol.SessionPrBindings = @json.from_json({
    "bindings": [
      { "url": pr.url },
      { "url": "https://github.com/fork/r/tree/topic" },
      { "url": "https://github.com/other/r/tree/topic" },
    ],
  })
  let conv = {
    ..test_model().active(),
    branch: Some("topic"),
    pull_request: Some({
      branch: "topic",
      probing: false,
      stale: false,
      pull_request: Some(pr),
      compare_url: None,
    }),
    pr_bindings: { ..SessionPrState::empty(), bindings: bindings.bindings, },
  }
  let rows = conv.session_pr_rows()
  assert_eq(rows.length(), 2)
  assert_true(rows[0].current)
  assert_eq(rows[0].urls.length(), 2)
  assert_true(rows[0].pull_request == Some(pr))
  assert_false(rows[1].current)
  let unbound = { ..conv, pr_bindings: SessionPrState::empty(), }
  let rows = unbound.session_pr_rows()
  assert_eq(rows.length(), 1)
  assert_true(rows[0].current && rows[0].urls.is_empty())
  // A stale PR response cannot label a new checkout; local data remains useful
  // without GitHub, a published branch, or an enabled host MCP entry.
  let switched = {
    ..unbound,
    branch: Some("local/new"),
    diffstat: Some({
      added: 8,
      removed: 2,
      files: 1,
      base: None,
      partial: true,
    }),
  }
  let rows = switched.session_pr_rows()
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].branch, Some("local/new"))
  assert_true(rows[0].url is None && rows[0].pull_request is None)
  assert_true(rows[0].changes is Some({ added: 8, partial: true, .. }))
  assert_eq({ ..switched, branch: Some(""), }.session_pr_rows().length(), 0)
  assert_eq({ ..switched, branch: None, }.session_pr_rows().length(), 0)
}

///|
test "a published checkout branch merges only its exact remote binding" {
  let bindings : @protocol.SessionPrBindings = @json.from_json({
    "bindings": [
      { "url": "https://github.com/o/r/tree/topic" },
      { "url": "https://github.com/fork/r/tree/topic" },
    ],
  })
  let conv = {
    ..test_model().active(),
    branch: Some("topic"),
    pull_request: Some({
      branch: "topic",
      probing: false,
      stale: false,
      pull_request: None,
      compare_url: Some("https://github.com/o/r/compare/topic?expand=1"),
    }),
    pr_bindings: { ..SessionPrState::empty(), bindings: bindings.bindings, },
  }
  let rows = conv.session_pr_rows()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].urls, ["https://github.com/o/r/tree/topic"])
  assert_eq(rows[1].urls, ["https://github.com/fork/r/tree/topic"])
}

///|
test "a newly bound PR enriches the already discovered branch before the next checkout probe" {
  let head = "https://github.com/o/r/tree/topic"
  let pr = { ..test_session_pr(), head_url: Some(head), }
  let bindings : @protocol.SessionPrBindings = @json.from_json({
    "bindings": [{ "url": head }, { "url": pr.url }],
  })
  let conv = {
    ..test_model().active(),
    branch: Some("topic"),
    pull_request: Some({
      branch: "topic",
      probing: false,
      stale: false,
      pull_request: None,
      compare_url: Some("https://github.com/o/r/compare/topic?expand=1"),
    }),
    pr_bindings: {
      ..SessionPrState::empty(),
      bindings: bindings.bindings,
      details: Map::from_array([(pr.url, { detail: Some(pr), error: None, })]),
    },
  }
  let rows = conv.session_pr_rows()
  assert_eq(rows.length(), 1)
  assert_true(rows[0].current && rows[0].pull_request == Some(pr))
  assert_eq(rows[0].urls, [head, pr.url])
  let unbound = { ..conv, pr_bindings: SessionPrState::empty(), }.session_pr_rows()
  assert_eq(unbound.length(), 1)
  assert_true(unbound[0].pull_request is None)
  assert_eq(unbound[0].url, Some(head))
  assert_true(unbound[0].urls.is_empty())
}
