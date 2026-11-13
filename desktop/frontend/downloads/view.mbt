///|
/// The downloads alone, for a page that shows them in place.
pub fn Model::list(self : Model, locale : @i18n.Locale) -> @html.Html {
  self.targets_list(locale, _ => true)
}

///|
/// The release's state, listing only the targets `keep` accepts.
fn Model::targets_list(
  self : Model,
  locale : @i18n.Locale,
  keep : (Target) -> Bool,
) -> @html.Html {
  match self {
    Idle | Loading =>
      @html.p(
        class="downloads-status",
        attrs=@html.Attrs::build().role("status"),
        text(locale, Checking),
      )
    Unavailable =>
      @html.div([
        @html.p(class="downloads-status", text(locale, NotPublished)),
        release_link(FallbackReleasesUrl, text(locale, GitHubReleases)),
      ])
    Ready(version~, page_url~, targets~) => {
      let targets = targets.filter(keep)
      @html.div([
        if targets.is_empty() {
          @html.p(class="downloads-status", text(locale, NoTargets))
        } else {
          @html.ul(
            class="downloads-list",
            targets.map(target => {
              @html.li(
                @html.a(class="downloads-row", href=target.url, escape=true, [
                  @html.span(class="downloads-platform", [
                    @icons.icon(os_icon(target.os)),
                    @html.text(target.label),
                  ]),
                  @html.span(class="downloads-action", [
                    @html.text(text(locale, DownloadVersion(version))),
                    @icons.icon(@icons.icon_arrow_down),
                  ]),
                ]),
              )
            }),
          )
        },
        release_link(page_url, text(locale, GitHubReleases)),
      ])
    }
  }
}

///|
/// Mounted once at a stable position; `open` shows it modally, and the
/// browser owns Escape, outside-click dismissal and focus restoration.
pub fn Model::dialog(self : Model, locale : @i18n.Locale) -> @html.Html {
  @rui.dialog(
    id=DialogId,
    class="dialog-size-small",
    attrs=@html.Attrs::build().aria_labelledby(DialogId + "-title"),
    [
      @rui.dialog_header([
        @rui.dialog_title(
          id=DialogId + "-title",
          @sidebar_messages.text(locale, DownloadApps),
        ),
      ]),
      self.list(locale),
    ],
  )
}

///|
/// The steps that add a computer as a device, from its installer to the
/// setting that lists it here. Mounted and shown like `dialog`.
pub fn Model::add_device_dialog(
  self : Model,
  locale : @i18n.Locale,
) -> @html.Html {
  @rui.dialog(
    id=AddDeviceDialogId,
    class="dialog-size-small",
    attrs=@html.Attrs::build().aria_labelledby(AddDeviceDialogId + "-title"),
    [
      @rui.dialog_header([
        @rui.dialog_title(
          id=AddDeviceDialogId + "-title",
          @sidebar_messages.text(locale, AddDevice),
        ),
      ]),
      // Its numbers are drawn in CSS; WebKit drops the list role without them.
      @html.ol(
        class="add-device-steps",
        attrs=@html.Attrs::build().role("list"),
        [
          @html.li([
            @html.p(text(locale, InstallStep)),
            self.targets_list(locale, target => target.os.hosts_device()),
          ]),
          @html.li(@html.p(text(locale, SignInStep))),
          @html.li(@html.p(text(locale, RemoteControlStep))),
          @html.li(@html.p(text(locale, ListedWhileRunning))),
        ],
      ),
    ],
  )
}

///|
fn release_link(url : String, label : String) -> @html.Html {
  @html.p(
    class="downloads-note",
    @html.a(href=url, escape=true, target=Blank, rel="noopener", [
      @html.text(label),
      @icons.icon(@icons.icon_link_external),
    ]),
  )
}

///|
fn os_icon(os : Os) -> () -> @html.Html {
  match os {
    MacOS => @icons.icon_apple
    Windows => @icons.icon_windows
    Linux => @icons.icon_linux
    Android => @icons.icon_android
  }
}
