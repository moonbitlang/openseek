// A compact, host-backed folder chooser. The location bar behaves like a
// system picker, while the inline composer can create and enter a folder
// without leaving the add-project flow. Keyboard capture lives in `keys.mbt`;
// focused controls keep their own Enter and Escape behavior here.

///|
pub fn view(emit : @cmd.Emit[Msg], picker : State) -> @html.Html {
  let rows : Array[@html.Html] = []
  if picker.new_folder is Some(name) {
    rows.push(new_folder_row(emit, picker, name))
  }
  for name in picker.entries {
    let target = match picker.location {
      Some(Directory(path)) => path.picker_child_path(name)
      // A drive row ("C:") enters that drive's root; the trailing slash is
      // the drive root's canonical resource spelling ("/C:/").
      Some(DriveList) => "/" + name + "/"
      None => name
    }
    rows.push(
      @html.button(
        class="picker-row",
        type_="button",
        disabled=picker.loading,
        on_click=emit(Navigate(target)),
        attrs=@html.Attrs::build().aria_label("Open folder \{name}"),
        [
          @html.span(class="picker-row-icon", @icons.icon(@icons.icon_folder)),
          @html.span(class="picker-row-name", name),
          @html.span(
            class="picker-row-chevron",
            attrs=@html.Attrs::build().aria_hidden("true"),
            @icons.icon(@icons.icon_chevron_down),
          ),
        ],
      ),
    )
  }
  if picker.entries.is_empty() && picker.new_folder is None {
    rows.push(empty_view(picker))
  }
  let can_create = !picker.loading &&
    picker.location is Some(Directory(_)) &&
    picker.new_folder is None
  let folder_count = picker.entries.length()
  let folder_count_label = if folder_count == 1 {
    "1 folder"
  } else {
    "\{folder_count} folders"
  }
  @html.div(class="modal-backdrop picker-backdrop", on_click=emit(Close), [
    @html.div(
      class="modal picker-modal",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_labelledby("project-picker-title")
        .on_click(event => {
          event.stop_propagation()
          @cmd.none
        }),
      [
        @html.div(class="picker-header", [
          @html.div(class="picker-header-leading", [
            @html.span(
              class="picker-header-icon",
              @icons.icon(@icons.icon_folder_opened),
            ),
            @html.div(class="picker-header-copy", [
              @html.div(
                id="project-picker-title",
                class="modal-title",
                "Add a project",
              ),
              @html.div(
                class="picker-subtitle",
                "Choose a folder to use as a project workspace.",
              ),
            ]),
          ]),
          @html.button(
            class="picker-close",
            type_="button",
            title="Close",
            on_click=emit(Close),
            attrs=@html.Attrs::build().aria_label("Close project picker"),
            @icons.icon(@icons.icon_close),
          ),
        ]),
        @html.div(class="picker-location-bar", [
          picker_breadcrumbs(emit, picker),
          @html.button(
            class="picker-new-folder",
            type_="button",
            disabled=!can_create,
            on_click=emit(BeginCreateFolder),
            [@icons.icon(@icons.icon_add), @html.span("New folder")],
          ),
        ]),
        @html.div(class="picker-browser", [
          @html.div(
            class="picker-list",
            attrs=@html.Attrs::build().aria_busy(picker.loading.to_string()),
            [
              @html.div(class="picker-list-heading", [
                @html.span("Name"),
                @html.span(
                  class="picker-list-count",
                  if picker.loading {
                    "Loading…"
                  } else {
                    folder_count_label
                  },
                ),
              ]),
              @html.div(class="picker-list-rows", rows),
            ],
          ),
        ]),
        picker_footer(emit, picker),
      ],
    ),
  ])
}

///|
fn new_folder_row(
  emit : @cmd.Emit[Msg],
  picker : State,
  name : String,
) -> @html.Html {
  let valid = !name.trim().is_empty()
  @html.div(class="picker-create-row", [
    @html.span(class="picker-create-icon", @icons.icon(@icons.icon_folder)),
    @html.input(
      input_type=@html.InputType::Text,
      value=name,
      autofocus=true,
      placeholder="New folder name",
      on_input=emit.map(value => NewFolderNameChanged(value)),
      attrs=@html.Attrs::build()
        .aria_label("New folder name")
        .data_set("focus-owner", "")
        .disabled(picker.loading)
        .on_keydown(event => {
          if event.is_composing() {
            return @cmd.none
          }
          match event.key() {
            "Enter" => {
              event.prevent_default()
              if valid {
                emit(CreateFolder)
              } else {
                @cmd.none
              }
            }
            "Escape" => {
              event.prevent_default()
              emit(CancelCreateFolder)
            }
            _ => @cmd.none
          }
        }),
    ),
    @html.button(
      class="picker-create-cancel",
      type_="button",
      disabled=picker.loading,
      on_click=emit(CancelCreateFolder),
      "Cancel",
    ),
    @html.button(
      class="picker-create-submit",
      type_="button",
      disabled=picker.loading || !valid,
      on_click=emit(CreateFolder),
      if picker.loading {
        "Creating…"
      } else {
        "Create"
      },
    ),
  ])
}

///|
fn empty_view(picker : State) -> @html.Html {
  let (title, detail) = if picker.loading {
    ("Loading folders…", "This should only take a moment.")
  } else {
    ("No folders here", "Create a folder here, or add this location as-is.")
  }
  @html.div(class="picker-empty", attrs=@html.Attrs::build().role("status"), [
    @html.div(class="picker-empty-title", title),
    @html.div(class="picker-empty-detail", detail),
  ])
}

///|
fn picker_footer(emit : @cmd.Emit[Msg], picker : State) -> @html.Html {
  let can_confirm = !picker.loading &&
    picker.location is Some(Directory(_)) &&
    picker.new_folder is None
  @html.div(class="picker-footer", [
    current_location(picker),
    @html.div(class="modal-actions", [
      @html.button(type_="button", on_click=emit(Close), "Cancel"),
      @html.button(
        class="primary",
        type_="button",
        disabled=!can_confirm,
        on_click=emit(Confirm),
        "Add project",
      ),
    ]),
  ])
}

///|
/// The footer keeps the directory being confirmed visible even when the
/// breadcrumb has scrolled horizontally, mirroring a native picker's compact
/// selection summary. A loading navigation intentionally keeps showing the
/// last successful location while the primary action is disabled.
fn current_location(picker : State) -> @html.Html {
  let (label, path) = match picker.location {
    Some(Directory(resource)) => ("Current folder", resource.path)
    Some(DriveList) => ("Location", "This PC")
    None => ("Location", "Loading…")
  }
  @html.div(class="picker-current-location", [
    @html.span(
      class="picker-current-icon",
      @icons.icon(@icons.icon_folder_opened),
    ),
    @html.div(class="picker-current-copy", [
      @html.span(class="picker-current-label", label),
      @html.span(class="picker-current-path", path),
    ]),
  ])
}

///|
/// The current location as a clickable trail: every ancestor is a button
/// that navigates back up to it, the way a system chooser's path bar works.
/// POSIX paths root at `/`; Windows resource paths keep `/C:/` as their
/// drive root and root at the drive list ("This PC"), which is how another
/// drive letter is reached. UNC never reaches this UI because the backend
/// rejects it.
fn picker_breadcrumbs(emit : @cmd.Emit[Msg], picker : State) -> @html.Html {
  let crumbs : Array[@html.Html] = []
  guard picker.location is Some(location) else {
    return @html.div(class="picker-crumbs", crumbs)
  }
  guard location is Directory(resource) else {
    crumbs.push(
      @html.button(
        class="picker-crumb current",
        type_="button",
        disabled=picker.loading,
        on_click=emit(Navigate("/")),
        "This PC",
      ),
    )
    return @html.div(class="picker-crumbs", crumbs)
  }
  let path = resource.path
  let segments : Array[String] = []
  for part in path.split("/") {
    if !part.is_empty() {
      segments.push("\{part}")
    }
  }
  let drive_root = match segments {
    [drive, ..] if drive.length() == 2 && drive.has_suffix(":") => Some(drive)
    _ => None
  }
  crumbs.push(
    @html.button(
      class=if segments.is_empty() {
        "picker-crumb current"
      } else {
        "picker-crumb"
      },
      type_="button",
      disabled=picker.loading,
      on_click=emit(Navigate("/")),
      if drive_root is Some(_) {
        "This PC"
      } else {
        "/"
      },
    ),
  )
  let mut prefix = ""
  for index, segment in segments {
    prefix = if drive_root is Some(_) && index == 0 {
      "/" + segment + "/"
    } else if prefix.has_suffix("/") {
      prefix + segment
    } else {
      prefix + "/" + segment
    }
    crumbs.push(
      @html.span(
        class="picker-crumb-sep",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "›",
      ),
    )
    crumbs.push(
      @html.button(
        class=if index == segments.length() - 1 {
          "picker-crumb current"
        } else {
          "picker-crumb"
        },
        type_="button",
        disabled=picker.loading,
        on_click=emit(Navigate(prefix)),
        segment,
      ),
    )
  }
  @html.div(class="picker-crumbs", crumbs)
}
