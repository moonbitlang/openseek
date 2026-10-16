///|
fn ssh_load_cached_projects(dispatch : @cmd.Emit[Msg], id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[Array[String]?, String] = Ok(
        @interop.bridge_request(Local, @commands.ssh_cached_projects, { id, }),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(Ssh(CachedProjects(id, result))))
    })
    |> ignore
  })
}

///|
fn ssh_cache_projects(
  dispatch : @cmd.Emit[Msg],
  id : String,
  projects : Array[@common.Uri],
) -> @cmd.Cmd {
  let paths = projects.filter_map(uri => @resource.path_for(uri, Remote(id)))
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      ignore(
        @interop.bridge_request_in_order(
          Local,
          @commands.ssh_cache_projects,
          { id, paths, },
          lane="ssh-projects:" + id,
        ),
      ) catch {
        error =>
          scheduler.add(
            dispatch(
              HostActionFailed(
                "Could not save remote project catalog: " +
                @interop.bridge_error_text(error),
              ),
            ),
          )
      }
    })
    |> ignore
  })
}
