// The sidebar's archive flow: `archive_session` asks the host to zip a
// conversation's workspace folder away, `archived_sessions` reads back which
// ids are archived. Both ops reply with the full archived list, so one
// decoder serves the startup fetch and the action alike.

///|
fn fetch_archived(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // A host without the op (or without runtime state) just reads as an
      // empty Archived group.
      let reply = bridge_request(
        "archived_sessions",
        @js.Object::new().to_value(),
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(ArchivedLoaded(decode_archived(reply_json_text(reply)))),
      )
    })
  })
}

///|
fn archive_session(dispatch : @cmd.Emit[Msg], session : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      let reply = bridge_request("archive_session", payload.to_value()) catch {
        error => {
          scheduler.add(dispatch(ArchiveFailed(bridge_error_text(error))))
          return
        }
      }
      scheduler.add(
        dispatch(ArchivedLoaded(decode_archived(reply_json_text(reply)))),
      )
    })
  })
}

///|
fn decode_archived(text : String) -> Array[String] {
  let json = @json.parse(text) catch { _ => return [] }
  guard json is Object(reply) else { return [] }
  guard reply.get("sessions") is Some(Array(items)) else { return [] }
  let ids : Array[String] = []
  for item in items {
    if item is String(id) && !id.is_empty() {
      ids.push(id)
    }
  }
  ids
}
