///|
test "ordinary MBTI tabs default to diagram and toggle without replacing the document" {
  let path = @pathx.Relative("api/pkg.generated.mbti")
  let docs = owned_state().docs.copy()
  docs[path] = loaded_doc(path.0)
  let state = { ..owned_state(), docs, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }

  assert_true(mbti_view_available(state, ctx))
  assert_true(uses_mbti_diagram_surface(state, ctx))
  assert_true(state.mbti_view_mode(path) is MbtiDiagram)

  let (_, source) = update(
    test_emit(),
    MbtiViewModeSelected(MbtiSource),
    state,
    ctx,
  )
  assert_true(source.mbti_view_mode(path) is MbtiSource)
  assert_false(uses_mbti_diagram_surface(source, ctx))
  assert_true(source.docs.get(path) == state.docs.get(path))

  let (_, diagram) = update(
    test_emit(),
    MbtiViewModeSelected(MbtiDiagram),
    source,
    ctx,
  )
  assert_true(diagram.mbti_view_mode(path) is MbtiDiagram)
  assert_true(uses_mbti_diagram_surface(diagram, ctx))
}

///|
test "reviewed MBTI files keep source and reject the diagram toggle" {
  let path = @pathx.Relative("api/pkg.generated.mbti")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = reviewed_doc(
    path,
    selected,
    baseline="package \"old\"",
    view_mode=ReviewSource,
  )
  let state = { ..owned_state(), docs, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }

  assert_false(mbti_view_available(state, ctx))
  assert_false(uses_mbti_diagram_surface(state, ctx))
  let (_, after) = update(
    test_emit(),
    MbtiViewModeSelected(MbtiSource),
    state,
    ctx,
  )
  assert_true(after == state)
}

///|
test "positioned MBTI opens use source and closing forgets the tab preference" {
  let path = @pathx.Relative("api/pkg.generated.mbti")
  let docs = owned_state().docs.copy()
  docs[path] = loaded_doc(path.0)
  let state = { ..owned_state(), docs, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }

  let (_, positioned) = open_document(
    test_emit(),
    state,
    ctx,
    path,
    name="pkg.generated.mbti",
    range=Some(@common.Range(3, 1, 3, 8)),
    had_active=true,
  )
  assert_true(positioned.mbti_view_mode(path) is MbtiSource)

  let (_, closed) = close_document(
    test_emit(),
    positioned,
    { ..ctx, open_files: [], active_file: None, },
    path,
    next=None,
    was_active=true,
  )
  assert_true(closed.mbti_view_modes.get(path) is None)
  assert_true(closed.mbti_view_mode(path) is MbtiDiagram)
}

///|
test "non-MBTI documents do not expose or accept MBTI presentation" {
  let path = @pathx.Relative("src/main.mbt")
  let docs = owned_state().docs.copy()
  docs[path] = loaded_doc(path.0)
  let state = { ..owned_state(), docs, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  assert_false(mbti_view_available(state, ctx))
  let (_, after) = update(
    test_emit(),
    MbtiViewModeSelected(MbtiSource),
    state,
    ctx,
  )
  assert_true(after == state)
}
