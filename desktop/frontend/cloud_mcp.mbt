///|
priv suberror CloudMcpConnection {
  CloudMcpConnection
}

///|
/// Every real Cloud conversation opened on this device keeps its connection
/// across selection changes. Account retirement unloads all sockets and timers.
fn cloud_mcp_subscriptions(model : Model, emit : @cmd.Emit[Msg]) -> @sub.Sub {
  guard model.is_desktop &&
    !model.cloud.needs_sign_in &&
    model.account is Some(account) else {
    return @sub.batch([])
  }
  @sub.batch(
    [
      for session, _ in model.cloud.conversations if model.cloud
      .draft_identity()
      .map_or(true, owner => owner.session() != session) &&
      !model.cloud.retired.contains(session) &&
      !model.cloud.deletions.contains(session) => {
        cloud_mcp_connection(account, model.cloud.epoch, session, emit)
      }
    ],
  )
}

///|
fn cloud_mcp_connection(
  account : @protocol.AccountSession,
  epoch : Int32,
  session : String,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  @sub.custom_sub(
    "cloud-mcp-\{epoch}:\{account.user.user_id}:\{session}",
    Local,
    CloudMcpConnection,
    (_, scheduler) => {
      let active = Ref(true)
      let current : Ref[@js.Value?] = Ref(None)
      let timer : Ref[@common.Disposable?] = Ref(None)
      let account_id = account.user.user_id
      let ready_changed = ready => {
        scheduler.add(
          emit(CloudAction(@cloud.ClientToolsReady(epoch, session, ready))),
        )
      }
      fn connect() -> Unit {
        guard active.val else { return }
        let origin = if @cloud.CloudOrigin.has_prefix("https://") {
          "wss://" + @cloud.CloudOrigin[8:].to_owned()
        } else {
          "ws://" + @cloud.CloudOrigin[7:].to_owned()
        }
        let url = origin + "/v1/sessions/\{@uri.encode_component(session)}/mcp"
        let ctor : @js.Value = @js.globalThis.get_with_string("WebSocket")
        let socket : @js.Value = ctor.new([url])
        current.val = Some(socket)
        let ready = Ref(false)
        let live = () => {
          active.val &&
          current.val.map_or(false, value => physical_equal(value, socket))
        }
        let send = (message : Json) => {
          let _ : @js.Value = socket.apply_with_string("send", [
            @js.Value::cast_from(message.stringify()),
          ])
        }
        socket.set_with_string("onopen", (_ : @js.Value) => {
          if live() {
            send({ "type": "auth", "token": Json(account.token) })
          }
        })
        socket.set_with_string("onmessage", (event : @js.Value) => {
          guard live() &&
            @interop.js_prop(event, "data") is Some(data) &&
            (@js.Cast::into(data) : String?) is Some(text) else {
            return
          }
          let message = @json.parse(text) catch { _ => return }
          if !ready.val {
            guard message is { "type": "ready", .. } else { return }
            ready.val = true
            if timer.val is Some(handle) {
              handle.dispose()
              timer.val = None
            }
            ready_changed(true)
            scheduler.add(
              @cmd.attempt(
                result => {
                  match result {
                    Ok(snapshot) =>
                      emit(
                        CloudQuestions(
                          account=account_id,
                          @user_questions.Snapshot(snapshot),
                        ),
                      )
                    Err(_) => @cmd.none
                  }
                },
                () => {
                  let reply = @interop.bridge_request(
                    Local,
                    @commands.cloud_mcp,
                    @protocol.CloudMcpRequest::Questions(account=account_id),
                  )
                  @json.from_json(reply)
                },
              ),
            )
            return
          }
          // TODO: bound concurrent dispatches if the service broadcasts bursts
          // large enough to overload this device. Calls are not replayed.
          @js.Promise::from_async(() => {
            let answer : Json = @interop.bridge_request(
              Local,
              @commands.cloud_mcp,
              @protocol.CloudMcpRequest::Dispatch(
                account=account_id,
                session~,
                message~,
              ),
            ) catch {
              error => {
                // A failed host hop ends the connection. Dispatcher owns
                // protocol errors and tool-failure responses.
                if live() {
                  scheduler.add(
                    emit(HostActionFailed(@interop.bridge_error_text(error))),
                  )
                  let _ : @js.Value = socket.apply_with_string(
                    "close",
                    ([] : FixedArray[@js.Value]),
                  )
                }
                return
              }
            }
            // Reconnect never resends a request or a reply from an older socket.
            if live() && answer != null {
              send(answer)
            }
          })
          |> ignore
        })
        socket.set_with_string("onclose", (_ : @js.Value) => {
          guard live() else { return }
          current.val = None
          if timer.val is Some(handle) {
            handle.dispose()
          }
          ready_changed(false)
          // A later answer must use Cloud input rather than an MCP reply to
          // this dead socket. Finish detaching before accepting new calls.
          @js.Promise::from_async(() => {
            let _ : Json = @interop.bridge_request(
              Local,
              @commands.cloud_mcp,
              @protocol.CloudMcpRequest::Detach(account=account_id, session~),
            ) catch {
              _ => null
            }
            if active.val {
              timer.val = Some(@base_browser.schedule_timeout(connect, 1500))
            }
          })
          |> ignore
        })
        timer.val = Some(
          @base_browser.schedule_timeout(
            () => {
              if live() && !ready.val {
                let _ : @js.Value = socket.apply_with_string(
                  "close",
                  ([] : FixedArray[@js.Value]),
                )
              }
            },
            10000,
          ),
        )
      }
      connect()
      Some({
        unload: _ => {
          active.val = false
          if timer.val is Some(handle) {
            handle.dispose()
          }
          if current.val is Some(socket) {
            let _ : @js.Value = socket.apply_with_string(
              "close",
              ([] : FixedArray[@js.Value]),
            )
          }
          current.val = None
        },
        update_tagger: _ => (),
      })
    },
  )
}
