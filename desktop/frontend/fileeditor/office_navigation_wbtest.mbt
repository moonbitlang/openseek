///|
test "Office navigation waits for a document and consumes only the current click" {
  let (state, ctx, path) = office_selection_fixture()
  let navigation : OfficeCitationNavigation = {
    owner: ctx.owner,
    epoch: state.request_epoch,
    generation: state.file_link_generation,
    path,
    target: WordParagraph("/docx/body/p[1]"),
  }
  let state = { ..state, office_navigation: Some(navigation), }
  let (_, done) = state.sync_office_navigation(test_emit(), ctx)
  assert_eq(done.office_navigation, None)
  assert_eq(done.error, None)
  let docs = state.docs.copy()
  docs[path] = { ..docs[path], state: TabLoading, }
  let (_, loading) = { ..state, docs, }.sync_office_navigation(test_emit(), ctx)
  assert_eq(loading.office_navigation, Some(navigation))
  for
    retired in [
      { ..state, file_link_generation: state.file_link_generation + 1, },
      { ..state, request_epoch: state.request_epoch + 1, },
      {
        ..state,
        owner: Some(
          @interop.Host({ ..ctx.owner.host().unwrap(), session: "another", }),
        ),
      },
    ] {
    let (_, retired) = retired.sync_office_navigation(test_emit(), ctx)
    assert_eq(retired.office_navigation, None)
    assert_eq(retired.error, None)
  }
  let (_, switched) = state.sync_office_navigation(test_emit(), {
    ..ctx,
    active_file: Some(test_file("other.docx")),
  })
  assert_eq(switched.office_navigation, None)
}

///|
test "PDF citations wait for readiness and never clamp a missing page" {
  let (state, ctx, path, pdf) = pdf_fixture()
  let navigation : OfficeCitationNavigation = {
    owner: ctx.owner,
    epoch: state.request_epoch,
    generation: state.file_link_generation,
    path,
    target: PdfPage(2),
  }
  let state = { ..state, office_navigation: Some(navigation), }
  for status in [PdfStatus::PdfLoading, PdfPasswordRequired(incorrect=false)] {
    let pending = state.with_pdf_document(path, { ..pdf, status, })
    let (_, pending) = pending.sync_office_navigation(test_emit(), ctx)
    assert_eq(pending.office_navigation, Some(navigation))
  }
  let ready = state.with_pdf_document(path, {
    ..pdf,
    status: PdfReady,
    pages: Some(2),
  })
  let (_, done) = ready.sync_office_navigation(test_emit(), ctx)
  assert_eq(done.office_navigation, None)
  assert_eq(done.error, None)
  let invalid = {
    ..ready,
    office_navigation: Some({ ..navigation, target: PdfPage(3), }),
  }
  let (_, invalid) = invalid.sync_office_navigation(test_emit(), ctx)
  assert_eq(invalid.office_navigation, None)
  assert_true(invalid.error is Some(_))
  assert_eq(pdf_in(invalid, path).page, 1)
}

///|
test "stale navigation results do not show errors in a newer destination" {
  let (state, ctx, path) = office_selection_fixture()
  let navigation : OfficeCitationNavigation = {
    owner: ctx.owner,
    epoch: state.request_epoch,
    generation: state.file_link_generation,
    path,
    target: WordHeading("Missing"),
  }
  let (_, failed) = update(
    test_emit(),
    OfficeCitationLocated(navigation, false),
    state,
    ctx,
  )
  assert_true(failed.error is Some(_))
  let (_, ignored) = update(
    test_emit(),
    OfficeCitationLocated(
      { ..navigation, generation: navigation.generation - 1, },
      false,
    ),
    state,
    ctx,
  )
  assert_eq(ignored.error, None)
}
