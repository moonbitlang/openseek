///|
fn search_label(locale : @i18n.Locale) -> String {
  match locale {
    English => "Search conversations"
    SimplifiedChinese => "搜索对话"
    TraditionalChinese => "搜尋對話"
    Japanese => "チャットを検索"
    Spanish => "Buscar conversaciones"
  }
}

///|
fn clear_label(locale : @i18n.Locale) -> String {
  match locale {
    English => "Clear search"
    SimplifiedChinese => "清除搜索"
    TraditionalChinese => "清除搜尋"
    Japanese => "検索をクリア"
    Spanish => "Borrar búsqueda"
  }
}

///|
pub fn Model::view(
  self : Model,
  locale : @i18n.Locale,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let label = @messages.text(locale, SearchConversations)
  let children : Array[@html.Html] = [
    @icons.icon(@icons.icon_search),
    @html.input(
      id="session-search-input",
      value=self.query,
      placeholder=label,
      on_input=emit.map(query => Changed(query)),
      attrs=@html.Attrs::build()
        .aria_label(search_label(locale))
        .on_keydown(event => {
          if event.is_composing() {
            return @cmd.none
          }
          match event.key() {
            "Escape" => {
              event.prevent_default()
              emit(Clear)
            }
            "ArrowDown" => {
              event.prevent_default()
              emit(Move(1))
            }
            "ArrowUp" => {
              event.prevent_default()
              emit(Move(-1))
            }
            "Enter" => {
              event.prevent_default()
              emit(Pick)
            }
            _ => @cmd.none
          }
        }),
    ),
  ]
  if !self.query.is_empty() {
    let label = clear_label(locale)
    children.push(
      @html.button(
        class="icon-button icon-button-compact sidebar-search-clear",
        type_="button",
        title=label,
        attrs=@html.Attrs::build().aria_label(label),
        on_click=emit(Clear),
        @icons.icon(@icons.icon_close),
      ),
    )
  }
  @html.div(class="sidebar-search", children)
}
