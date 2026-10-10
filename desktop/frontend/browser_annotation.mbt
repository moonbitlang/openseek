///|
priv struct BrowserAnnotationSession {
  id : Int
  request : String
  owner : @interop.ConversationKey
  codex : Bool
  state : @preview.Annotation
} derive(Eq)

///|
fn capture_browser_element(
  dispatch : @cmd.Emit[Msg],
  payload : @protocol.BrowserPickPayload,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.BrowserPickReply, String] = try {
        let reply : @protocol.BrowserPickReply = @interop.bridge_request(
          Local,
          @commands.browser_pick_element,
          payload,
        )
        Ok(reply)
      } catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(
        dispatch(BrowserAnnotation(Picked(request=payload.request, result))),
      )
    })
    |> ignore
  })
}

///|
fn cancel_browser_capture(
  dispatch : @cmd.Emit[Msg],
  session : BrowserAnnotationSession,
) -> @cmd.Cmd {
  browser_op(
    dispatch,
    @commands.browser_cancel_pick,
    { id: session.id, request: session.request, },
    quiet=true,
  )
}

///|
fn update_browser_annotation(
  dispatch : @cmd.Emit[Msg],
  msg : @preview.AnnotationMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match msg {
    Start => {
      guard model.is_desktop &&
        @dock.active_browser(model.dock) is Some(id) &&
        @preview.page(model.preview, id) is Some(page) &&
        page.url is Some(_) else {
        return (@cmd.none, model)
      }
      guard model.active_checkout() is Some(context) else {
        return model.notify_error(
          dispatch, "Open a chat before adding a browser annotation.",
        )
      }
      let generation = model.browser_annotation_generation + 1
      let request = generation.to_string()
      let session : BrowserAnnotationSession = {
        id,
        request,
        owner: context.owner,
        codex: model.screen is Codex,
        state: Selecting,
      }
      let cancel = model.browser_annotation.map_or(@cmd.none, old => {
        cancel_browser_capture(dispatch, old)
      })
      (
        @cmd.batch([cancel, capture_browser_element(dispatch, { id, request, })]),
        {
          ..model,
          browser_annotation: Some(session),
          browser_annotation_generation: generation,
        },
      )
    }
    Cancel => {
      let command = model.browser_annotation.map_or(@cmd.none, session => {
        cancel_browser_capture(dispatch, session)
      })
      (command, { ..model, browser_annotation: None, })
    }
    Picked(request~, result) => {
      guard model.browser_annotation is Some(session) &&
        session.request == request &&
        session.state is Selecting else {
        return (@cmd.none, model)
      }
      guard model.active_checkout() is Some(context) &&
        context.owner == session.owner &&
        (model.screen is Codex) == session.codex &&
        desired_browser_view(model) == Some(session.id) else {
        return (@cmd.none, { ..model, browser_annotation: None, })
      }
      let element = match result {
        Ok(Selected(element)) => element
        Ok(Cancelled) =>
          return (@cmd.none, { ..model, browser_annotation: None, })
        Err(error) =>
          return (
            @cmd.none,
            {
              ..model,
              browser_annotation: Some({ ..session, state: Failed(error), }),
            },
          )
      }
      let mention : @composer.Mention = {
        ref_: BrowserAnnotation(element~),
        range: None,
      }
      let model = if session.codex {
        { ..model, codex: model.codex.with_browser_annotation(mention), }
      } else if model.active_conversation() is Some(conv) {
        let draft : @composer.Draft = {
          task: conv.task,
          mentions: conv.mentions,
          images: conv.images,
        }
        model.replace_conversation({
          ..conv,
          mentions: draft.with_mention(mention).mentions,
        })
      } else {
        return (@cmd.none, model)
      }
      (@composer.focus_message_end(), { ..model, browser_annotation: None, })
    }
  }
}

///|
/// Reconcile on every transition, including chat switches and tab changes.
fn reconcile_browser_annotation(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.browser_annotation is Some(session) else {
    return (@cmd.none, model)
  }
  if model.active_checkout() is Some(context) &&
    context.owner == session.owner &&
    (model.screen is Codex) == session.codex &&
    desired_browser_view(model) == Some(session.id) {
    return (@cmd.none, model)
  }
  (
    cancel_browser_capture(dispatch, session),
    { ..model, browser_annotation: None, },
  )
}

///|
test "picking an element immediately adds a mention and preserves the existing draft" {
  let dispatch = test_dispatch()
  let original = desktop_model()
  let original = original.replace_conversation({
    ..original.active(),
    task: "Please change this",
  })
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://example.test"),
    original,
  )
  let (_, selecting) = update(dispatch, BrowserAnnotation(Start), model)
  guard selecting.browser_annotation is Some(session) else {
    fail("selection did not start")
  }
  let element : @protocol.BrowserElement = {
    url: "https://example.test",
    title: "Demo",
    tag: "button",
    selector: Some("#buy"),
    text: "Buy",
    html: "<button id=\"buy\">Buy</button>",
  }
  let (_, stale) = update(
    dispatch,
    BrowserAnnotation(Picked(request="stale", Ok(Selected(element)))),
    selecting,
  )
  assert_true(stale == selecting)
  let picked = BrowserAnnotation(
    Picked(request=session.request, Ok(Selected(element))),
  )
  let (_, attached) = update(dispatch, picked, selecting)
  assert_true(selecting.browser_annotation is Some({ state: Selecting, .. }))
  assert_true(selecting.active().mentions.is_empty())
  assert_true(attached.browser_annotation is None)
  assert_eq(attached.active().task, "Please change this")
  assert_eq(attached.active().mentions.length(), 1)
  assert_true(
    attached.active().mentions[0].ref_ is BrowserAnnotation(element=found) &&
    found == element,
  )
  let (_, duplicate) = update(dispatch, picked, attached)
  assert_eq(duplicate.active().mentions.length(), 1)
}

///|
test "browser navigation and closing cancel selection and ignore a late reply" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://example.test"),
    desktop_model(),
  )
  let (_, selecting) = update(dispatch, BrowserAnnotation(Start), model)
  guard selecting.browser_annotation is Some(session) else {
    fail("selection did not start")
  }
  let (_, navigated) = update(
    dispatch,
    Preview(LoadingChanged(id=session.id, loading=true)),
    selecting,
  )
  assert_true(navigated.browser_annotation is None)
  let (_, closed) = update(dispatch, ToggleRightPanel, selecting)
  assert_true(closed.browser_annotation is None)
  let (_, late) = update(
    dispatch,
    BrowserAnnotation(Picked(request=session.request, Err("late failure"))),
    closed,
  )
  assert_true(late == closed)
  let (_, cancelled) = update(dispatch, BrowserAnnotation(Cancel), selecting)
  assert_true(cancelled.browser_annotation is None)
  assert_true(selecting.browser_annotation is Some({ state: Selecting, .. }))
}

///|
test "switching conversation drops a pending browser annotation" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://example.test"),
    desktop_model(),
  )
  let (_, selecting) = update(dispatch, BrowserAnnotation(Start), model)
  assert_true(selecting.browser_annotation is Some(_))
  let (_, switched) = reconcile_browser_annotation(dispatch, {
    ..selecting,
    active_session: "another-chat",
  })
  assert_true(switched.browser_annotation is None)
  assert_true(selecting.browser_annotation is Some(_))
}

///|
test "browser picks attach to the Codex composer without changing the OpenSeek draft" {
  let dispatch = test_dispatch()
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-1",
      "cwd": "/work/project",
      "preview": "Review",
      "turns": [],
    },
  })
  let (_, model) = update(dispatch, CodexOpenThread("codex-thread-1"), {
    ..desktop_model(),
    codex,
  })
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://example.test"),
    model,
  )
  let (_, selecting) = update(dispatch, BrowserAnnotation(Start), model)
  guard selecting.browser_annotation is Some(session) else {
    fail("selection did not start")
  }
  let element : @protocol.BrowserElement = {
    url: "https://example.test",
    title: "Demo",
    tag: "button",
    selector: None,
    text: "Buy",
    html: "<button>Buy</button>",
  }
  let (_, attached) = update(
    dispatch,
    BrowserAnnotation(Picked(request=session.request, Ok(Selected(element)))),
    selecting,
  )
  let mention : @composer.Mention = {
    ref_: BrowserAnnotation(element~),
    range: None,
  }
  assert_true(attached.browser_annotation is None)
  assert_true(
    attached.codex == selecting.codex.with_browser_annotation(mention),
  )
  assert_true(attached.active().mentions.is_empty())
  assert_true(selecting.codex == model.codex)
}
