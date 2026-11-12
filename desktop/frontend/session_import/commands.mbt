///|
fn import_source(
  target : Target,
  source : @protocol.SessionImportSource,
  generation : Int32,
  emit : @cmd.Emit[Msg],
  account~ : @protocol.AccountSession?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply : Result[String, Failure] = match target {
        Host(target) =>
          try {
            match
              @interop.bridge_request(
                target.channel,
                @commands.session_import,
                {
                  source,
                  workspace: target.workspace,
                  worktree_of: target.worktree_of,
                },
              ) {
              Success(id) => Ok(id)
              Failed(message) => Err(Diagnostic(message))
            }
          } catch {
            error => Err(Bridge(@interop.bridge_problem(error)))
          }
        // The dialog outlives the sign-in it opened under; a changed account
        // must not receive another account's import.
        Cloud(account=owner) =>
          match account {
            Some(session) if session.user.user_id == owner =>
              @cloud.import_session(session.token, source).map_err(failure => {
                Failure::Cloud(failure)
              })
            _ => Err(Failure::Cloud(@cloud_client.Unauthorized))
          }
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
            Err(FileTooLarge)
          } else {
            Ok(Some(blob.text())) catch {
              error => Err(Bridge(@interop.bridge_problem(error)))
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
