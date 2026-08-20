// The page's host transport: browsing the mooncakes.io registry and changing
// the engine's global skills library. All three are plain request/reply calls
// on the engine-host bridge, and each settles as one `Msg`.

///|
/// Fetch the registry's catalog of installable skills.
fn fetch_catalog(
  emit : @cmd.Emit[Msg],
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
          scheduler.add(emit(CatalogFailed(@interop.bridge_error_text(error))))
          return
        }
      }
      scheduler.add(emit(CatalogLoaded(catalog_from_reply(reply))))
    })
  })
}

///|
/// Install one catalog entry into the global skills library. Settles with an
/// `ActionDone` either way; the busy key is the entry's source label.
fn install(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  item : MarketItem,
) -> @cmd.Cmd {
  let key = source_label(item)
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
              emit(
                ActionDone(
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
      scheduler.add(emit(ActionDone(channel~, key~, error="")))
    })
  })
}

///|
/// Remove one registry-installed skill from the library; the busy key is
/// the library entry's id.
fn uninstall(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(channel, @commands.skills_uninstall, { id, }) catch {
          error => {
            scheduler.add(
              emit(
                ActionDone(
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
      scheduler.add(emit(ActionDone(channel~, key=id, error="")))
    })
  })
}
