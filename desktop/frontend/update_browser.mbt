// Browser dock navigation, native-view placement, and transition coverage.

///|
/// Whether a full-screen surface is drawn over the window. Every overlay
/// `view.mbt` appends after the shell (see its trailing `children.push`
/// block) belongs here: native views z-order above all HTML, so an overlay
/// this predicate forgets renders with the browser pane punched through it,
/// swallowing the clicks that land there.
fn covering_overlay(model : Model) -> Bool {
  model.workspace_picker is Some(_) ||
  model.archive_confirm is Some(_) ||
  model.quick_open is Some(_) ||
  model.update_ux is ConfirmingRestart(_) ||
  // Best effort: with the bridge gone the hide op may not deliver.
  model.bridge_state() is BridgeLost(_)
}

///|
/// Which browser page's native view belongs on screen: the active Browser
/// tab's, once it has a URL (a blank tab has no view yet) — and only while
/// the pane is actually visible and uncovered. Native views z-order above
/// all HTML, so anything the frontend draws over the pane area — the `+`
/// launcher popup, the narrow layout's sidebar drawer, the topbar app
/// launcher, the composer's git popover, and every `covering_overlay` — must
/// hide the view rather than fight it.
fn desired_browser_view(model : Model) -> Int? {
  guard model.is_desktop &&
    model.screen is Chat &&
    model.dock.open &&
    !model.dock.menu_open &&
    !model.launcher.open &&
    !model.git_details_open &&
    !(model.narrow && model.sidebar_open) &&
    !covering_overlay(model) else {
    return None
  }
  guard @dock.active_browser(model.dock) is Some(id) &&
    @preview.page(model.preview, id) is Some(page) &&
    page.url is Some(_) else {
    return None
  }
  Some(id)
}

///|
fn browser_geometry(model : Model) -> BrowserGeometry {
  {
    desired: desired_browser_view(model),
    sidebar_open: model.sidebar_open,
    narrow: model.narrow,
    terminal_open: model.terminal_panel.open,
    tree_layout: model.tree_layout,
  }
}

///|
/// Reconcile the native view with the pane after every message. Hiding is
/// immediate; showing waits for a fresh pane measurement (the measured
/// rectangle comes back as `BrowserPaneMeasured`, which sends the bounds
/// and then the visibility flip). The geometry signature keeps this pass
/// from re-measuring when nothing placement-relevant changed — including
/// after the measurement message itself, which never alters the signature.
fn sync_browser_view(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (Model, @cmd.Cmd) {
  let pane = model.browser_pane
  match desired_browser_view(model) {
    None =>
      match pane.shown {
        Some(old) =>
          (
            { ..model, browser_pane: { shown: None, rect: None, geo: None } },
            browser_set_visible(dispatch, old, false),
          )
        None =>
          if pane.geo is Some(_) {
            // A measurement was requested but the view left the screen
            // before it landed; forget it so a later show re-measures.
            (
              { ..model, browser_pane: { shown: None, rect: None, geo: None } },
              @cmd.none,
            )
          } else {
            (model, @cmd.none)
          }
      }
    Some(_) => {
      let geo = browser_geometry(model)
      if pane.geo == Some(geo) {
        (model, @cmd.none)
      } else {
        (
          { ..model, browser_pane: { ..pane, geo: Some(geo) } },
          @cmd.batch([
            watch_browser_pane(dispatch),
            measure_browser_pane(dispatch),
          ]),
        )
      }
    }
  }
}

///|
/// Test-only: a desktop-shaped model (browser tabs exist only where the
/// native views do), after one settling dispatch so the per-conversation
/// sync passes have claimed their owners — as any real first message has
/// long done before a tab can open.
fn desktop_model() -> Model {
  let model = { ..test_model(), is_desktop: true }
  let (_, model) = update(test_dispatch(), TranscriptPinned(true), model)
  model
}

///|
test "launcher rows open Browse, Files, and Review destinations" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, Dock(TogglePanel), model)
  let (_, model) = update(dispatch, Dock(MenuToggled), model)
  assert_true(model.dock.menu_open)
  let (_, model) = update(dispatch, BrowserTabRequested, model)
  assert_false(model.dock.menu_open)
  assert_true(@dock.active_browser(model.dock) == Some(1))
  let page = @preview.page(model.preview, 1).unwrap()
  assert_true(page.url is None)
  assert_false(page.loading)
  let (_, model) = update(dispatch, FilePickerRequested, model)
  assert_true(model.dock.active == Some(@dock.DockTab::FilePicker))
  assert_true(model.file_panel.explorer_mode is ExplorerFiles)
  assert_true(
    model.dock.tabs == [@dock.DockTab::Browser(id=1), @dock.DockTab::FilePicker],
  )
  let (_, model) = update(dispatch, ReviewRequested, model)
  assert_true(model.dock.active == Some(@dock.DockTab::FilePicker))
  assert_true(model.file_panel.explorer_mode is ExplorerChanges)
  assert_true(model.file_panel.changes is ChangeListLoading(_))
  // Files is an explicit destination even after Review selected Changes.
  let (_, model) = update(dispatch, FilePickerRequested, model)
  assert_true(model.file_panel.explorer_mode is ExplorerFiles)
}

///|
test "a tree pick fulfills the active picker in place" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, Dock(TogglePanel), model)
  let (_, model) = update(dispatch, FilePickerRequested, model)
  let (_, model) = update(
    dispatch,
    FileEditor(FileSelected(path=Relative("src/main.mbt"), name="main.mbt")),
    model,
  )
  assert_true(
    model.dock.tabs == [@dock.DockTab::File(path=Relative("src/main.mbt"))],
  )
  assert_true(@dock.active_file(model.dock) == Some(Relative("src/main.mbt")))
}

///|
test "a changed row opens the file tab in review mode" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, Dock(TogglePanel), model)
  let (_, model) = update(dispatch, FilePickerRequested, model)
  let path = @pathx.Relative("src/main.mbt")
  let (_, model) = update(
    dispatch,
    FileEditor(
      ChangedFileSelected({
        path,
        original_path: None,
        index_status: " ",
        worktree_status: "M",
        kind: ChangeModified,
      }),
    ),
    model,
  )
  assert_true(model.dock.tabs == [@dock.DockTab::File(path~)])
  assert_true(@dock.active_file(model.dock) == Some(path))
  assert_true(
    model.file_panel.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 1, baseline: ReviewLoading, .. }),
        ..,
      }
    ),
  )
}

///|
test "file rows and location jumps cannot open while checkout placement is missing" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = desktop_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(workspace),
      worktree: Some("wt"),
    })
    .with_dev(dev => {
      ..dev,
      workspaces: [workspace],
      worktrees: [
        {
          workspace,
          rows: [{ name: "wt", session: Some("desktop-test"), present: false }],
          generation: 1,
        },
      ],
    })
  let path = @pathx.Relative("src/main.mbt")
  let (_, ordinary) = update(
    dispatch,
    FileEditor(FileSelected(path~, name="main.mbt")),
    model,
  )
  assert_false(ordinary.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(ordinary.file_panel.docs.contains(path))
  let (_, review) = update(
    dispatch,
    FileEditor(
      ChangedFileSelected({
        path,
        original_path: None,
        index_status: " ",
        worktree_status: "M",
        kind: ChangeModified,
      }),
    ),
    model,
  )
  assert_false(review.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(review.file_panel.docs.contains(path))
  let (_, jumped) = update(
    dispatch,
    JumpToLocation(
      path="/proj/src/main.mbt",
      range=Some(@common.Range::Range(1, 1, 1, 1)),
      annotation=None,
    ),
    model,
  )
  assert_false(jumped.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(jumped.file_panel.docs.contains(path))
  let (_, navigation) = update(
    dispatch,
    FileEditor(
      OpenNavigationLocation(
        owner=file_ctx(model).owner,
        path~,
        range=@common.Range::Range(1, 1, 1, 1),
      ),
    ),
    model,
  )
  assert_false(navigation.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(navigation.file_panel.docs.contains(path))
}

///|
test "web links open (and reuse) a dock browser tab; other schemes do not" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_true(model.dock.open)
  assert_true(@dock.active_browser(model.dock) == Some(1))
  assert_true(
    @preview.page(model.preview, 1).unwrap().url ==
    Some("http://127.0.0.1:5173/"),
  )
  // xterm's link addon enters through a terminal message but follows the same
  // navigation path as a transcript anchor.
  let (_, model) = update(
    dispatch,
    Terminal(@terminal.LinkActivated(url="https://terminal.example/docs")),
    model,
  )
  assert_eq(model.dock.tabs.length(), 2)
  assert_true(@dock.active_browser(model.dock) == Some(2))
  assert_true(
    @preview.page(model.preview, 2).unwrap().url ==
    Some("https://terminal.example/docs"),
  )
  // The same URL re-activates the existing tab instead of duplicating.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 2)
  assert_eq(model.preview.pages.length(), 2)
  // External sites are web pages too: they get their own tab.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://github.com/moonbit"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 3)
  assert_true(@dock.active_browser(model.dock) == Some(3))
  // A non-web scheme keeps the system handler: no tab appears.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("mailto:someone@example.com"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 3)
  // So does a link clicked on another screen, where the dock is not on
  // screen to show a tab — Settings' device-page link wants the browser the
  // user is signed in to anyway.
  let (_, settings) = update(
    dispatch,
    ExternalLinkClicked("https://openseek.test/d/abc"),
    { ..model, screen: Settings },
  )
  assert_eq(settings.dock.tabs.length(), 3)
  assert_eq(settings.preview.pages.length(), 3)
}

///|
test "same-URL reuse scans this strip, not the global page map" {
  let dispatch = test_dispatch()
  let url = "http://127.0.0.1:5173/"
  // Another conversation's parked strip already holds this URL: its page
  // sits in the global map with no tab in this strip. It must not shadow
  // this strip's own tab.
  let (foreign, _) = @preview.open_page(@preview.State::empty(), url~)
  let model = { ..desktop_model(), preview: foreign }
  let (_, model) = update(dispatch, ExternalLinkClicked(url), model)
  assert_eq(model.dock.tabs.length(), 1)
  assert_eq(model.preview.pages.length(), 2)
  // A repeat click re-activates this strip's tab instead of stacking a
  // duplicate per click.
  let (_, model) = update(dispatch, ExternalLinkClicked(url), model)
  assert_eq(model.dock.tabs.length(), 1)
  assert_eq(model.preview.pages.length(), 2)
}

///|
test "a remote console routes loopback links to the system browser too" {
  let dispatch = test_dispatch()
  // test_model is desktop-shaped except for the flag; without native views
  // the dock must not grow browser tabs.
  let model = test_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_true(model.dock.tabs.is_empty())
  assert_true(model.preview.pages.is_empty())
}

///|
test "submitting the address bar normalizes the draft and commits it" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, Dock(TogglePanel), model)
  let (_, model) = update(dispatch, BrowserTabRequested, model)
  let (_, model) = update(
    dispatch,
    BrowserAddressEdited("localhost:5173"),
    model,
  )
  let (_, model) = update(dispatch, BrowserNavigateSubmitted, model)
  let page = @preview.page(model.preview, 1).unwrap()
  assert_true(page.url == Some("http://localhost:5173"))
  assert_eq(page.input, "http://localhost:5173")
  assert_true(page.loading)
  // A non-navigable draft changes nothing — including a bare scheme, which
  // the host would reject after the URL had already been committed.
  let (_, edited) = update(dispatch, BrowserAddressEdited("two words"), model)
  let (_, unchanged) = update(dispatch, BrowserNavigateSubmitted, edited)
  assert_true(
    @preview.page(unchanged.preview, 1).unwrap().url ==
    Some("http://localhost:5173"),
  )
  let (_, edited) = update(dispatch, BrowserAddressEdited("http://"), unchanged)
  let (_, still) = update(dispatch, BrowserNavigateSubmitted, edited)
  assert_true(
    @preview.page(still.preview, 1).unwrap().url ==
    Some("http://localhost:5173"),
  )
}

///|
test "navigating an already-placed tab re-places its view" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The host may have rebuilt the view under `browser.navigate` (nothing
  // acknowledges the ops that placed the old one), and a rebuilt view is
  // hidden at a placeholder size. Keeping the placement would leave the tab
  // blank until an unrelated resize, so the submission drops it…
  let (_, edited) = update(
    dispatch,
    BrowserAddressEdited("https://github.com/moonbit"),
    model,
  )
  let (_, navigated) = update(dispatch, BrowserNavigateSubmitted, edited)
  assert_true(navigated.browser_pane.shown is None)
  assert_true(navigated.browser_pane.rect is None)
  // …and the re-measure it provokes places the view again.
  let (_, replaced) = update(dispatch, BrowserPaneMeasured(rect~), navigated)
  assert_true(replaced.browser_pane.shown == Some(1))
  assert_true(replaced.browser_pane.rect == Some(rect))
}

///|
test "pane measurements place the active view and idempotently settle" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  assert_true(model.browser_pane.rect == Some(rect))
  let (_, again) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(again == model)
  // A zero-size measurement (the observer firing against a hidden pane)
  // never places the view.
  let zero : @preview.Rect = { x: 0, y: 0, width: 0, height: 0 }
  let (_, still) = update(dispatch, BrowserPaneMeasured(rect=zero), model)
  assert_true(still.browser_pane.rect == Some(rect))
}

///|
test "the launcher popup and tab close both retire the shown view" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The popup overlaps the pane, so the native view must hide under it.
  let (_, covered) = update(dispatch, Dock(MenuToggled), model)
  assert_true(covered.browser_pane.shown is None)
  // Closing the tab drops the page and the placement.
  let (_, closed) = update(
    dispatch,
    Dock(TabClosed(@dock.DockTab::Browser(id=1))),
    model,
  )
  assert_true(closed.browser_pane.shown is None)
  assert_true(@preview.page(closed.preview, 1) is None)
  assert_true(closed.dock.tabs.is_empty())
}

///|
test "full-screen modals hide the native view and closing restores it" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The workspace picker's modal covers the pane; native views z-order
  // above HTML, so the view must hide first.
  let (_, covered) = update(dispatch, PickWorkspace(Local), model)
  assert_true(covered.workspace_picker is Some(_))
  assert_true(covered.browser_pane.shown is None)
  // Closing the modal re-measures; the next measurement re-places the view.
  let (_, closed) = update(dispatch, WorkspacePickerClose, covered)
  let (_, restored) = update(dispatch, BrowserPaneMeasured(rect~), closed)
  assert_true(restored.browser_pane.shown == Some(1))
  // The topbar app launcher covers the pane too, and so does the composer's
  // git popover: it opens upward over the pane's bottom-left corner, and a
  // native view left showing would paint straight over it.
  let (_, launched) = update(dispatch, ToggleLauncher, restored)
  assert_true(launched.browser_pane.shown is None)
  // The popover needs a branch to have a trigger at all, so give the
  // conversation one before opening it.
  let (_, on_branch) = update_dev(dispatch, branch_reply("feature/x"), restored)
  let (_, detailing) = update(dispatch, ToggleGitDetails, on_branch)
  assert_true(detailing.browser_pane.shown is None)
  // So do the other two surfaces `view.mbt` appends beside the picker: the
  // archive-discard confirmation and Quick Open.
  let (_, archiving) = update_dev(
    dispatch,
    ArchiveNeedsForce(session="desktop-test", refusal={
      worktree: "wt-1",
      dirty_paths: ["desktop/lepus"],
      dirty_path_count: 1,
    }),
    restored,
  )
  assert_true(archiving.archive_confirm is Some(_))
  assert_true(archiving.browser_pane.shown is None)
  let (_, searching) = update(
    dispatch,
    QuickOpenOpen(QuickOpenSymbols),
    restored,
  )
  assert_true(searching.quick_open is Some(_))
  assert_true(searching.browser_pane.shown is None)
}
