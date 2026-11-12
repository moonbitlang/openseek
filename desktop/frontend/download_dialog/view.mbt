///|
/// Mounted once at a stable position; `open` shows it modally, and the
/// browser owns Escape, outside-click dismissal and focus restoration.
pub fn Model::view(self : Model, locale : @i18n.Locale) -> @html.Html {
  let body = match self.release {
    Loading =>
      @html.p(
        class="download-dialog-status",
        attrs=@html.Attrs::build().role("status"),
        text(locale, Checking),
      )
    Unavailable =>
      @html.div([
        @html.p(class="download-dialog-status", text(locale, NotPublished)),
        release_link(FallbackReleasesUrl, text(locale, BrowseReleases)),
      ])
    Ready(version~, page_url~, targets~) =>
      @html.div([
        if targets.is_empty() {
          @html.p(class="download-dialog-status", text(locale, NoTargets))
        } else {
          @html.ul(
            class="download-dialog-list",
            targets.map(target => {
              @html.li(
                @html.a(
                  class="download-dialog-row",
                  href=target.url,
                  escape=true,
                  [
                    @html.span(class="download-dialog-platform", target.label),
                    @html.span(class="download-dialog-action", [
                      @html.text(text(locale, DownloadVersion(version))),
                      @icons.icon(@icons.icon_arrow_down),
                    ]),
                  ],
                ),
              )
            }),
          )
        },
        release_link(page_url, text(locale, AllReleases)),
      ])
  }
  @rui.dialog(
    id=DialogId,
    class="dialog-size-small",
    attrs=@html.Attrs::build().aria_labelledby(DialogId + "-title"),
    [
      @rui.dialog_header([
        @rui.dialog_title(id=DialogId + "-title", text(locale, Title)),
      ]),
      body,
    ],
  )
}

///|
fn release_link(url : String, label : String) -> @html.Html {
  @html.p(
    class="download-dialog-note",
    @html.a(href=url, escape=true, target=Blank, rel="noopener", [
      @html.text(label),
      @icons.icon(@icons.icon_link_external),
    ]),
  )
}
