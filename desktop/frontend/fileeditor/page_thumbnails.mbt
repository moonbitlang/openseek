///|
const OfficePagesId = "openseek-office-pages"

///|
const OfficePageListId = "openseek-office-page-list"

///|
fn office_pages_view(
  locale~ : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let pages = if ctx.active_history_diff is None &&
    ctx.active_file is Some(path) {
    match state.docs.get(path) {
      Some({ state: TabOffice(document~, ..), .. }) if document.kind == Word =>
        Some(document.item_count)
      Some({ state: TabPdf(document~, ..), .. }) if document.status == PdfReady =>
        document.pages
      _ => None
    }
  } else {
    None
  }
  @html.div(
    id=OfficePagesId,
    class=if state.office_pages_open && pages is Some(_) {
      "office-page-rail"
    } else {
      "office-page-rail hidden"
    },
    attrs=@html.Attrs::build()
      .role("navigation")
      .aria_label(ui(locale, OfficePages)),
    [
      @html.div(class="office-page-heading", [
        @html.span(
          class="office-page-count",
          ui(locale, OfficePageCount).replace(
            old="{count}",
            new=pages.map(value => value.to_string()).unwrap_or("…"),
          ),
        ),
        @html.button(
          type_="button",
          class="office-viewer-control",
          title=ui(locale, OfficeClosePages),
          attrs=@html.Attrs::build().aria_label(ui(locale, OfficeClosePages)),
          on_click=dispatch(OfficePagesToggled),
          @icons.icon(@icons.icon_layout_sidebar_left),
        ),
      ]),
      @office_viewer.render_page_thumbnails(
        OfficePageListId,
        page_label=ui(locale, OfficePageLabel),
        unavailable_label=ui(locale, OfficePageUnavailable),
      ),
    ],
  )
}

///|
fn office_pages_command(
  state : State,
  config : @office_viewer.SurfaceConfig,
) -> @cmd.Cmd {
  @cmd.batch([
    @office_viewer.page_thumbnails_command(
      config,
      if config.kind == Some(PowerPoint) {
        OfficeSlideListId
      } else {
        OfficePageListId
      },
      enabled=config.kind == Some(PowerPoint) || state.office_pages_open,
      // Root-absolute: the page route never moves the shared resources.
      runtime_url="/assets/page-thumbnails.js",
    ),
    @cmd.custom_cmd(
      _ => observe_office_page_layout(OfficePagesId),
      kind=@cmd.after_render,
    ),
  ])
}

///|
fn refresh_office_pages(state : State, ctx : Ctx) -> @cmd.Cmd {
  guard ctx.active_history_diff is None && ctx.active_file is Some(path) else {
    return dispose_office_pages()
  }
  match state.docs.get(path) {
    Some({ state: TabOffice(document~, ..), .. }) =>
      office_pages_command(state, office_surface_config(state, path, document))
    Some({ state: TabPdf(document~, ..), .. }) if document.status == PdfReady =>
      office_pages_command(state, pdf_surface_config(state, path))
    _ => dispose_office_pages()
  }
}

///|
fn dispose_office_pages() -> @cmd.Cmd {
  @cmd.batch([
    @office_viewer.dispose_page_thumbnails_command(OfficeSurfaceId),
    @cmd.custom_cmd(
      _ => dispose_office_page_layout(OfficePagesId),
      kind=@cmd.after_render,
    ),
  ])
}

///|
// Only the embedding panel's responsive layout belongs to OpenSeek.
extern "js" fn observe_office_page_layout(rail_id : String) =
  #| id => {
  #|   const rail = document.getElementById(id), slot = rail?.parentElement;
  #|   if (!slot || rail.__openSeekPageLayout) return;
  #|   const update = () => { rail.dataset.overlay = String(slot.clientWidth < 560); };
  #|   const observer = new ResizeObserver(update);
  #|   observer.observe(slot);
  #|   rail.__openSeekPageLayout = observer;
  #|   update();
  #| }

///|
extern "js" fn dispose_office_page_layout(rail_id : String) =
  #| id => {
  #|   const rail = document.getElementById(id);
  #|   rail?.__openSeekPageLayout?.disconnect();
  #|   if (rail) delete rail.__openSeekPageLayout;
  #| }
