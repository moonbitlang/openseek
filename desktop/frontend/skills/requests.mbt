// The page's host transport: browsing the mooncakes.io registry and changing
// the engine's global skills library. All three are plain request/reply calls
// on the engine-host bridge, and each settles as one `Msg`.

///|
/// Best effort: a rejected clipboard write (no permission, no API) is not
/// worth a message, so neither outcome maps back into update.
fn copy_content(content : String) -> @cmd.Cmd {
  @clipboard.copy(@clipboard.Text(content))
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
    @js.Promise::from_async(() => {
      let items = try {
        let reply = @interop.bridge_request(
          channel,
          @commands.skills_catalog,
          @protocol.EmptyPayload::NoPayload,
        )
        catalog_from_reply(reply)
      } catch {
        error => {
          scheduler.add(
            emit(
              CatalogFailed(channel~, message=@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      scheduler.add(emit(CatalogLoaded(channel~, items~)))
    })
    |> ignore
  })
}

///|
fn fetch_content(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  request : Int,
  target : PreviewTarget,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
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
                    request~,
                    target~,
                    message=@interop.bridge_error_text(error),
                  ),
                ),
              )
              return
            }
          }
          scheduler.add(emit(preview_reply(request, target, reply)))
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
                    request~,
                    target~,
                    message=@interop.bridge_error_text(error),
                  ),
                ),
              )
              return
            }
          }
          scheduler.add(emit(preview_reply(request, target, reply)))
        }
      }
    })
    |> ignore
  })
}

///|
fn preview_reply(
  request : Int,
  target : PreviewTarget,
  reply : @protocol.SkillContentReply,
) -> Msg {
  match reply {
    SkillContent(content) => PreviewLoaded(request~, target~, content~)
    SkillContentError(message) => PreviewFailed(request~, target~, message~)
  }
}

///|
fn fetch_installed_content(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  request : Int,
  item : InstalledItem,
) -> @cmd.Cmd {
  fetch_content(emit, channel, request, Installed(item))
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
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(channel, @commands.skills_install, {
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
      }
      let error = match reply {
        SkillInstalled(_) => ""
        SkillInstallError(message) => message
      }
      scheduler.add(emit(ActionDone(channel~, key~, error~)))
    })
    |> ignore
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
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(channel, @commands.skills_uninstall, {
        id,
      }) catch {
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
      }
      let error = match reply {
        SkillUninstalled => ""
        SkillUninstallError(message) => message
      }
      scheduler.add(emit(ActionDone(channel~, key=id, error~)))
    })
    |> ignore
  })
}
