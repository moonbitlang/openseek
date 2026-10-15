///|
priv enum Label {
  Search
  Hint
  Close
  Searching
  NoResults
  Archived
  More
  Partial
  Untitled
}

///|
fn text(locale : @i18n.Locale, label : Label) -> String {
  match locale {
    SimplifiedChinese =>
      match label {
        Search => "搜索对话"
        Hint => "搜索会话标题"
        Close => "关闭搜索"
        Searching => "正在搜索…"
        NoResults => "未找到匹配的对话"
        Archived => "显示已归档会话"
        More => "显示最近 100 个结果，请缩小搜索范围"
        Partial => "部分会话无法搜索"
        Untitled => "未命名对话"
      }
    TraditionalChinese =>
      match label {
        Search => "搜尋對話"
        Hint => "搜尋對話標題"
        Close => "關閉搜尋"
        Searching => "正在搜尋…"
        NoResults => "找不到符合的對話"
        Archived => "顯示已封存對話"
        More => "顯示最近 100 個結果，請縮小搜尋範圍"
        Partial => "部分對話無法搜尋"
        Untitled => "未命名對話"
      }
    Japanese =>
      match label {
        Search => "チャットを検索"
        Hint => "チャットのタイトルを検索"
        Close => "検索を閉じる"
        Searching => "検索中…"
        NoResults => "一致するチャットはありません"
        Archived => "アーカイブ済みチャットを表示"
        More =>
          "最新の100件を表示しています。検索を絞り込んでください"
        Partial => "一部のチャットを検索できませんでした"
        Untitled => "無題のチャット"
      }
    Spanish =>
      match label {
        Search => "Buscar conversaciones"
        Hint => "Buscar títulos de conversaciones"
        Close => "Cerrar búsqueda"
        Searching => "Buscando…"
        NoResults => "No se encontraron conversaciones"
        Archived => "Mostrar conversaciones archivadas"
        More =>
          "Se muestran los 100 resultados más recientes; acota la búsqueda"
        Partial => "No se pudieron buscar algunas conversaciones"
        Untitled => "Conversación sin título"
      }
    English =>
      match label {
        Search => "Search conversations"
        Hint => "Search conversation titles"
        Close => "Close search"
        Searching => "Searching…"
        NoResults => "No matching conversations"
        Archived => "Show archived conversations"
        More => "Showing the 100 most recent results. Narrow your search."
        Partial => "Some conversations could not be searched"
        Untitled => "Untitled conversation"
      }
  }
}

///|
fn highlighted(value : String, query : String) -> @html.Html {
  let query = query.trim().to_owned().to_lower()
  let children : Array[@html.Html] = []
  let mut rest = value
  while !query.is_empty() {
    guard rest.to_lower().find(query) is Some(offset) else { break }
    children.push(@html.span(rest.view(end_offset=offset).to_owned()))
    children.push(
      @html.strong(
        rest
        .view(start_offset=offset, end_offset=offset + query.length())
        .to_owned(),
      ),
    )
    rest = rest.view(start_offset=offset + query.length()).to_owned()
  }
  children.push(@html.span(rest))
  @html.span(children)
}

///|
pub fn Model::view(
  self : Model,
  locale : @i18n.Locale,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let children : Array[@html.Html] = []
  if self.search is Some(search) {
    children.push(
      @html.div(class="quick-open-input-wrap session-search-header", [
        @icons.icon(@icons.icon_search),
        @html.div(
          class="session-search-input-wrap",
          attrs=@html.Attrs::build().on_keydown(event => {
            if event.is_composing() {
              return @cmd.none
            }
            match event.key() {
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
                emit(Pick(search.selected))
              }
              _ => @cmd.none
            }
          }),
          @html.input(
            id="session-search-input",
            value=search.query,
            autofocus=true,
            placeholder=text(locale, Hint),
            on_input=emit.map(value => Changed(value)),
            attrs=@html.Attrs::build()
              .aria_label(text(locale, Hint))
              .data_set("focus-owner", ""),
          ),
        ),
        @html.button(
          class="export-dialog-close",
          title=text(locale, Close),
          on_click=emit(Close),
          attrs=@html.Attrs::build().aria_label(text(locale, Close)),
          @icons.icon(@icons.icon_close),
        ),
      ]),
    )
    let results : Array[@html.Html] = []
    match search.phase {
      Empty =>
        results.push(@html.p(class="quick-open-empty", text(locale, Hint)))
      Waiting | Loading =>
        results.push(@html.p(class="quick-open-empty", text(locale, Searching)))
      Failed(error) =>
        results.push(@html.p(class="quick-open-empty error", error))
      Ready(reply) => {
        if reply.hits.is_empty() {
          results.push(
            @html.p(class="quick-open-empty", text(locale, NoResults)),
          )
        }
        for index, hit in reply.hits {
          results.push(
            @html.button(
              id="session-search-result-\{index}",
              class=if index == search.selected {
                "quick-open-row session-search-result selected"
              } else {
                "quick-open-row session-search-result"
              },
              title=hit.workspace,
              on_click=emit(Pick(index)),
              [
                @html.span(
                  class="quick-open-kind",
                  @icons.icon(
                    if hit.archived {
                      @icons.icon_archive
                    } else {
                      @icons.icon_comment_discussion
                    },
                  ),
                ),
                @html.span(class="quick-open-row-text", [
                  @html.span(
                    class="quick-open-name session-search-result-title",
                    highlighted(
                      if hit.title.is_blank() {
                        text(locale, Untitled)
                      } else {
                        hit.title
                      },
                      search.query,
                    ),
                  ),
                  @html.span(
                    class="quick-open-detail session-search-workspace",
                    hit.workspace
                    .split("/")
                    .last()
                    .map(part => part.to_owned())
                    .unwrap_or(hit.workspace),
                  ),
                ]),
              ],
            ),
          )
        }
        if reply.has_more {
          results.push(@html.p(class="quick-open-empty", text(locale, More)))
        }
        if !reply.errors.is_empty() {
          results.push(
            @html.details(class="session-search-errors", [
              @html.summary(text(locale, Partial)),
              @html.p(reply.errors.join("\n")),
            ]),
          )
        }
      }
    }
    children.push(
      @html.div(
        class="quick-open-list session-search-results",
        attrs=@html.Attrs::build().aria_live("polite"),
        results,
      ),
    )
    children.push(
      @html.div(
        class="session-search-footer",
        @html.button(
          class=if search.include_archived {
            "quick-open-row session-search-archive selected"
          } else {
            "quick-open-row session-search-archive"
          },
          on_click=emit(ToggleArchived),
          attrs=@html.Attrs::build().aria_pressed(
            search.include_archived.to_string(),
          ),
          [@icons.icon(@icons.icon_archive), @html.span(text(locale, Archived))],
        ),
      ),
    )
  }
  @html.dialog(
    id=DialogId,
    class="quick-open-dialog session-search-dialog",
    on_cancel=emit(Close),
    attrs=@html.Attrs::build().aria_label(text(locale, Search)),
    children,
  )
}
