///|
let ssh_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  "ssh.event",
)

///|
fn DesktopBridgeActor::route_for(
  self : DesktopBridgeActor,
  id : String,
) -> @ssh.Route? {
  self.routes.get(id)
}

///|
/// Each host keeps its app-server connection and independent SSH terminals.
/// The page generation fences events already queued when a page is replaced.
async fn DesktopBridgeActor::run_attached_remote(
  self : DesktopBridgeActor,
  route : @ssh.Route,
  generation : Int32,
  attachment : Int32,
) -> Unit {
  let emit : async (Json) -> Unit = event => {
    self.inbox.put(
      Deliver(
        Ssh({
          "host_id": route.profile.id,
          "attachment": generation,
          "route": attachment,
          "event": event,
        }),
      ),
    )
  }
  defer route.close_terminals()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      route.run_terminals(notification => {
        emit({
          "kind": "terminal",
          "value": {
            "method": notification.wire_name(),
            "params": notification.params(),
          },
        })
      })
    })
    route.run(emit=event => emit(event.to_json())) catch {
      error => emit({ "kind": "failed", "message": "\{error}" })
    }
    group.return_immediately(())
  })
}

///|
/// OS-owned commands must select the same host as the project. They must
/// never interpret a remote path or a remote terminal id on the local host.
async fn DesktopBridgeActor::remote_host_request(
  self : DesktopBridgeActor,
  context : @proton.CommandContext,
  state : @api.DesktopState,
  request : @protocol.SshHostRequest,
) -> @protocol.SshReply {
  guard self.route_for(request.host_id) is Some(route) else {
    return SshUnsent("This SSH host is not connected in this window")
  }
  try {
    for endpoint in route.terminal_endpoints() {
      if endpoint.name() == request.method_ {
        return SshSuccess(endpoint.invoke(request.params))
      }
    }
    if request.method_ == @commands.host_open_path_preview.name() {
      let payload : @protocol.OpenPathPayload = @json.from_json(request.params)
      let reply : @protocol.OpenPathReply = match
        route.request_current(@commands.fs_resolve_reference, payload) {
        ReferenceText(path~, line~, column~) => Editor({ path, line, column, })
        ReferenceDirectory(path~) => Directory({ path, })
        ReferenceRefused(message~) => Refused(message)
        ReferenceBinary(path~) =>
          RemotePreview(local_path=route.preview_file(path), remote_path=path)
      }
      return SshSuccess(reply.to_json())
    }
    if request.method_ == @commands.session_export.name() {
      let payload : @protocol.SessionExportPayload = @json.from_json(
        request.params,
      )
      return SshSuccess(
        export_session(context, state, payload, remote=route).to_json(),
      )
    }
    if request.method_ == @commands.session_share.name() {
      let payload : @protocol.SessionSharePayload = @json.from_json(
        request.params,
      )
      return SshSuccess(
        state
        .share_content(
          payload.source,
          () => capture_session_export(state, payload.source, remote=route),
          on_progress=progress => {
            self.inbox.put(
              Deliver(
                Hub(
                  SessionShareProgress({
                    generation: payload.generation,
                    progress,
                  }),
                ),
              ),
            ) catch {
              _ => ()
            }
          },
        )
        .to_json(),
      )
    }
    SshUnsent("This operation is not an SSH desktop command")
  } catch {
    error => SshUnknown("\{error}")
  }
}
