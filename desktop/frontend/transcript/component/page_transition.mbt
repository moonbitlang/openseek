///|
/// The rail can move before the expensive transcript subtree is replaced.
/// A generation prevents an earlier click from finishing a newer request.
priv struct PageNavigation {
  page : Int
  generation : Int
  rendering : Bool
} derive(Eq)

///|
fn Model::navigation_page(
  self : Model,
  turns : TurnIndex,
) -> @transcript_overview.Page {
  turns.page_rows(
    match self.navigation {
      Some(navigation) => Some(navigation.page)
      None => self.page
    },
  ).page
}

///|
fn Model::mount_page(
  self : Model,
  turns : TurnIndex,
  generation : Int,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  guard self.navigation is Some(navigation) &&
    navigation.generation == generation &&
    !navigation.rendering else {
    return (self, @cmd.none)
  }
  let page = turns.page_rows(Some(navigation.page)).page
  (
    {
      ..self,
      page: Some(page.index),
      overlap: None,
      navigation: Some({ ..navigation, rendering: true, }),
    },
    @cmd.batch([
      measure_page_after_render(),
      restore_scroll_after_render(0),
      after_page_paint(emit(PageReady(generation))),
    ]),
  )
}

///|
/// Yield an actual paint before preparing the page, and another after its
/// layout. The optional delay belongs to the rail animation, not the loader.
fn after_page_paint(command : @cmd.Cmd, animate? : Bool = false) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      @dom.window().request_animation_frame(_ => {
        @dom.window().request_animation_frame(_ => {
          let reduced = @dom.window()
            .match_media("(prefers-reduced-motion: reduce)")
            .get_matches()
          scheduler.add(
            if animate && !reduced {
              @cmd.delay(command, 180)
            } else {
              command
            },
          )
        })
        |> ignore
      })
      |> ignore
    },
    kind=@cmd.after_render,
  )
}

///|
/// Shared by initial session loading and transcript page navigation.
pub fn conversation_loading_view(
  locale? : @i18n.Locale = English,
) -> @html.Html {
  let label = match locale {
    English => "Loading conversation…"
    Spanish => "Cargando conversación…"
    SimplifiedChinese => "正在加载对话…"
    TraditionalChinese => "正在載入對話…"
    Japanese => "チャットを読み込み中…"
  }
  @html.div(
    class="conversation-load-state",
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    label,
  )
}
