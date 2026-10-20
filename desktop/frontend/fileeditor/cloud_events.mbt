///|
priv suberror CloudFilesSubscription {
  CloudFilesSubscription(
    @interop.ConversationIdentity,
    CloudFiles,
    @cmd.Emit[Msg]
  )
}

///|
/// The stream belongs to the authenticated session, independent of the read
/// epoch advanced by invalidation. Hidden documents stay cached and lazy.
fn cloud_files_subscription(ctx : Ctx, emit : @cmd.Emit[Msg]) -> @sub.Sub {
  guard ctx.owner is @interop.Cloud(session~, ..) &&
    ctx.cloud_files is Some(files) else {
    return @sub.none
  }
  @sub.custom_sub(
    "cloud-files:" + ctx.owner.key() + ":" + files.epoch.to_string(),
    Local,
    CloudFilesSubscription(ctx.owner, files, emit),
    (payload, scheduler) => {
      guard payload is CloudFilesSubscription(owner, files, emit) else {
        return None
      }
      let mut emit = emit
      let active = Ref(true)
      let client : Ref[@http.Client?] = Ref(None)
      @js.Promise::from_async(() => {
        while active.val {
          let retry = try {
            @cloud_client.watch_files(
              files.token,
              session,
              opened => client.val = Some(opened),
              () => active.val,
              () => {
                if active.val {
                  scheduler.add(
                    emit(WorkspaceInvalidated(owner~, auth_epoch=files.epoch)),
                  )
                }
              },
            )
            true
          } catch {
            @cloud_client.RequestError(Unauthorized | Http(404)) => false
            _ => true
          }
          client.val = None
          guard active.val else { break }
          guard retry else { break }
          @async.sleep(1500)
        }
      })
      |> ignore
      Some({
        unload: _ => {
          active.val = false
          if client.val is Some(client) {
            client.close()
          }
        },
        update_tagger: payload => {
          if payload is CloudFilesSubscription(_, _, next) {
            emit = next
          }
        },
      })
    },
  )
}
