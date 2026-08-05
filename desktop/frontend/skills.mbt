// The Skills panel's commands: browsing the mooncakes.io registry and
// managing the engine's global skills library through the host's skill ops.
// All four are plain request/reply calls on the engine-host bridge.

///|
/// Fetch the registry's catalog of installable skills.
fn fetch_skills_catalog(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.skills_catalog,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(SkillsCatalogFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          SkillsCatalogLoaded(@transcript.skills_catalog_from_reply(reply)),
        ),
      )
    })
  })
}

///|
/// Refresh the local skills library's contents.
fn fetch_installed_skills(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.skills_installed,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(InstalledSkillsFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          InstalledSkillsLoaded(@transcript.installed_skills_from_reply(reply)),
        ),
      )
    })
  })
}

///|
/// Install one catalog entry into the global skills library. Settles with a
/// `SkillActionDone` either way; the busy key is the entry's source label.
fn install_skill(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  item : @transcript.MarketSkillItem,
) -> @cmd.Cmd {
  let key = @transcript.market_source_label(item)
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(channel, @commands.skills_install, {
          module_name: item.module_name,
          version: item.version,
          package_path: if item.package_path.is_empty() {
            None
          } else {
            Some(item.package_path)
          },
        }) catch {
          error => {
            scheduler.add(
              dispatch(
                SkillActionDone(
                  channel~,
                  key~,
                  error=@interop.bridge_error_text(error),
                ),
              ),
            )
            return
          }
        },
      )
      scheduler.add(dispatch(SkillActionDone(channel~, key~, error="")))
    })
  })
}

///|
/// Remove one registry-installed skill from the library; the busy key is
/// the library entry's id.
fn uninstall_skill(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(channel, @commands.skills_uninstall, { id, }) catch {
          error => {
            scheduler.add(
              dispatch(
                SkillActionDone(
                  channel~,
                  key=id,
                  error=@interop.bridge_error_text(error),
                ),
              ),
            )
            return
          }
        },
      )
      scheduler.add(dispatch(SkillActionDone(channel~, key=id, error="")))
    })
  })
}
