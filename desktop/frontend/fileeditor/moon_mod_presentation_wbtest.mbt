///|
fn moon_mod_test_state() -> (State, Ctx, @pathx.Relative) raise {
  let path = @pathx.Relative("moon.mod")
  let docs = owned_state().docs.copy()
  docs[path] = loaded_doc(path.0)
  let state = { ..owned_state(), docs, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  (state, ctx, path)
}

///|
test "ordinary moon.mod defaults to source and requests its graph only when selected" {
  let (state, ctx, path) = moon_mod_test_state()
  assert_true(moon_mod_view_available(state, ctx))
  assert_false(uses_package_diagram_surface(state, ctx))
  assert_true(state.moon_mod_view_mode(path) is MoonModSource)

  let (source, _) = sync(test_emit(), state, ctx)
  assert_true(source.package_graphs.get(path) is None)
  assert_eq(source.package_graph_generation, 0)
  let (_, state) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModDependencies),
    source,
    ctx,
  )
  assert_true(uses_package_diagram_surface(state, ctx))

  let (loading, _) = sync(test_emit(), state, ctx)
  guard loading.package_graphs.get(path)
    is Some(PackageGraphLoading(generation)) else {
    fail("expected the explicitly selected dependency graph request")
  }
  assert_eq(generation, 1)
  let (still_loading, _) = sync(test_emit(), loading, ctx)
  assert_true(
    still_loading.package_graphs.get(path) ==
    Some(PackageGraphLoading(generation)),
  )
  assert_eq(still_loading.package_graph_generation, generation)
}

///|
test "package graph replies accept only the current owner epoch path and generation" {
  let (state, ctx, path) = moon_mod_test_state()
  let (_, state) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModDependencies),
    state,
    ctx,
  )
  let (loading, _) = sync(test_emit(), state, ctx)
  let stale = PackageGraphRequestLoaded(
    owner=ctx.owner,
    epoch=ctx.request_epoch,
    path~,
    generation=0,
    source="stale",
  )
  let (_, after_stale) = update(test_emit(), stale, loading, ctx)
  assert_true(after_stale == loading)

  let wrong_owner = PackageGraphRequestLoaded(
    owner={ ..ctx.owner, session: "another-session", },
    epoch=ctx.request_epoch,
    path~,
    generation=1,
    source="wrong-owner",
  )
  let (_, after_wrong_owner) = update(test_emit(), wrong_owner, loading, ctx)
  assert_true(after_wrong_owner == loading)
  let wrong_epoch = PackageGraphRequestLoaded(
    owner=ctx.owner,
    epoch=ctx.request_epoch + 1,
    path~,
    generation=1,
    source="wrong-epoch",
  )
  let (_, after_wrong_epoch) = update(test_emit(), wrong_epoch, loading, ctx)
  assert_true(after_wrong_epoch == loading)
  let wrong_path = PackageGraphRequestLoaded(
    owner=ctx.owner,
    epoch=ctx.request_epoch,
    path=Relative("nested/moon.mod"),
    generation=1,
    source="wrong-path",
  )
  let (_, after_wrong_path) = update(test_emit(), wrong_path, loading, ctx)
  assert_true(after_wrong_path == loading)

  let current = PackageGraphRequestLoaded(
    owner=ctx.owner,
    epoch=ctx.request_epoch,
    path~,
    generation=1,
    source="graph-json",
  )
  let (_, ready) = update(test_emit(), current, loading, ctx)
  assert_true(
    ready.package_graphs.get(path) == Some(PackageGraphReady(1, "graph-json")),
  )

  let late_failure = PackageGraphRequestFailed(
    owner=ctx.owner,
    epoch=ctx.request_epoch,
    path~,
    generation=1,
    message="late",
  )
  let (_, after_late_failure) = update(test_emit(), late_failure, ready, ctx)
  assert_true(after_late_failure == ready)
}

///|
test "source preserves a ready graph and failed dependency view retries explicitly" {
  let (state, ctx, path) = moon_mod_test_state()
  let (_, state) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModDependencies),
    state,
    ctx,
  )
  let package_graphs = state.package_graphs.copy()
  package_graphs[path] = PackageGraphReady(4, "cached")
  let ready = { ..state, package_graphs, package_graph_generation: 4, }
  let (_, source) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModSource),
    ready,
    ctx,
  )
  assert_true(source.moon_mod_view_mode(path) is MoonModSource)
  assert_false(uses_package_diagram_surface(source, ctx))
  assert_true(
    source.package_graphs.get(path) == Some(PackageGraphReady(4, "cached")),
  )

  let (_, dependencies) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModDependencies),
    source,
    ctx,
  )
  assert_true(uses_package_diagram_surface(dependencies, ctx))
  assert_true(
    dependencies.package_graphs.get(path) ==
    Some(PackageGraphReady(4, "cached")),
  )

  let failed_graphs = dependencies.package_graphs.copy()
  failed_graphs[path] = PackageGraphFailed(5, "moon failed")
  let failed = {
    ..dependencies,
    package_graphs: failed_graphs,
    package_graph_generation: 5,
  }
  let (_, source_after_failure) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModSource),
    failed,
    ctx,
  )
  assert_true(source_after_failure.moon_mod_view_mode(path) is MoonModSource)
  assert_true(
    source_after_failure.package_graphs.get(path) ==
    Some(PackageGraphFailed(5, "moon failed")),
  )
  let (_, retrying) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModDependencies),
    source_after_failure,
    ctx,
  )
  assert_true(retrying.package_graphs.get(path) is None)
  let (loading, _) = sync(test_emit(), retrying, ctx)
  assert_true(loading.package_graphs.get(path) == Some(PackageGraphLoading(6)))
}

///|
test "positioned moon.mod opens source and close forgets all graph state" {
  let (state, ctx, path) = moon_mod_test_state()
  let (_, state) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModDependencies),
    state,
    ctx,
  )
  let (_, positioned) = open_document(
    test_emit(),
    state,
    ctx,
    path,
    name="moon.mod",
    range=Some(Range(1, 1, 1, 5)),
    had_active=true,
  )
  assert_true(positioned.moon_mod_view_mode(path) is MoonModSource)

  let graphs = positioned.package_graphs.copy()
  graphs[path] = PackageGraphReady(1, "cached")
  let positioned = { ..positioned, package_graphs: graphs, }
  let (_, closed) = close_document(
    test_emit(),
    positioned,
    { ..ctx, open_files: [], active_file: None, },
    path,
    next=None,
    was_active=true,
  )
  assert_true(closed.moon_mod_view_modes.get(path) is None)
  assert_true(closed.package_graphs.get(path) is None)
  assert_true(closed.moon_mod_view_mode(path) is MoonModSource)
}

///|
test "reviewed and historical moon.mod views remain source-only" {
  let (state, ctx, path) = moon_mod_test_state()
  let (_, state) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModDependencies),
    state,
    ctx,
  )
  let docs = state.docs.copy()
  docs[path] = {
    ..docs[path],
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("name = \"old/app\""),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let reviewed = { ..state, docs, }
  assert_false(moon_mod_view_available(reviewed, ctx))
  assert_false(uses_package_diagram_surface(reviewed, ctx))
  let (_, after_toggle) = update(
    test_emit(),
    MoonModViewModeSelected(MoonModSource),
    reviewed,
    ctx,
  )
  assert_true(after_toggle == reviewed)
  let (after_sync, _) = sync(test_emit(), reviewed, ctx)
  assert_true(after_sync.package_graphs.get(path) is None)

  let history = {
    ..ctx,
    active_file: None,
    active_history_diff: Some({
      commit: "commit",
      parent: Some("parent"),
      path,
      original_path: None,
      status: "M",
      kind: "modified",
    }),
  }
  assert_false(moon_mod_view_available(state, history))
  assert_false(uses_package_diagram_surface(state, history))
}

///|
test "package graph invalidation covers manifests but not source edits" {
  assert_true(Modified(Relative("moon.mod")).package_graph_relevant())
  assert_true(Modified(Relative("nested/moon.pkg")).package_graph_relevant())
  assert_true(
    Renamed(old=Relative("old/moon.work"), new=Relative("new/moon.work")).package_graph_relevant(),
  )
  assert_false(Modified(Relative("src/main.mbt")).package_graph_relevant())
  assert_false(
    Modified(Relative("notes/moon.mod.bak")).package_graph_relevant(),
  )
}

///|
test "watcher baseline invalidates a graph cached across its observation gap" {
  let (state, ctx, path) = moon_mod_test_state()
  let package_graphs = state.package_graphs.copy()
  package_graphs[path] = PackageGraphReady(3, "cached")
  let state = { ..state, package_graphs, package_graph_generation: 3, }
  let (_, invalidated) = update(
    test_emit(),
    FsChanged(
      root=ctx.test_root(),
      generation=ctx.watch_identity(state.watch_generation),
      changes=None,
    ),
    state,
    ctx,
  )
  assert_true(invalidated.package_graphs.get(path) is None)
}
