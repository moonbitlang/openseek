// The page's transport: browsing the mooncakes.io registry and changing a
// skills library. A host library is reached through the engine-host bridge,
// the Cloud library over the account's Cloud API; both answer with the same
// skill replies, and each request settles as one `Msg`.

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
/// The message for a request that did not produce a reply.
fn request_error_text(error : Error, locale : @i18n.Locale) -> String {
  match error {
    @cloud_client.RequestError(failure) => failure.text(locale)
    error => @interop.bridge_error_text(error)
  }
}

///|
fn install_payload(item : MarketItem) -> @protocol.InstallSkillPayload {
  {
    module_name: item.module_name,
    version: item.version,
    package_path: if item.package_path.is_empty() {
      None
    } else {
      Some(item.package_path)
    },
  }
}

///|
async fn catalog_reply(library : Library) -> @protocol.SkillsCatalogReply {
  match library {
    Host(channel) =>
      @interop.bridge_request(
        channel,
        @commands.skills_catalog,
        @protocol.EmptyPayload::NoPayload,
      )
    Cloud(access) => @cloud_client.skills_catalog(access.token)
  }
}

///|
async fn content_reply(
  library : Library,
  target : PreviewTarget,
) -> @protocol.SkillContentReply {
  match (library, target) {
    (Host(channel), Market(item)) =>
      @interop.bridge_request(
        channel,
        @commands.skills_content,
        install_payload(item),
      )
    (Host(channel), Installed(item)) =>
      @interop.bridge_request(channel, @commands.skills_installed_content, {
        id: item.id,
      })
    (Cloud(access), Market(item)) =>
      @cloud_client.skills_content(access.token, install_payload(item))
    (Cloud(access), Installed(item)) =>
      @cloud_client.skills_installed_content(access.token, item.id)
  }
}

///|
async fn install_reply(
  library : Library,
  item : MarketItem,
) -> @protocol.InstallSkillReply {
  match library {
    Host(channel) =>
      @interop.bridge_request(
        channel,
        @commands.skills_install,
        install_payload(item),
      )
    Cloud(access) =>
      @cloud_client.skills_install(access.token, install_payload(item))
  }
}

///|
async fn uninstall_reply(
  library : Library,
  id : String,
) -> @protocol.UninstallSkillReply {
  match library {
    Host(channel) =>
      @interop.bridge_request(channel, @commands.skills_uninstall, { id, })
    Cloud(access) => @cloud_client.skills_uninstall(access.token, id)
  }
}

///|
async fn set_enabled_reply(
  library : Library,
  payload : @protocol.SetSkillEnabledPayload,
) -> @protocol.SetSkillEnabledReply {
  match library {
    Host(channel) =>
      @interop.bridge_request(channel, @commands.skills_set_enabled, payload)
    Cloud(access) => @cloud_client.skills_set_enabled(access.token, payload)
  }
}

///|
/// The installed library's contents, for the root's mirror.
pub async fn installed_reply(
  library : Library,
) -> @protocol.InstalledSkillsReply {
  match library {
    Host(channel) =>
      @interop.bridge_request(
        channel,
        @commands.skills_installed,
        @protocol.EmptyPayload::NoPayload,
      )
    Cloud(access) => @cloud_client.skills_installed(access.token)
  }
}

///|
/// Fetch the registry's catalog of installable skills.
fn fetch_catalog(
  emit : @cmd.Emit[Msg],
  library : Library,
  locale : @i18n.Locale,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let items = catalog_from_reply(catalog_reply(library)) catch {
        error => {
          scheduler.add(
            emit(
              CatalogFailed(library~, message=request_error_text(error, locale)),
            ),
          )
          return
        }
      }
      scheduler.add(emit(CatalogLoaded(library~, items~)))
    })
    |> ignore
  })
}

///|
fn fetch_content(
  emit : @cmd.Emit[Msg],
  library : Library,
  locale : @i18n.Locale,
  request : Int32,
  target : PreviewTarget,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = content_reply(library, target) catch {
        error => {
          scheduler.add(
            emit(
              PreviewFailed(
                library~,
                request~,
                target~,
                message=request_error_text(error, locale),
              ),
            ),
          )
          return
        }
      }
      let msg = match reply {
        SkillContent(content) =>
          PreviewLoaded(library~, request~, target~, content~)
        SkillContentError(message) =>
          PreviewFailed(library~, request~, target~, message~)
      }
      scheduler.add(emit(msg))
    })
    |> ignore
  })
}

///|
fn fetch_installed_content(
  emit : @cmd.Emit[Msg],
  library : Library,
  locale : @i18n.Locale,
  request : Int32,
  item : InstalledItem,
) -> @cmd.Cmd {
  fetch_content(emit, library, locale, request, Installed(item))
}

///|
/// Run one library-changing action and settle it as `ActionDone`.
fn library_action(
  emit : @cmd.Emit[Msg],
  library : Library,
  locale : @i18n.Locale,
  action : PendingSkillAction,
  run : async () -> String?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let error = run() catch {
        error => Some(request_error_text(error, locale))
      }
      scheduler.add(emit(ActionDone(library~, action~, error~)))
    })
    |> ignore
  })
}

///|
/// Install a catalog entry, including replacing an installed registry skill.
/// The caller supplies the operation label retained until the reply settles.
fn install(
  emit : @cmd.Emit[Msg],
  library : Library,
  locale : @i18n.Locale,
  item : MarketItem,
  action : PendingSkillAction,
) -> @cmd.Cmd {
  library_action(emit, library, locale, action, async fn() {
    match install_reply(library, item) {
      SkillInstalled(_) => None
      SkillInstallError(message) => Some(message)
    }
  })
}

///|
/// Remove one registry-installed skill from the library. The pending
/// operation retains its source after the library entry disappears.
fn uninstall(
  emit : @cmd.Emit[Msg],
  library : Library,
  locale : @i18n.Locale,
  item : InstalledItem,
) -> @cmd.Cmd {
  let action = Uninstalling(source=item.source, id=item.id)
  library_action(emit, library, locale, action, async fn() {
    match uninstall_reply(library, item.id) {
      SkillUninstalled => None
      SkillUninstallError(message) => Some(message)
    }
  })
}

///|
fn set_enabled(
  emit : @cmd.Emit[Msg],
  library : Library,
  locale : @i18n.Locale,
  payload : @protocol.SetSkillEnabledPayload,
  action : PendingSkillAction,
) -> @cmd.Cmd {
  library_action(emit, library, locale, action, async fn() {
    match set_enabled_reply(library, payload) {
      SkillEnabledSet => None
      SkillEnabledError(message) => Some(message)
    }
  })
}
