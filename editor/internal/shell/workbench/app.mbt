///|
/// The shipped app shell, the `vs/workbench` role: it owns the websocket
/// protocol client, composes the viewer library with the explorer widget,
/// and renders the chrome around them (topbar, sidebar, diagnostics
/// panel, status messages, theme).
priv struct WorkbenchDocumentView {
  uri : String
  display_name : String
  language_id : String
  revision : String
} derive(Eq)

///|
priv struct WorkbenchModel {
  status : String
  status_message : String
  theme : String
  /// Whether the shell allocates a grid column to the workspace explorer.
  explorer_visible : Bool
  document : WorkbenchDocumentView?
  line_count : Int
  diagnostics : Array[@language.Diagnostic]
  /// Mirrors whether the viewer holds a rendered frame; while it does not,
  /// the shell renders its own status placeholder instead of the viewer.
  viewer_has_frame : Bool
  /// The modal repository picker; `None` while closed.
  repo_picker : RepoPickerModel?
  /// The served workspace root as last announced by the server; empty until
  /// the first connection announce. A differing announce (reconnect across a
  /// switch, another session switching) triggers the full switch cleanup.
  workspace_root : String
} derive(Eq)

///|
/// The shell's scroll policy for an incoming document read: a reload of the
/// open document keeps the viewport (`save_view_state`/`restore_view_state`
/// around `set_model`, the Monaco host pattern), a newly opened document
/// starts at the top.
priv enum DocumentViewState {
  PreserveScroll
  ResetScroll
  RevealDefinition(@language.Location)
}

///|
priv enum WorkbenchMsg {
  ConnectProtocol
  ProtocolEvent(@websocket.Event)
  ProtocolSendFailed(String)
  SelectWorkspace(@base_common.Uri)
  OpenDefinitionLocation(@language.Location)
  AutoOpenResolved(@base_common.Uri?)
  ActiveDocumentRead(@workspace.DocumentReadResult, DocumentViewState)
  ActiveDocumentChanged(@workspace.DocumentChange)
  ViewerEvent(WorkbenchViewerEvent)
  ToggleExplorer
  ToggleTheme
  WindowResized
  OpenRepoPicker
  CloseRepoPicker
  BrowseRepoDirectory(String)
  /// Carries the picker request generation that produced the listing so
  /// superseded responses are dropped instead of applied.
  RepoDirectoryListed(
    Int,
    Result[@remote_protocol.HostDirectoryListing, String]
  )
  ConfirmRepoPicker
  RepoSwitchFailed(Int, String)
  WorkspaceRootSwitched(String)
}

///|
priv enum WorkbenchViewerEvent {
  DidChangeMarkers(Array[@base_common.Uri])
  DidBuildViewModel(@viewer_testing.ViewModelBuiltObservation)
  DidRenderModel(@viewer_testing.ModelRenderedObservation)
  DidRenderMarkdown(@model.TextModel)
  DidResolveHover(@viewer_testing.HoverResolvedObservation)
  DidScroll(@editor_api.ScrollEvent)
  DidDispose
}

///|
priv suberror StartupSubscription

///|
fn startup_sub(cmd : @cmd.Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "workbench-startup",
    Local,
    StartupSubscription,
    SubLoader((_, scheduler) => {
      scheduler.add(cmd)
      Some({ unload: _ => (), update_tagger: _ => (), })
    }),
  )
}

///|
let workbench_dispatch : Ref[((WorkbenchMsg) -> Unit)?] = Ref(None)

///|
fn dispatch_workbench_msg(msg : WorkbenchMsg) -> Unit {
  match workbench_dispatch.val {
    Some(dispatch) => dispatch(msg)
    None => ()
  }
}

///|
/// The embedded viewer instance, created on first use with the remote
/// document provider and event subscriptions into the shell update loop.
let viewer_cell : Ref[@viewer.Viewer?] = Ref(None)

///|
/// Rich Markdown is a sibling surface selected by this host. It is never a
/// presentation branch inside the code editor.
let markdown_viewer_cell : Ref[@viewer.MarkdownViewer?] = Ref(None)

///|
/// Workbench-only layout hooks live for the mounted page. Keeping the
/// lifetimes here makes reinstallation idempotent for browser harnesses that
/// mount the shell more than once in one document.
let viewer_host_resize_observer : Ref[@base_common.Disposable?] = Ref(None)

///|
let explorer_resize_dispose : Ref[(() -> Unit)?] = Ref(None)

///|
priv struct WorkbenchServices {
  viewer : @viewer.ViewerServices
  languages : @languages.Languages
  markers : @markers.MarkerService
  remote_language : RemoteLanguageFreshness
  agent_feedback : @agent_feedback.AgentFeedbackService
  agent_feedback_handle : @agent_feedback_api.AgentFeedbackHandle
  log_service : @log.LogService
}

///|
let viewer_services_cell : Ref[WorkbenchServices?] = Ref(None)

///|
let workbench_model_version : Ref[Int] = Ref(0)

///|
fn workbench_services() -> WorkbenchServices {
  match viewer_services_cell.val {
    Some(services) => services
    None => {
      let log_service = workbench_log_service()
      let languages = @languages.default_languages()
      let markers = @markers.MarkerService(
        schedule=@base_browser.queue_microtask,
      )
      let remote_language = RemoteLanguageFreshness(markers)
      let agent_feedback = @agent_feedback.AgentFeedbackService()
      let agent_feedback_handle = agent_feedback.agent_feedback_handle()
      let location_opener = workbench_location_opener()
      let text_model_resolver = workbench_text_model_resolver()
      let viewer = @viewer.ViewerServices(
        languages=languages.language_handle(log_service.log_handle()),
        markers=MarkerStore(markers.marker_service_handle()),
        agent_feedback=agent_feedback_handle,
        location_opener~,
        text_model_resolver~,
        log_service=log_service.log_handle(),
      )
      let services : WorkbenchServices = {
        viewer,
        languages,
        markers,
        remote_language,
        agent_feedback,
        agent_feedback_handle,
        log_service,
      }
      viewer_services_cell.val = Some(services)
      services
    }
  }
}

///|
/// Resolves the workbench viewer, creating it into the shell-rendered
/// `.viewer-host` element on first use (`Viewer::create`, the
/// `monaco.editor.create` pattern). First use happens in the after-render
/// attach command, so the host element is always in the DOM by then.
fn workbench_viewer() -> @viewer.Viewer {
  match viewer_cell.val {
    Some(viewer) => viewer
    None => {
      let host = @rdom.document()
        .query_selector(".viewer-host")
        .to_option()
        .unwrap()
      let viewer = @viewer.Viewer::create(
        host,
        services=workbench_services().viewer,
        options=ViewerOptions(
          theme=stored_theme(),
          placeholder=source_message(initial_workbench_model()),
        ),
      )
      install_viewer_event_subscriptions(viewer)
      viewer_cell.val = Some(viewer)
      viewer
    }
  }
}

///|
fn workbench_markdown_viewer() -> @viewer.MarkdownViewer {
  match markdown_viewer_cell.val {
    Some(viewer) => viewer
    None => {
      let host = @rdom.document()
        .query_selector(".viewer-host")
        .to_option()
        .unwrap()
      let viewer = @viewer.MarkdownViewer::create(
        host,
        services=workbench_services().viewer,
        options=MarkdownViewerOptions(theme=stored_theme()),
      )
      markdown_viewer_cell.val = Some(viewer)
      viewer
    }
  }
}

///|
fn workbench_active_model() -> @model.TextModel? {
  match markdown_viewer_cell.val {
    Some(viewer) =>
      match viewer.get_model() {
        Some(model) => Some(model.model)
        None => workbench_viewer().get_model()
      }
    None => workbench_viewer().get_model()
  }
}

///|
fn layout_workbench_presentation() -> Unit {
  workbench_viewer().layout()
  match markdown_viewer_cell.val {
    Some(viewer) => viewer.layout()
    None => ()
  }
}

///|
fn clear_workbench_model() -> Unit {
  workbench_viewer().set_model(None)
  match markdown_viewer_cell.val {
    Some(viewer) => viewer.set_model(None) |> ignore
    None => ()
  }
  show_workbench_presentation("code")
}

///|
extern "js" fn show_workbench_presentation(kind : String) -> Unit =
  #| (kind) => {
  #|   const host = globalThis.document?.querySelector?.('.viewer-host');
  #|   if (!host) return;
  #|   for (const node of host.children) {
  #|     const code = node.classList?.contains('monaco-editor') ?? false;
  #|     const markdown =
  #|       node.classList?.contains('moonbit-viewer-markdown-document') ||
  #|       node.classList?.contains('moonbit-viewer-markdown-empty');
  #|     if (code) node.hidden = kind !== 'code';
  #|     if (markdown) node.hidden = kind !== 'markdown';
  #|   }
  #| }

///|
fn install_viewer_event_subscriptions(viewer : @viewer.Viewer) -> Unit {
  // Diagnostics counts live on the marker service (Monaco's
  // `IMarkerService.onMarkerChanged`), not on the editor.
  workbench_services().markers.on_did_change_markers(uris => {
    dispatch_workbench_msg(ViewerEvent(DidChangeMarkers(uris)))
  })
  |> ignore
  @viewer_testing.on_did_build_view_model(viewer.get_id(), event => {
    dispatch_workbench_msg(ViewerEvent(DidBuildViewModel(event)))
  })
  |> ignore
  @viewer_testing.on_did_render_model(viewer.get_id(), event => {
    dispatch_workbench_msg(ViewerEvent(DidRenderModel(event)))
  })
  |> ignore
  @viewer_testing.on_did_resolve_hover(viewer.get_id(), event => {
    dispatch_workbench_msg(ViewerEvent(DidResolveHover(event)))
  })
  |> ignore
  viewer.on_did_scroll_change(event => {
    dispatch_workbench_msg(ViewerEvent(DidScroll(event)))
  })
  |> ignore
  viewer.on_did_dispose(() => {
    // `Viewer::on_did_dispose` intentionally fires before contribution
    // teardown. Enter terminal resolver shutdown now, but let the nested Peek
    // Viewer release its real model lease before the cache retires that model.
    shutdown_preview_resources()
    workbench_services().remote_language.invalidate()
    dispatch_workbench_msg(ViewerEvent(DidDispose))
  })
  |> ignore
}

///|
/// Browser entrypoint for the reference workbench.
pub fn start_app() -> Unit {
  install_host_capabilities()
  let services = workbench_services()
  register_remote_language_providers(services)
  install_moonbit_markdown_comment_provider(services.languages)
  install_language_tokenizers(services)
  install_feedback_persistence(services)
  mount_app()
}

///|
/// Languages are compile-time packages composed here by import; the
/// viewer library itself renders unregistered languages as plain text.
fn install_language_tokenizers(services : WorkbenchServices) -> Unit {
  services.languages.set_tokens_provider(
    "moonbit",
    @lang_moonbit.MoonBitTokenizer(),
  )
  |> ignore
  services.languages.set_tokens_provider("json", @lang_json.JsonTokenizer())
  |> ignore
  services.languages.set_tokens_provider(
    "moonbit-config",
    @lang_moon_config.MoonConfigTokenizer(),
  )
  |> ignore
  let javascript = @lang_javascript.JavascriptTokenizer()
  services.languages.set_tokens_provider("javascript", javascript) |> ignore
  // TypeScript reads acceptably through the JavaScript rules until a
  // dedicated package exists.
  services.languages.set_tokens_provider("typescript", javascript) |> ignore
}

///|
/// Mounts the Rabbita workbench shell and attaches the viewer view after the
/// first shell paint.
fn mount_app() -> Unit {
  let app = @rabbita.new(() => {
    let tree_view = workspace_file_tree().view()
    let (state, emit) = @rabbita.create_state(
      initial_workbench_model(),
      update=(state, msg, emit) => {
        let (cmd, model) = update_workbench(emit, msg, state)
        (model, cmd)
      },
      subscriptions=(_state, emit) => {
        @sub.batch([
          startup_sub(
            @cmd.custom_cmd(scheduler => {
              workbench_dispatch.val = Some(msg => scheduler.add(emit(msg)))
              protocol_send.val = Some(packet => {
                scheduler.add(send_client_packet_cmd(emit, packet))
              })
              scheduler.add(emit(ConnectProtocol))
              // The viewer view mounts into the stable host element after the
              // shell's first paint; the shell never renders children into it.
              scheduler.add(
                @cmd.custom_cmd(
                  _ => attach_workbench_viewer(),
                  kind=@cmd.after_render,
                ),
              )
            }),
          ),
          @sub.on_resize(emit.map(_ => WindowResized)),
        ])
      },
    )
    state.view2(tree_view, (state, tree_html) => {
      view_workbench(emit, state, tree_html)
    })
  })
  app.mount("app")
}

///|
/// Creates the imperative viewer inside the shell-rendered host element and
/// gives it keyboard focus (the viewer owns its own key handling).
fn attach_workbench_viewer() -> Unit {
  let viewer = workbench_viewer()
  install_workbench_resize_hooks()
  show_workbench_presentation("code")
  viewer.focus()
}

///|
/// Keeps the Viewer layout synchronized with every host-box change, including
/// Explorer splitter gestures that do not emit a window resize event.
fn install_workbench_resize_hooks() -> Unit {
  match viewer_host_resize_observer.val {
    Some(observer) => observer.dispose()
    None => ()
  }
  match explorer_resize_dispose.val {
    Some(dispose) => dispose()
    None => ()
  }
  guard @rdom.document().query_selector(".viewer-host").to_option()
    is Some(host) else {
    return
  }
  viewer_host_resize_observer.val = @base_browser.observe_element_resize(host, () => {
    layout_workbench_presentation()
  })
  explorer_resize_dispose.val = Some(install_explorer_resize_handle())
}

///|
/// Installs the pointer and keyboard branches of the accessible Explorer
/// splitter. Width is stored on the grid rather than the sidebar element, so
/// the mobile grid can override it without fighting a native inline width.
extern "js" fn install_explorer_resize_handle() -> () -> Unit =
  #| () => {
  #|   const main = globalThis.document?.querySelector?.('.editor-main');
  #|   const sidebar = globalThis.document?.querySelector?.('#workspace-explorer');
  #|   const handle = globalThis.document?.querySelector?.('[data-action="resize-explorer"]');
  #|   if (!main || !sidebar || !handle) return () => {};
  #|   const ownerWindow = handle.ownerDocument?.defaultView ?? globalThis;
  #|   const minWidth = 200;
  #|   const maximumWidth = () => Math.max(
  #|     minWidth,
  #|     Math.min(420, Math.floor((ownerWindow.innerWidth || 840) * 0.5)),
  #|   );
  #|   const isMobile = () => ownerWindow.matchMedia?.('(max-width: 680px)').matches ?? false;
  #|   let width = Math.round(Number.parseFloat(
  #|     ownerWindow.getComputedStyle?.(main).getPropertyValue('--explorer-width'),
  #|   )) || 280;
  #|   let activePointerId = null;
  #|   let startX = 0;
  #|   let startWidth = width;
  #|   let savedCursor = '';
  #|   let savedUserSelect = '';
  #|   const applyWidth = (next) => {
  #|     width = Math.max(minWidth, Math.min(maximumWidth(), Math.round(next)));
  #|     main.style.setProperty('--explorer-width', `${width}px`);
  #|     handle.setAttribute('aria-valuenow', String(width));
  #|     handle.setAttribute('aria-valuemax', String(maximumWidth()));
  #|   };
  #|   const finishDrag = (event) => {
  #|     if (activePointerId === null) return;
  #|     if (event?.pointerId !== undefined && event.pointerId !== activePointerId) return;
  #|     try { handle.releasePointerCapture?.(activePointerId); } catch (_error) {}
  #|     activePointerId = null;
  #|     ownerWindow.removeEventListener('pointermove', moveDrag);
  #|     ownerWindow.removeEventListener('pointerup', finishDrag);
  #|     ownerWindow.removeEventListener('pointercancel', finishDrag);
  #|     handle.ownerDocument.body.style.cursor = savedCursor;
  #|     handle.ownerDocument.body.style.userSelect = savedUserSelect;
  #|   };
  #|   const moveDrag = (event) => {
  #|     if (event.pointerId !== activePointerId) return;
  #|     applyWidth(startWidth + event.clientX - startX);
  #|   };
  #|   const startDrag = (event) => {
  #|     if (event.button !== 0 || isMobile()) return;
  #|     event.preventDefault();
  #|     activePointerId = event.pointerId;
  #|     startX = event.clientX;
  #|     startWidth = width;
  #|     savedCursor = handle.ownerDocument.body.style.cursor;
  #|     savedUserSelect = handle.ownerDocument.body.style.userSelect;
  #|     handle.ownerDocument.body.style.cursor = 'ew-resize';
  #|     handle.ownerDocument.body.style.userSelect = 'none';
  #|     try { handle.setPointerCapture?.(event.pointerId); } catch (_error) {}
  #|     ownerWindow.addEventListener('pointermove', moveDrag);
  #|     ownerWindow.addEventListener('pointerup', finishDrag);
  #|     ownerWindow.addEventListener('pointercancel', finishDrag);
  #|   };
  #|   const onKeyDown = (event) => {
  #|     let next = width;
  #|     if (event.key === 'ArrowLeft') next -= 10;
  #|     else if (event.key === 'ArrowRight') next += 10;
  #|     else if (event.key === 'Home') next = minWidth;
  #|     else if (event.key === 'End') next = maximumWidth();
  #|     else return;
  #|     event.preventDefault();
  #|     applyWidth(next);
  #|   };
  #|   const onWindowResize = () => {
  #|     if (isMobile()) {
  #|       handle.setAttribute('aria-valuemax', String(Math.max(width, maximumWidth())));
  #|     } else {
  #|       applyWidth(width);
  #|     }
  #|   };
  #|   if (isMobile()) {
  #|     main.style.setProperty('--explorer-width', `${width}px`);
  #|     handle.setAttribute('aria-valuenow', String(width));
  #|     handle.setAttribute('aria-valuemax', String(Math.max(width, maximumWidth())));
  #|   } else {
  #|     applyWidth(width);
  #|   }
  #|   handle.addEventListener('pointerdown', startDrag);
  #|   handle.addEventListener('keydown', onKeyDown);
  #|   ownerWindow.addEventListener('resize', onWindowResize);
  #|   return () => {
  #|     finishDrag();
  #|     handle.removeEventListener('pointerdown', startDrag);
  #|     handle.removeEventListener('keydown', onKeyDown);
  #|     ownerWindow.removeEventListener('resize', onWindowResize);
  #|   };
  #| }

///|
/// Lifts a plain viewer call into the shell's command system.
fn viewer_cmd(action : () -> Unit) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => action())
}

///|
fn initial_workbench_model() -> WorkbenchModel {
  {
    status: "loading",
    status_message: "",
    theme: stored_theme(),
    explorer_visible: true,
    document: None,
    line_count: 0,
    diagnostics: [],
    viewer_has_frame: false,
    repo_picker: None,
    workspace_root: "",
  }
}

///|
/// Outer update: the shell owns the empty-viewer message policy, and the
/// viewer displays it; push the wording into the viewer whenever a state
/// transition changes it.
fn update_workbench(
  emit : @rabbita.Emit[WorkbenchMsg],
  msg : WorkbenchMsg,
  model : WorkbenchModel,
) -> (@rabbita.Cmd, WorkbenchModel) {
  let (cmd, next) = workbench_update(emit, msg, model)
  let message = source_message(next)
  if message == source_message(model) {
    (cmd, next)
  } else {
    (
      @rabbita.batch([
        cmd,
        viewer_cmd(() => {
          let viewer = workbench_viewer()
          viewer.update_options(viewer.get_options().with_placeholder(message))
        }),
      ]),
      next,
    )
  }
}

///|
fn workbench_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  msg : WorkbenchMsg,
  model : WorkbenchModel,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match msg {
    ConnectProtocol =>
      (
        connect_protocol_cmd(emit),
        { ..model, status: "loading", status_message: "", },
      )
    ProtocolEvent(event) => protocol_event_update(emit, model, event)
    ProtocolSendFailed(message) => {
      // A failed send is not guaranteed to be followed by a Closed event.
      // Resume every suspended provider/resolver now so F12 and Peek cannot
      // remain in a permanent loading state.
      fail_pending_requests(message)
      (
        dom_mounted_status_cmd("error"),
        { ..model, status: "error", status_message: message, },
      )
    }
    SelectWorkspace(uri) => select_workspace_update(model, uri)
    OpenDefinitionLocation(location) =>
      open_definition_location_update(model, location)
    AutoOpenResolved(found) =>
      match found {
        Some(uri) =>
          if model.document is None {
            select_workspace_update(model, uri)
          } else {
            (@rabbita.none, model)
          }
        // An empty workspace keeps the loading placeholder.
        None => (@rabbita.none, model)
      }
    ActiveDocumentRead(result, view_state) =>
      active_document_read_update(model, result, view_state)
    ActiveDocumentChanged(change) =>
      active_document_change_update(model, change)
    ViewerEvent(event) => viewer_event_update(model, event)
    ToggleExplorer =>
      (
        @cmd.custom_cmd(
          _ => layout_workbench_presentation(),
          kind=@cmd.after_render,
        ),
        { ..model, explorer_visible: !model.explorer_visible, },
      )
    ToggleTheme => {
      let theme = if model.theme == "light" { "dark" } else { "light" }
      (
        @rabbita.batch([
          persist_theme_cmd(theme),
          viewer_cmd(() => {
            let viewer = workbench_viewer()
            viewer.update_options(viewer.get_options().with_theme(theme))
            match markdown_viewer_cell.val {
              Some(markdown) =>
                markdown.update_options(
                  markdown.get_options().with_theme(theme),
                )
              None => ()
            }
          }),
        ]),
        { ..model, theme, },
      )
    }
    WindowResized => (viewer_cmd(layout_workbench_presentation), model)
    OpenRepoPicker => open_repo_picker_update(emit, model)
    CloseRepoPicker => (@rabbita.none, { ..model, repo_picker: None, })
    BrowseRepoDirectory(path) => browse_repo_directory_update(emit, model, path)
    RepoDirectoryListed(generation, result) =>
      repo_directory_listed_update(model, generation, result)
    ConfirmRepoPicker => confirm_repo_picker_update(emit, model)
    RepoSwitchFailed(generation, message) =>
      repo_switch_failed_update(model, generation, message)
    WorkspaceRootSwitched(root) =>
      workspace_root_switched_update(emit, model, root)
  }
}

///|
fn select_workspace_update(
  model : WorkbenchModel,
  uri : @base_common.Uri,
) -> (@rabbita.Cmd, WorkbenchModel) {
  (
    open_active_document_cmd(uri, ResetScroll),
    { ..model, status: "loading", status_message: "", viewer_has_frame: false, },
  )
}

///|
fn open_definition_location_update(
  model : WorkbenchModel,
  location : @language.Location,
) -> (@rabbita.Cmd, WorkbenchModel) {
  (
    open_active_document_cmd(location.uri, RevealDefinition(location)),
    { ..model, status: "loading", status_message: "", viewer_has_frame: false, },
  )
}

///|
fn workbench_markdown_resource_kind(
  text_model : @model.TextModel,
) -> @viewer.MarkdownResourceKind? {
  let path = text_model.uri.path.to_lower()
  if path.has_suffix(".mbt.md") {
    Some(MoonBitMarkdown)
  } else if path.has_suffix(".md") || text_model.get_language_id() == "markdown" {
    Some(OrdinaryMarkdown)
  } else {
    None
  }
}

///|
/// Installs a model into the host-selected code or Markdown surface. Neither
/// reusable widget infers presentation from a URI.
fn set_workbench_model(
  text_model : @model.TextModel,
  view_state : DocumentViewState,
) -> Unit {
  workbench_services().remote_language.note_document(text_model)
  sync_document_feedback(text_model)
  match workbench_markdown_resource_kind(text_model) {
    Some(resource_kind) =>
      set_workbench_markdown_model(text_model, resource_kind, view_state)
    None => set_workbench_code_model(text_model, view_state)
  }
}

///|
fn set_workbench_markdown_model(
  text_model : @model.TextModel,
  resource_kind : @viewer.MarkdownResourceKind,
  view_state : DocumentViewState,
) -> Unit {
  let viewer = workbench_markdown_viewer()
  let state = match view_state {
    PreserveScroll => viewer.save_view_state()
    ResetScroll | RevealDefinition(_) => None
  }
  workbench_viewer().set_model(None)
  viewer.set_model(Some(MarkdownViewerModel(text_model, resource_kind)))
  |> ignore
  show_workbench_presentation("markdown")
  viewer.restore_view_state(state)
  viewer.handle_initialized()
  match view_state {
    RevealDefinition(location) =>
      if location.uri.to_string() == text_model.uri.to_string() {
        viewer.reveal_range_in_center(text_model.validate_range(location.range))
        viewer.focus()
      }
    PreserveScroll | ResetScroll => ()
  }
  dispatch_workbench_msg(ViewerEvent(DidRenderMarkdown(text_model)))
}

///|
fn set_workbench_code_model(
  text_model : @model.TextModel,
  view_state : DocumentViewState,
) -> Unit {
  let viewer = workbench_viewer()
  match markdown_viewer_cell.val {
    Some(markdown) => markdown.set_model(None) |> ignore
    None => ()
  }
  let restored_view_state = match view_state {
    PreserveScroll => {
      let state = viewer.save_view_state()
      viewer.set_model(Some(text_model))
      viewer.restore_view_state(state)
      state is Some(_)
    }
    ResetScroll => {
      viewer.set_model(Some(text_model))
      false
    }
    RevealDefinition(_) => {
      viewer.set_model(Some(text_model))
      false
    }
  }
  show_workbench_presentation("code")
  // The reference workbench presents `.mbt` sources as a top-level outline.
  // Keep this a host policy instead of changing the reusable Viewer's default:
  // other registered languages and external embedders retain expanded models.
  // `set_model` computes folding ranges synchronously, so the collapse is part
  // of the stable initialization state and never needs a timer or render hook.
  if !restored_view_state && should_auto_fold_top_level(text_model) {
    viewer.fold_top_level()
  }
  // Matches TextFileEditor.setInput: model, restored state/options, then the
  // separate ICodeEditor.handleInitialized boundary.
  viewer.handle_initialized()
  match view_state {
    RevealDefinition(location) =>
      if location.uri.to_string() == text_model.uri.to_string() {
        let target_range = text_model.validate_range(location.range)
        let target = target_range.get_start_position()
        viewer.set_position(target, source="gotoDefinition")
        viewer.reveal_position_in_center_if_outside_viewport(target)
        viewer.focus()
        let decorations = viewer.create_decorations_collection(decorations=[
          {
            range: target_range,
            options: ModelDecorationOptions(
              "symbolHighlight",
              description="symbol-navigate-action-highlight",
            ),
          },
        ])
        @base_browser.schedule_timeout(
          () => {
            match viewer.get_model() {
              Some(current) if current.same(text_model) => decorations.clear()
              _ => ()
            }
          },
          350,
        )
        |> ignore
      }
    PreserveScroll | ResetScroll => ()
  }
}

///|
/// Whether the reference workbench applies its initial outline policy.
///
/// Folding itself remains language-neutral; the host opts in only for ordinary
/// MoonBit source files because their top-level declarations are the
/// workbench's primary reading surface. In particular, `.mbt.md` documents and
/// extensionless sources remain expanded. A fresh open applies the policy;
/// watched-file replacements restore their saved view state instead of
/// applying the initial policy again.
fn should_auto_fold_top_level(text_model : @model.TextModel) -> Bool {
  text_model.get_language_id() == "moonbit" &&
  text_model.display_name.has_suffix(".mbt")
}

///|
/// Host-owned document read results are translated into direct viewer model
/// calls or shell-level source errors.
fn active_document_read_update(
  model : WorkbenchModel,
  result : @workspace.DocumentReadResult,
  view_state : DocumentViewState,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match result {
    DocumentLoaded(document) => {
      let text_model = document_to_text_model(document)
      (viewer_cmd(() => set_workbench_model(text_model, view_state)), model)
    }
    DocumentNotFound(uri) =>
      active_document_error_update(
        model,
        DocumentError(FileNotFound, "Document not found.", uri~),
      )
    DocumentReadFailed(error) => active_document_error_update(model, error)
  }
}

///|
fn active_document_change_update(
  model : WorkbenchModel,
  change : @workspace.DocumentChange,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match change {
    DocumentInvalidated(uri~, ..) =>
      (reload_active_document_cmd(uri, PreserveScroll), model)
    DocumentUpdated(document) => {
      let text_model = document_to_text_model(document)
      (viewer_cmd(() => set_workbench_model(text_model, PreserveScroll)), model)
    }
    DocumentDeleted(uri) =>
      active_document_error_update(
        model,
        DocumentError(FileNotFound, "Document was deleted.", uri~),
      )
    DocumentChangeFailed(uri=_uri, error~) =>
      active_document_error_update(model, error)
  }
}

///|
fn active_document_error_update(
  model : WorkbenchModel,
  error : @workspace.DocumentError,
) -> (@rabbita.Cmd, WorkbenchModel) {
  emit_event("language:error", error.to_json().stringify())
  let clear = viewer_cmd(() => {
    workbench_services().remote_language.invalidate()
    clear_workbench_model()
  })
  let (status, status_message) = if error.code == FileNotFound {
    ("missing", "Source file is missing.")
  } else {
    ("error", error.message)
  }
  (
    @rabbita.batch([clear, dom_mounted_status_cmd(status)]),
    { ..model, status, status_message, viewer_has_frame: false, },
  )
}

///|
/// Viewer lifecycle facts drive the shell: status and topbar sync, the
/// explorer's autoReveal, and the harness events the viewer no longer
/// formats itself.
fn viewer_event_update(
  model : WorkbenchModel,
  event : WorkbenchViewerEvent,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match event {
    DidChangeMarkers(uris) => {
      // The marker service reports per-resource changes; the status line only
      // tracks the open document.
      match workbench_active_model() {
        Some(text_model) =>
          if uris.search_by(uri => uri.to_string() == text_model.uri.to_string())
            is Some(_) {
            emit_language_status(
              workbench_services().markers
              .diagnostics_for_resource(text_model.uri)
              .length(),
              text_model.revision,
            )
          }
        None => ()
      }
      (@rabbita.none, model)
    }
    DidBuildViewModel(event) => {
      let diagnostic_count = workbench_services().markers
        .diagnostics_for_resource(event.model.uri)
        .length()
      set_current_model(text_model_harness_json(event.model))
      emit_render_event(
        event.line_count,
        event.token_count,
        diagnostic_count,
        event.model.revision,
        event.tokenize_ms,
        event.build_ms,
      )
      (@rabbita.none, model)
    }
    DidRenderModel(event) => {
      let diagnostics = workbench_services().markers.diagnostics_for_resource(
        event.model.uri,
      )
      emit_dom_mounted(
        event.rendered_lines,
        diagnostics.length(),
        "ready",
        patch_ms=Some(event.patch_ms),
      )
      let next = {
        ..model,
        status: "ready",
        status_message: "",
        document: Some(model_to_view(event.model)),
        line_count: event.line_count,
        diagnostics,
        viewer_has_frame: true,
      }
      if event.fresh {
        // The viewer lifecycle drives the explorer's autoReveal: a freshly
        // loaded document expands its ancestor chain and selects its row.
        (workspace_file_tree().set_active(event.model.uri), next)
      } else {
        (@rabbita.none, next)
      }
    }
    DidRenderMarkdown(text_model) => {
      let diagnostics = workbench_services().markers.diagnostics_for_resource(
        text_model.uri,
      )
      let line_count = text_model.get_line_count()
      set_current_model(text_model_harness_json(text_model))
      emit_render_event(
        line_count,
        0,
        diagnostics.length(),
        text_model.revision,
        0.0,
        0.0,
      )
      emit_dom_mounted(line_count, diagnostics.length(), "ready", patch_ms=None)
      let next = {
        ..model,
        status: "ready",
        status_message: "",
        document: Some(model_to_view(text_model)),
        line_count,
        diagnostics,
        viewer_has_frame: true,
      }
      (workspace_file_tree().set_active(text_model.uri), next)
    }
    DidResolveHover(event) => {
      emit_hover_status(event.ok, event.revision)
      (@rabbita.none, model)
    }
    DidScroll(event) => {
      emit_scroll_event(event.scroll_top, event.scroll_left)
      (@rabbita.none, model)
    }
    DidDispose => (@rabbita.none, { ..model, viewer_has_frame: false, })
  }
}

///|
fn protocol_event_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  event : @websocket.Event,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match event {
    // A fresh socket (first connect or reconnect) re-resolves the explorer
    // tree; the auto-open policy fills the viewer when nothing is open yet.
    Opened => {
      let commands = [workspace_file_tree().refresh()]
      if model.document is None {
        commands.push(auto_open_first_file_cmd(emit))
      }
      (@rabbita.batch(commands), { ..model, status_message: "", })
    }
    Message(raw) => protocol_message_update(emit, model, raw)
    Closed(_) => {
      fail_pending_requests("Connection lost.")
      (
        dom_mounted_status_cmd("stale"),
        {
          ..model,
          status: "stale",
          status_message: "Connection lost. Reconnecting...",
        },
      )
    }
    Errored => {
      fail_pending_requests("Remote protocol connection failed.")
      (
        dom_mounted_status_cmd("error"),
        {
          ..model,
          status: "error",
          status_message: "Remote protocol connection failed.",
        },
      )
    }
  }
}

///|
fn protocol_message_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  raw : String,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match @remote_protocol.decode_server_packet(raw) {
    DecodedServerPacket(packet) =>
      // Correlated responses resume their waiting provider request; only
      // push packets fall through to app-level handling.
      if resolve_pending_response(packet) {
        (@rabbita.none, model)
      } else {
        server_packet_update(emit, model, packet)
      }
    ServerPacketDecodeError(error) => protocol_error_update(model, error)
  }
}

///|
fn server_packet_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  packet : @remote_protocol.ServerPacket,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match packet {
    // Uncorrelated document packets are watch pushes; the document source
    // routes them to the listener registered for their URI.
    DocumentLoaded(payload) => (route_watched_document_cmd(payload), model)
    DocumentChanged(payload) => (route_watched_document_cmd(payload), model)
    // Diagnostics are always a server push (relayed from backend `moon check`
    // runs); they land in the marker service keyed by resource.
    Diagnostics(payload) => (apply_remote_diagnostics_cmd(payload), model)
    // The server's workspace announcement: the connection-attach greeting,
    // or another session switching the root. The handler no-ops when the
    // announced root matches what this client already shows.
    WorkspaceSwitched(payload) =>
      workspace_announce_update(emit, model, payload.root)
    // Feature results without a waiting request are unsolicited; provider
    // commands consume theirs through the pending table.
    DirectoryResolved(_) => (@rabbita.none, model)
    HoverResult(_) => (@rabbita.none, model)
    DefinitionResult(_) => (@rabbita.none, model)
    ReferencesResult(_) => (@rabbita.none, model)
    DocumentSymbolsResult(_) => (@rabbita.none, model)
    HostDirectoryListed(_) => (@rabbita.none, model)
    RemoteError(error) =>
      match watched_uri_for_error(error) {
        Some(uri_key) => (route_watched_error_cmd(uri_key, error), model)
        None => protocol_error_update(model, error)
      }
  }
}

///|
fn protocol_error_update(
  model : WorkbenchModel,
  error : @remote_protocol.ProtocolError,
) -> (@rabbita.Cmd, WorkbenchModel) {
  emit_event("language:error", error.to_json().stringify())
  if error.provider_code == "FileNotFound" {
    (
      dom_mounted_status_cmd("missing"),
      {
        ..model,
        status: "missing",
        status_message: "Source file is missing.",
        viewer_has_frame: false,
      },
    )
  } else {
    (
      dom_mounted_status_cmd("error"),
      { ..model, status: "error", status_message: error.message, },
    )
  }
}

///|
fn document_to_text_model(
  document : @workspace.DocumentSnapshot,
) -> @model.TextModel {
  workbench_model_version.val += 1
  TextModel(
    document.uri,
    document.display_name,
    document.language_id,
    workbench_model_version.val,
    document.revision,
    document.text,
  )
}

///|
fn model_to_view(model : @model.TextModel) -> WorkbenchDocumentView {
  {
    uri: model.uri.to_string(),
    display_name: model.display_name,
    language_id: model.language_id,
    revision: model.revision,
  }
}

///|
fn text_model_harness_json(model : @model.TextModel) -> String {
  let mut payload = "{"
  payload = "\{payload}\"uri\":\{json_string(model.uri.to_string())}"
  payload = "\{payload},\"displayName\":\{json_string(model.display_name)}"
  payload = "\{payload},\"languageId\":\{json_string(model.language_id)}"
  payload = "\{payload},\"version\":\{model.version.to_string()}"
  payload = "\{payload},\"revision\":\{json_string(model.revision)}"
  payload = "\{payload},\"text\":\{json_string(model.snapshot.get_value())}"
  payload = "\{payload}}"
  payload
}

///|
fn view_workbench(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  tree_html : @html.Html,
) -> @html.Html {
  let children : Array[@html.Html] = [
    view_topbar(emit, model),
    @html.div(class=editor_main_class(model), [
      view_sidebar(emit, model, tree_html),
      view_explorer_resize_handle(),
      // The stable viewer host: the viewer attaches its imperative DOM
      // into this element after mount, and the shell must never render
      // vdom children into it (Rabbita's diff would not know them).
      @html.div(class="viewer-host", ([] : Array[@html.Html])),
    ]),
    view_diagnostics(model),
  ]
  match model.repo_picker {
    Some(picker) => children.push(view_repo_picker(emit, picker))
    None => ()
  }
  @html.main_(class="editor-shell", attrs=shell_attrs(model), children)
}

///|
fn shell_attrs(model : WorkbenchModel) -> @html.Attrs {
  let mut attrs = @html.Attrs::build()
  attrs = attrs.data_set("status", model.status)
  attrs = attrs.data_set("theme", model.theme)
  attrs = attrs.data_set("explorer-visible", model.explorer_visible.to_string())
  attrs = attrs.data_set("line-count", line_count_string(model))
  match model.document {
    Some(document) => attrs = attrs.data_set("source-uri", document.uri)
    None => ()
  }
  attrs
}

///|
fn editor_main_class(model : WorkbenchModel) -> String {
  if model.explorer_visible {
    "editor-main"
  } else {
    "editor-main is-explorer-hidden"
  }
}

///|
fn view_topbar(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
) -> @html.Html {
  let explorer_action = if model.explorer_visible {
    "Hide Explorer"
  } else {
    "Show Explorer"
  }
  @html.div(class="topbar", [
    @html.div(class="topbar-leading", [
      @html.button(
        type_="button",
        class="topbar-action",
        title=explorer_action,
        on_click=emit(ToggleExplorer),
        attrs=@html.Attrs::build()
          .data_set("action", "toggle-explorer")
          .aria_label(explorer_action)
          .aria_controls("workspace-explorer")
          .aria_expanded(model.explorer_visible.to_string()),
        icon_sidebar(),
      ),
      @html.div(class="source-title", [
        @html.strong(document_title(model)),
        @html.span(document_meta(model)),
      ]),
    ]),
    @html.div(
      class="source-status source-status-\{model.status}",
      status_text(model),
    ),
  ])
}

///|
/// Sidebar chrome (Explorer title, theme toggle) stays in the shell; the
/// tree itself is the embedded explorer widget value.
fn view_sidebar(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  tree_html : @html.Html,
) -> @html.Html {
  @html.aside(
    id="workspace-explorer",
    class="workspace-sidebar",
    hidden=!model.explorer_visible,
    attrs=@html.Attrs::build().aria_label("Workspace files"),
    [
      @html.div(class="workspace-title", [
        @html.span(class="workspace-title-label", "Explorer"),
        @html.span(class="workspace-title-actions", [
          @html.button(
            type_="button",
            class="sidebar-action",
            title="Open Repository...",
            on_click=emit(OpenRepoPicker),
            attrs=@html.Attrs::build()
              .data_set("action", "open-repository")
              .aria_label("Open repository"),
            icon_folder(),
          ),
          @html.button(
            type_="button",
            class="sidebar-action",
            title="Toggle Color Theme",
            on_click=emit(ToggleTheme),
            attrs=@html.Attrs::build()
              .data_set("action", "toggle-theme")
              .aria_label("Toggle color theme"),
            icon_color_mode(),
          ),
        ]),
      ]),
      tree_html,
    ],
  )
}

///|
fn view_explorer_resize_handle() -> @html.Html {
  @html.div(
    class="workspace-resize-handle",
    attrs=@html.Attrs::build()
      .data_set("action", "resize-explorer")
      .role("separator")
      .tabindex(0)
      .title("Resize Explorer")
      .aria_label("Resize Explorer")
      .aria_controls("workspace-explorer")
      .aria_orientation("vertical")
      .aria_valuemin("200")
      .aria_valuemax("420")
      .aria_valuenow("280"),
    ([] : Array[@html.Html]),
  )
}

///|
fn view_diagnostics(model : WorkbenchModel) -> @html.Html {
  let children : Array[@html.Html] = [@html.strong("Diagnostics")]
  if model.viewer_has_frame {
    for diagnostic in model.diagnostics {
      children.push(
        @html.div(
          class="diagnostic-item",
          "\{diagnostic.severity.label()}: \{diagnostic.message}",
        ),
      )
    }
  }
  @html.aside(
    class="diagnostics",
    attrs=@html.Attrs::build().aria_label("Diagnostics"),
    children,
  )
}

///|
fn line_count_string(model : WorkbenchModel) -> String {
  if model.viewer_has_frame {
    model.line_count.to_string()
  } else {
    "0"
  }
}

///|
fn document_title(model : WorkbenchModel) -> String {
  match model.document {
    Some(document) =>
      if document.display_name == "" {
        display_name_from_uri(document.uri)
      } else {
        document.display_name
      }
    None => "Readonly MoonBit Editor"
  }
}

///|
fn document_meta(model : WorkbenchModel) -> String {
  match model.document {
    Some(document) => {
      let language = if document.language_id == "" {
        "moonbit"
      } else {
        document.language_id
      }
      "\{language} \{document.revision}"
    }
    None => "moonbit"
  }
}

///|
fn status_text(model : WorkbenchModel) -> String {
  let count = if model.viewer_has_frame {
    "\{model.line_count.to_string()} lines"
  } else {
    ""
  }
  let label = status_label(model.status)
  if count == "" {
    label
  } else {
    "\{label} - \{count}"
  }
}

///|
fn status_label(status : String) -> String {
  match status {
    "ready" => "Ready"
    "loading" => "Loading"
    "missing" => "Missing"
    "stale" => "Reconnecting"
    _ => "Error"
  }
}

///|
fn source_message(model : WorkbenchModel) -> String {
  match model.status {
    "loading" => "Loading source..."
    "missing" => "Source file is missing."
    "stale" => "Connection lost. Reconnecting..."
    "error" =>
      if model.status_message == "" {
        "Unable to load source."
      } else {
        model.status_message
      }
    _ => ""
  }
}

///|
fn display_name_from_uri(uri : String) -> String {
  let path = match uri.find("://") {
    Some(index) => uri[index + 3:].to_owned()
    None => uri
  }
  let segments = path.split("/")
  for segment_view in segments; found = uri {
    let segment = segment_view.to_owned()
    continue if segment == "" { found } else { segment }
  } nobreak {
    found
  }
}

///|
let theme_storage_key = "readonly-editor:theme"

///|
fn stored_theme() -> String {
  match storage_get_item(theme_storage_key) {
    "light" => "light"
    _ => "dark"
  }
}

///|
fn persist_theme_cmd(theme : String) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => storage_set_item(theme_storage_key, theme))
}
