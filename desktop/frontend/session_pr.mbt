///|
priv struct SessionPrState {
  bindings : Array[@protocol.SessionPrBinding]
  details : Map[String, SessionPrCache]
  checkout : (String, @protocol.SessionPrDetail)?
  collapsed : Bool
  checks_url : String?
  generation : Int32
  error : String?
} derive(Eq)

///|
/// Last successful metadata can survive a failed refresh. Neither the
/// request URL nor the lookup error is part of the host's PR metadata.
priv struct SessionPrCache {
  detail : @protocol.SessionPrDetail?
  error : String?
} derive(Eq)

///|
fn SessionPrState::empty() -> SessionPrState {
  {
    bindings: [],
    details: {},
    checkout: None,
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
  checkout~ : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionPrDetail?, String] = Ok(
        @interop.bridge_request(channel, @commands.session_pr_detail, binding).detail,
      ) catch {
        error => Err(error.to_string())
      }
      let url = binding.url
      let msg = if checkout {
        PrCheckoutDetailLoaded(session~, generation~, url~, result~)
      } else {
        PrBindingDetailLoaded(session~, generation~, url~, result~)
      }
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
/// A PR and its exact head URL share one row. Repository identity is in the
/// URL, so equal branch names in different repositories never collapse.
fn Conversation::session_pr_rows(
  self : Conversation,
) -> Array[@composer.SessionPrRow] {
  let current_pr = self
    .settled_probe()
    .bind(probe => probe.pull_request)
    .map(pr => pr.url)
  let checkout = self.pr_bindings.checkout
    .filter(entry => Some(entry.0) == current_pr)
    .map(entry => entry.1)
  let current_head = match checkout.bind(detail => detail.head_url) {
    Some(url) => Some(url)
    None =>
      self
      .settled_probe()
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
  let rows : Array[@composer.SessionPrRow] = []
  for binding in bindings {
    // The PR row below owns this branch binding too, regardless of order.
    if bindings.any(other => {
        other.url != binding.url &&
        details
        .get(other.url)
        .bind(cache => cache.detail)
        .bind(detail => detail.head_url) ==
        Some(binding.url)
      }) {
      continue
    }
    let cache = details.get(binding.url)
    let detail = cache.bind(cache => cache.detail)
    let head = detail.bind(detail => detail.head_url)
    let urls = bindings
      .filter(item => item.url == binding.url || Some(item.url) == head)
      .map(item => item.url)
    let current = current_pr == Some(binding.url) ||
      current_head == Some(binding.url)
    let pr = detail.map(detail => detail.pull_request)
    let pr = if pr is Some(_) {
      pr
    } else if current {
      checkout.map(detail => detail.pull_request)
    } else {
      None
    }
    rows.push({
      url: binding.url,
      urls,
      pull_request: pr,
      head_url: if head is Some(_) {
        head
      } else {
        current_head.filter(_ => current)
      },
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
  let result : Result[@protocol.SessionPrDetail?, String] = Err("offline")
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
        PrCheckoutDetailLoaded(
          session="desktop-test",
          generation=loaded1.active().pull_request_generation,
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
  let detail : @protocol.SessionPrDetail = {
    pull_request: test_session_pr(),
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
/// Only branch associations need another lookup to prove that the current
/// PR belongs to their exact repository. Ordinary chats pay no extra gh call.
fn fetch_checkout_pr_detail(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  conv : Conversation,
) -> @cmd.Cmd {
  guard conv.pr_bindings.bindings.any(binding => binding.url.contains("/tree/")) &&
    conv.settled_probe().bind(probe => probe.pull_request) is Some(pr) else {
    return @cmd.none
  }
  try {
    let binding : @protocol.SessionPrBinding = @json.from_json({ "url": pr.url })
    fetch_pr_detail(
      emit,
      channel,
      conv.session_id,
      binding,
      generation=conv.pull_request_generation,
      checkout=true,
    )
  } catch {
    _ => @cmd.none
  }
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
  let detail : @protocol.SessionPrDetail = {
    pull_request: test_session_pr(),
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
  assert_true(
    ready.active().pr_bindings.details.get(detail.pull_request.url) is None,
  )
  let (_, failed) = update_msg(emit, reply(Err("offline")), ready)
  let rows = failed.active().session_pr_rows()
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].url, url)
  assert_true(rows[0].pull_request == Some(detail.pull_request))
  assert_true(rows[0].head_url == detail.head_url)
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
