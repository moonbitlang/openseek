///|
priv suberror ImportError {
  ImportError(String)
}

///|
fn import_source(
  target : Target,
  source : @protocol.SessionImportSource,
  generation : Int32,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = try {
        let workspace = match target.workspace {
          Registered(path) | Allocated(path) => path
          Unplaced => {
            let path = match
              @interop.bridge_request(
                target.channel,
                @commands.fs_create_unnamed_workspace,
                @protocol.NoPayload,
              ) {
              Listing(path~, ..) => path
              BrowseError(message) => raise ImportError(message)
              Drives(_) => raise ImportError("Expected a chat workspace.")
            }
            scheduler.add(emit(WorkspaceChanged(generation, Allocated(path))))
            path
          }
        }
        if target.workspace is (Unplaced | Allocated(_)) {
          match
            @interop.bridge_request(target.channel, @commands.workspace_add, {
              path: workspace,
            }) {
            Workspaces(_, ..) => ()
            WorkspaceError(message) => raise ImportError(message)
          }
          scheduler.add(
            emit(WorkspaceChanged(generation, Registered(workspace))),
          )
        }
        @interop.bridge_request(target.channel, @commands.session_import, {
          source,
          workspace,
          worktree_of: target.worktree_of,
        })
      } catch {
        ImportError(message) => @protocol.Failed(message)
        error => @protocol.Failed(@interop.bridge_error_text(error))
      }
      scheduler.add(emit(Imported(generation, reply)))
    })
    |> ignore
  })
}

///|
/// DOM handles and file reads stay inside a command, using existing typed
/// Rabbita DOM/JS bindings. Cancel emits a result just like a selected file.
fn pick_file(generation : Int32, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let input = @dom.document().create_element("input")
    input.set_attribute("type", "file")
    input.set_attribute("accept", ".json,application/json")
    input.set_attribute("hidden", "")
    fn remove() {
      let _ : Unit = @js.Value::cast_from(input).apply_with_string(
        "remove",
        ([] : FixedArray[@js.Value]),
      )
    }
    input.add_event_listener_with_options(
      "cancel",
      _ => {
        remove()
        scheduler.add(emit(Picked(generation, Ok(None))))
      },
      once=true,
    )
    input.add_event_listener_with_options(
      "change",
      _ => {
        let files : @js.Value = @js.Value::cast_from(input).get_with_string(
          "files",
        )
        let file : @js.Nullable[@js.Value] = files.apply_with_string("item", [
          @js.Value::cast_from(0),
        ])
        remove()
        guard file.to_option() is Some(file) else {
          scheduler.add(emit(Picked(generation, Ok(None))))
          return
        }
        @js.Promise::from_async(() => {
          let blob : @dom.Blob = file.cast()
          let result = if blob.get_size() > 16 * 1024 * 1024 {
            Err("JSON must be no larger than 16 MiB.")
          } else {
            Ok(Some(blob.text())) catch {
              error => Err(@interop.bridge_error_text(error))
            }
          }
          scheduler.add(emit(Picked(generation, result)))
        })
        |> ignore
      },
      once=true,
    )
    if @dom.document().get_body() is Some(body) {
      body.append_child(input.as_node())
    }
    if input.to_html_element() is Some(element) {
      element.click()
    }
  })
}
