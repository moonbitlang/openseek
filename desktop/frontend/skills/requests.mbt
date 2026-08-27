// The page's host transport: browsing the mooncakes.io registry and changing
// the engine's global skills library. All three are plain request/reply calls
// on the engine-host bridge, and each settles as one `Msg`.

///|
extern "js" fn copy_text_to_clipboard(text : String) -> Unit =
  #| (text) => {
  #|   try {
  #|     const clipboard = globalThis.navigator?.clipboard;
  #|     if (clipboard && typeof clipboard.writeText === "function") {
  #|       clipboard.writeText(text).catch(() => {});
  #|     }
  #|   } catch {
  #|   }
  #| }

///|
fn copy_content(content : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => copy_text_to_clipboard(content))
}

///|
fn restore_list_scroll(scroll_top : Double) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().query_selector(".skills-page").to_option()
        is Some(page) {
        page.set_scroll_top(scroll_top)
      }
    },
    kind=@cmd.after_render,
  )
}

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
          scheduler.add(
            emit(
              CatalogFailed(channel~, message=@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      scheduler.add(
        emit(CatalogLoaded(channel~, items=catalog_from_reply(reply))),
      )
    })
  })
}

///|
fn fetch_content(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  request_id : String,
  target : PreviewTarget,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      match target {
        Market(item) => {
          let reply = @interop.bridge_request(
            channel,
            @commands.skills_content,
            {
              module_name: item.module_name,
              version: item.version,
              package_path: if item.package_path.is_empty() {
                None
              } else {
                Some(item.package_path)
              },
            },
          ) catch {
            error => {
              scheduler.add(
                emit(
                  PreviewFailed(
                    request_id~,
                    message=@interop.bridge_error_text(error),
                  ),
                ),
              )
              return
            }
          }
          scheduler.add(emit(preview_reply(request_id, reply)))
        }
        Installed(item) => {
          let reply = @interop.bridge_request(
            channel,
            @commands.skills_installed_content,
            { id: item.id, },
          ) catch {
            error => {
              scheduler.add(
                emit(
                  PreviewFailed(
                    request_id~,
                    message=@interop.bridge_error_text(error),
                  ),
                ),
              )
              return
            }
          }
          scheduler.add(emit(preview_reply(request_id, reply)))
        }
      }
    })
  })
}

///|
fn preview_reply(request_id : String, reply : @protocol.ReadFileReply) -> Msg {
  match reply {
    @protocol.ReadFileReply::Content(content~, ..) =>
      PreviewLoaded(request_id~, content~)
    _ => PreviewFailed(request_id~, message="SKILL.md is not readable")
  }
}

///|
fn fetch_installed_content(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  request_id : String,
  item : InstalledItem,
) -> @cmd.Cmd {
  fetch_content(emit, channel, request_id, Installed(item))
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
