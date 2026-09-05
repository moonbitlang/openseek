// A compact, host-backed folder chooser. The location bar behaves like a
// system picker, while the inline composer can create and enter a folder
// without leaving the add-project flow. Keyboard capture lives in `keys.mbt`;
// focused controls keep their own Enter and Escape behavior here.

///|
const PathInputId : String = "project-picker-path-input"

///|
const PathListId : String = "project-picker-folder-list"

///|
const NewFolderInputId : String = "project-picker-new-folder-input"

///|
fn path_row_id(index : Int) -> String {
  "project-picker-folder-\{index}"
}

///|
/// Focus the path after rendering it, selecting the whole value so typing
/// replaces it. Completion browses leave the editor enabled, so it keeps
/// focus and caret on its own while they run.
fn focus_path_after_render() -> @cmd.Cmd {
  focus_after_render(PathInputId, select_all=true)
}

///|
/// Focus the new-folder composer after rendering it, keeping whatever name
/// a failed create left behind.
fn focus_new_folder_after_render() -> @cmd.Cmd {
  focus_after_render(NewFolderInputId, select_all=false)
}

///|
fn focus_after_render(id : String, select_all~ : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => focus_input(id, select_all), kind=@cmd.after_render)
}

///|
extern "js" fn focus_input(id : String, select_all : Bool) -> Unit =
  #| (id, selectAll) => {
  #|   const input = document.getElementById(id);
  #|   if (!input) return;
  #|   input.focus();
  #|   if (selectAll) return input.select();
  #|   const end = input.value.length;
  #|   input.setSelectionRange(end, end);
  #| }

///|
/// Keep keyboard completion visible while focus stays in the combobox.
fn scroll_path_row_after_render(index : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => scroll_path_row(path_row_id(index)),
    kind=@cmd.after_render,
  )
}

///|
extern "js" fn scroll_path_row(id : String) -> Unit =
  #| (id) => document.getElementById(id)?.scrollIntoView({ block: "nearest" })

///|
pub fn view(emit : @cmd.Emit[Msg], picker : State) -> @html.Html {
  let visible_entries = picker.visible_entries()
  let filter_active = !picker.path_filter().is_empty()
  let suggestion_active = picker.selected_path_suggestion() is Some(_)
  let path_editing = picker.path_draft is Some(_)
  let rows : Array[@html.Html] = []
  if picker.new_folder is Some(name) {
    rows.push(new_folder_row(emit, picker, name))
  }
  for index, name in visible_entries {
    let target = picker.entry_target(name)
    let selected = suggestion_active && index == picker.path_selection
    let row_attrs = @html.Attrs::build()
      .id(path_row_id(index))
      .aria_label("Open folder \{name}")
    let row_attrs = if path_editing {
      row_attrs.role("option").aria_selected(selected.to_string())
    } else {
      row_attrs
    }
    rows.push(
      @html.button(
        class=if selected { "picker-row selected" } else { "picker-row" },
        type_="button",
        disabled=picker.loading,
        on_click=emit(Navigate(target)),
        attrs=row_attrs,
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
  if visible_entries.is_empty() && picker.new_folder is None {
    rows.push(empty_view(picker, filter_active))
  }
  let can_create = picker.actionable_directory() is Some(_)
  let folder_count = visible_entries.length()
  let folder_count_label = if filter_active {
    if folder_count == 1 {
      "1 match"
    } else {
      "\{folder_count} matches"
    }
  } else if folder_count == 1 {
    "1 folder"
  } else {
    "\{folder_count} folders"
  }
  let list_attrs = @html.Attrs::build()
    .id(PathListId)
    .aria_label("Folders")
    .aria_busy(picker.loading.to_string())
  let list_attrs = if path_editing {
    list_attrs.role("listbox")
  } else {
    list_attrs
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
          match picker.path_draft {
            Some(value) => path_editor(emit, picker, value, suggestion_active)
            None => picker_breadcrumbs(emit, picker)
          },
          @html.button(
            class="picker-new-folder",
            type_="button",
            disabled=!can_create,
            on_click=emit(BeginCreateFolder),
            [@icons.icon(@icons.icon_add), @html.span("New folder")],
          ),
        ]),
        @html.div(class="picker-browser", [
          @html.div(class="picker-list", attrs=list_attrs, [
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
          ]),
        ]),
        picker_footer(emit, picker),
      ],
    ),
  ])
}

///|
fn path_editor(
  emit : @cmd.Emit[Msg],
  picker : State,
  value : String,
  suggestion_active : Bool,
) -> @html.Html {
  let base_attrs = @html.Attrs::build()
    .id(PathInputId)
    .role("combobox")
    .aria_label("Folder path")
    .aria_controls(PathListId)
    .aria_expanded("true")
    .aria_autocomplete("list")
    .aria_keyshortcuts("Meta+L Control+L")
    .data_set("focus-owner", "")
    .on_keydown(event => {
      if event.is_composing() {
        return @cmd.none
      }
      match event.key() {
        "ArrowDown" => {
          event.prevent_default()
          emit(MovePathSelection(1))
        }
        "ArrowUp" => {
          event.prevent_default()
          emit(MovePathSelection(-1))
        }
        "Tab" =>
          if picker.selected_path_suggestion() is Some(_) {
            event.prevent_default()
            emit(CompletePath)
          } else {
            @cmd.none
          }
        "Enter" => {
          event.prevent_default()
          emit(SubmitPath)
        }
        "Escape" => {
          event.prevent_default()
          emit(CancelPathEdit)
        }
        _ => @cmd.none
      }
    })
  let input_attrs = if suggestion_active &&
    picker.visible_entries().get(picker.path_selection) is Some(_) {
    base_attrs.aria_activedescendant(path_row_id(picker.path_selection))
  } else {
    base_attrs
  }
  @html.div(class="picker-path-editor", [
    @html.span(
      class="picker-path-editor-icon",
      attrs=@html.Attrs::build().aria_hidden("true"),
      @icons.icon(@icons.icon_folder_opened),
    ),
    @html.input(
      input_type=@html.InputType::Text,
      value~,
      autofocus=true,
      placeholder="Enter a folder path",
      on_input=emit.map(next => PathChanged(next)),
      attrs=input_attrs,
    ),
    @html.button(
      class="picker-path-editor-cancel",
      type_="button",
      title="Cancel path editing",
      on_click=emit(CancelPathEdit),
      attrs=@html.Attrs::build().aria_label("Cancel path editing"),
      @icons.icon(@icons.icon_close),
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
        .id(NewFolderInputId)
        .aria_label("New folder name")
        .data_set("focus-owner", "")
        .disabled(picker.loading)
        .on_keydown(event => {
          if event.is_composing() {
            return @cmd.none
          }
          match event.key() {
            "Enter" => {
              // Deciding validity here would read the name captured at the
              // last paint, missing keystrokes still inside the same frame —
              // typing a name and pressing Enter at once created nothing.
              // `CreateFolder` checks the current name itself.
              event.prevent_default()
              emit(CreateFolder)
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
fn empty_view(picker : State, filter_active : Bool) -> @html.Html {
  let (title, detail) = if picker.loading {
    ("Loading folders…", "This should only take a moment.")
  } else if !picker.listing_completes_draft() {
    // The host's own refusal, so permissions, a missing directory, and a
    // non-directory path read differently in place.
    let reason = match picker.completion_browse {
      Some(Refused(_, message~)) => message
      _ => "Check the path, or press Enter to open it and see why."
    }
    ("Cannot list this folder", reason)
  } else if filter_active {
    ("No matching folders", "Try a different name or enter a complete path.")
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
  let can_confirm = picker.actionable_directory() is Some(_)
  @html.div(class="picker-footer", [
    current_location(picker),
    @html.div(class="modal-actions", [
      @html.button(
        class="button secondary",
        type_="button",
        on_click=emit(Close),
        "Cancel",
      ),
      @html.button(
        class="button primary",
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
    Some(Directory(path)) => ("Current folder", path)
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
/// All protocol paths root at `/`. The host interprets that as the POSIX
/// filesystem root or the Windows drive list, so the frontend never needs to
/// guess a platform from a drive-shaped path. UNC never reaches this UI
/// because the backend rejects it.
fn picker_breadcrumbs(emit : @cmd.Emit[Msg], picker : State) -> @html.Html {
  let crumbs : Array[@html.Html] = []
  guard picker.location is Some(location) else {
    return @html.div(class="picker-crumbs", crumbs)
  }
  guard location is Directory(path) else {
    crumbs.push(
      @html.button(
        class="picker-crumb current",
        type_="button",
        title="Edit path (⌘L)",
        disabled=picker.loading,
        on_click=emit(EditPath),
        attrs=@html.Attrs::build().aria_label("Edit current path"),
        "This PC",
      ),
    )
    return @html.div(class="picker-crumbs", crumbs)
  }
  let segments : Array[String] = []
  for part in path.split("/") {
    if !part.is_empty() {
      segments.push("\{part}")
    }
  }
  crumbs.push(
    @html.button(
      class=if segments.is_empty() {
        "picker-crumb current"
      } else {
        "picker-crumb"
      },
      type_="button",
      title=if segments.is_empty() { "Edit path (⌘L)" } else { "Open root" },
      disabled=picker.loading,
      on_click=if segments.is_empty() {
        emit(EditPath)
      } else {
        emit(Navigate("/"))
      },
      attrs=if segments.is_empty() {
        @html.Attrs::build().aria_label("Edit current path")
      } else {
        @html.Attrs::build().aria_label("Open root folder")
      },
      "/",
    ),
  )
  let mut prefix = ""
  for index, segment in segments {
    // A trailing slash is equivalent on POSIX and is required by the host's
    // reversible Windows drive-root protocol spelling.
    prefix = if index == 0 && segment.has_suffix(":") {
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
        title=if index == segments.length() - 1 {
          "Edit path (⌘L)"
        } else {
          "Open \{segment}"
        },
        disabled=picker.loading,
        on_click=if index == segments.length() - 1 {
          emit(EditPath)
        } else {
          emit(Navigate(prefix))
        },
        attrs=if index == segments.length() - 1 {
          @html.Attrs::build().aria_label("Edit current path")
        } else {
          @html.Attrs::build().aria_label("Open folder \{segment}")
        },
        segment,
      ),
    )
  }
  @html.div(class="picker-crumbs", crumbs)
}
