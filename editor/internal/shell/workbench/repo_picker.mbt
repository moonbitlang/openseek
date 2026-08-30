// The repository picker: a modal directory browser over the server host's
// filesystem. Clicking a row navigates into that directory; "Open This
// Folder" re-roots the served workspace at the listed directory. The switch
// itself is confirmed by the server — the requesting session resumes through
// its correlated response, every other session reacts to the broadcast push.

///|
priv struct RepoPickerModel {
  /// The request generation this picker is waiting on; results stamped with
  /// an older generation are superseded and dropped.
  generation : Int
  /// Absolute host path currently listed; empty until the first listing
  /// (the server starts from the current workspace root).
  path : String
  parent : String?
  entries : Array[@remote_protocol.HostDirectoryEntry]
  loading : Bool
  error : String
} derive(Eq)

///|
/// Monotonic stamp for picker requests, module-level like the protocol
/// request counter: reopening the picker also advances it, so a listing from
/// a previous picker instance can never land in the current one.
let repo_picker_generation : Ref[Int] = Ref(0)

///|
fn next_repo_picker_generation() -> Int {
  repo_picker_generation.val += 1
  repo_picker_generation.val
}

///|
fn open_repo_picker_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
) -> (@rabbita.Cmd, WorkbenchModel) {
  let generation = next_repo_picker_generation()
  (
    list_host_directory_cmd(emit, generation, ""),
    {
      ..model,
      repo_picker: Some({
        generation,
        path: "",
        parent: None,
        entries: [],
        loading: true,
        error: "",
      }),
    },
  )
}

///|
fn browse_repo_directory_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  path : String,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) => {
      let generation = next_repo_picker_generation()
      (
        list_host_directory_cmd(emit, generation, path),
        {
          ..model,
          repo_picker: Some({ ..picker, generation, loading: true, error: "", }),
        },
      )
    }
    None => (@rabbita.none, model)
  }
}

///|
/// A listing is applied only when it answers the picker's current request
/// generation; results from a cancelled picker or a superseded navigation
/// are dropped, so a stale listing can never clear `loading` while a newer
/// request is still pending.
fn repo_directory_listed_update(
  model : WorkbenchModel,
  generation : Int,
  result : Result[@remote_protocol.HostDirectoryListing, String],
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) if picker.generation == generation => {
      let picker = match result {
        Ok(listing) =>
          {
            generation,
            path: listing.path,
            parent: listing.parent,
            entries: listing.entries,
            loading: false,
            error: "",
          }
        Err(message) => { ..picker, loading: false, error: message, }
      }
      (@rabbita.none, { ..model, repo_picker: Some(picker), })
    }
    _ => (@rabbita.none, model)
  }
}

///|
fn confirm_repo_picker_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) =>
      if picker.loading || picker.path == "" {
        (@rabbita.none, model)
      } else {
        let generation = next_repo_picker_generation()
        (
          switch_workspace_cmd(emit, generation, picker.path),
          {
            ..model,
            repo_picker: Some({
              ..picker,
              generation,
              loading: true,
              error: "",
            }),
          },
        )
      }
    None => (@rabbita.none, model)
  }
}

///|
fn repo_switch_failed_update(
  model : WorkbenchModel,
  generation : Int,
  message : String,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) if picker.generation == generation =>
      (
        @rabbita.none,
        {
          ..model,
          repo_picker: Some({ ..picker, loading: false, error: message, }),
        },
      )
    _ => (@rabbita.none, model)
  }
}

///|
/// The server announced its served workspace root: the connection-attach
/// greeting, or a broadcast from another session's switch. Matching roots are
/// a no-op; a first announce only records the root (the `Opened` flow already
/// populated the workbench); a differing root on a client that already had
/// one — reconnect across a switch, another tab switching — runs the full
/// switch cleanup.
fn workspace_announce_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  root : String,
) -> (@rabbita.Cmd, WorkbenchModel) {
  if root == model.workspace_root {
    (@rabbita.none, model)
  } else if model.workspace_root == "" {
    (@rabbita.none, { ..model, workspace_root: root, })
  } else {
    workspace_root_switched_update(emit, model, root)
  }
}

///|
/// The served workspace root changed (confirmed switch from this session or a
/// broadcast from another): drop everything scoped to the old root — active
/// document and its watch, viewer model, moon markers — then re-resolve the
/// explorer and auto-open the new workspace's first file.
fn workspace_root_switched_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  root : String,
) -> (@rabbita.Cmd, WorkbenchModel) {
  (
    @rabbita.batch([
      @cmd.custom_cmd(_ => close_active_document_source()),
      viewer_cmd(() => {
        workbench_services().remote_language.invalidate()
        workbench_services().markers.change_all("moon", [])
        clear_workbench_model()
      }),
      workspace_file_tree().refresh(),
      auto_open_first_file_cmd(emit),
    ]),
    {
      ..model,
      repo_picker: None,
      workspace_root: root,
      status: "loading",
      status_message: "",
      document: None,
      line_count: 0,
      diagnostics: [],
      viewer_has_frame: false,
    },
  )
}

///|
fn list_host_directory_cmd(
  emit : @rabbita.Emit[WorkbenchMsg],
  generation : Int,
  path : String,
) -> @rabbita.Cmd {
  @cmd.perform(result => emit(RepoDirectoryListed(generation, result)), async fn() noraise {
    let response = protocol_request("list-dir", id => {
      ListHostDirectory({ id, path, })
    })
    match response {
      HostDirectoryListed(payload) => Ok(payload.listing)
      RemoteError(error) => Err(error.message)
      _ => Err("Unexpected protocol response for host directory listing.")
    }
  })
}

///|
fn switch_workspace_cmd(
  emit : @rabbita.Emit[WorkbenchMsg],
  generation : Int,
  path : String,
) -> @rabbita.Cmd {
  @cmd.perform(
    result => {
      match result {
        Ok(root) => emit(WorkspaceRootSwitched(root))
        Err(message) => emit(RepoSwitchFailed(generation, message))
      }
    },
    async fn() noraise {
      let response = protocol_request("switch", id => {
        SwitchWorkspace({ id, path, })
      })
      match response {
        WorkspaceSwitched(payload) => Ok(payload.root)
        RemoteError(error) => Err(error.message)
        _ => Err("Unexpected protocol response for workspace switch.")
      }
    },
  )
}

///|
fn view_repo_picker(
  emit : @rabbita.Emit[WorkbenchMsg],
  picker : RepoPickerModel,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  match picker.parent {
    Some(parent) =>
      rows.push(
        @html.button(
          type_="button",
          class="repo-picker-entry repo-picker-parent",
          on_click=emit(BrowseRepoDirectory(parent)),
          attrs=@html.Attrs::build().data_set("repo-path", parent),
          [
            @html.span(class="repo-picker-entry-icon", icon_folder()),
            @html.span(class="repo-picker-entry-label", ".."),
          ],
        ),
      )
    None => ()
  }
  for entry in picker.entries {
    let children : Array[@html.Html] = [
      @html.span(class="repo-picker-entry-icon", icon_folder()),
      @html.span(class="repo-picker-entry-label", entry.name),
    ]
    if entry.is_workspace {
      children.push(@html.span(class="repo-picker-badge", "repo"))
    }
    rows.push(
      @html.button(
        type_="button",
        class="repo-picker-entry",
        on_click=emit(BrowseRepoDirectory(entry.path)),
        attrs=@html.Attrs::build().data_set("repo-path", entry.path),
        children,
      ),
    )
  }
  if !picker.loading && picker.entries.is_empty() {
    rows.push(@html.div(class="repo-picker-empty", "No subdirectories"))
  }
  let body : Array[@html.Html] = [
    @html.div(class="repo-picker-header", [
      @html.span(class="repo-picker-title", "Open Repository"),
      @html.button(
        type_="button",
        class="sidebar-action",
        title="Close",
        on_click=emit(CloseRepoPicker),
        attrs=@html.Attrs::build()
          .data_set("action", "close-repo-picker")
          .aria_label("Close repository picker"),
        "\u{2715}",
      ),
    ]),
    @html.div(
      class="repo-picker-path",
      if picker.path == "" {
        "Loading..."
      } else {
        picker.path
      },
    ),
  ]
  if picker.error != "" {
    body.push(@html.div(class="repo-picker-error", picker.error))
  }
  body.push(
    @html.div(
      class=if picker.loading {
        "repo-picker-list is-loading"
      } else {
        "repo-picker-list"
      },
      rows,
    ),
  )
  body.push(
    @html.div(class="repo-picker-footer", [
      @html.button(
        type_="button",
        class="repo-picker-button",
        on_click=emit(CloseRepoPicker),
        attrs=@html.Attrs::build().data_set("action", "cancel-repo-picker"),
        "Cancel",
      ),
      @html.button(
        type_="button",
        class="repo-picker-button repo-picker-button-primary",
        on_click=emit(ConfirmRepoPicker),
        attrs=@html.Attrs::build().data_set("action", "confirm-repo-picker"),
        "Open This Folder",
      ),
    ]),
  )
  @html.div(class="repo-picker-overlay", [
    @html.div(
      class="repo-picker",
      attrs=@html.Attrs::build().aria_label("Open repository"),
      body,
    ),
  ])
}
