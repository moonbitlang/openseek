///|
/// The rail can move before the expensive transcript subtree is replaced.
/// A generation prevents an earlier click from finishing a newer request.
priv struct PageNavigation {
  page : Int
  anchor : @transcript_overview.TurnKey?
  generation : Int
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
    navigation.generation == generation else {
    return (self, @cmd.none)
  }
  let page = turns.page_rows(Some(navigation.page)).page
  let (next, position) = self.show_page(
    page.index,
    emit,
    anchor?=navigation.anchor,
  )
  (next, @cmd.batch([position, after_page_paint(emit(PageReady(generation)))]))
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

///|
/// Use layout coordinates: getBoundingClientRect includes the message's
/// entrance transform, which is still animating while a page is prepared.
fn turn_layout_top(bubble : @dom.Element, transcript : @dom.Element) -> Double? {
  let mut current = Some(bubble)
  let mut top = 0.0
  while current is Some(node) {
    if node.is_same_node(transcript.as_node()) {
      return Some(top)
    }
    guard node.to_html_element() is Some(element) else { return None }
    top += element.get_offset_top()
    current = element.get_offset_parent()
  }
  None
}

///|
/// Explicit navigation unpins even at an old page's bottom. The overview
/// stays complete; only the selected page's message branches are mounted.
fn Model::select_page(
  self : Model,
  turns : TurnIndex,
  index : Int,
  emit : @cmd.Emit[Msg],
  anchor? : @transcript_overview.TurnKey,
) -> (Model, @cmd.Cmd) {
  let rows = turns.page_rows(Some(index))
  guard anchor is Some(_) ||
    rows.page.index != self.navigation_page(turns).index else {
    return (self, @cmd.none)
  }
  let overview : @transcript_overview.State = {
    hover: None,
    active: match anchor {
      Some(key) => Some(key)
      None => turns.keys.get(rows.page.start)
    },
  }
  if self.navigation is None &&
    rows.page.index == turns.page_rows(self.page).page.index {
    return { ..self, overview, }.show_page(rows.page.index, emit, anchor?)
  }
  let generation = self.navigation_generation + 1
  (
    {
      ..self,
      navigation: Some({ page: rows.page.index, anchor, generation, }),
      navigation_generation: generation,
      pinned: false,
      overview,
    },
    @cmd.batch([
      // A clicked tick is already visible; keep it under the pointer.
      if anchor is None {
        reveal_active_overview_tick()
      } else {
        @cmd.none
      },
      after_page_paint(emit(MountPage(generation)), animate=true),
    ]),
  )
}

///|
/// All navigation paths commit page bounds and restore position here. A
/// wheel crossing supplies the retained turn's offset; clicks align at 10px.
fn Model::show_page(
  self : Model,
  page : Int,
  emit : @cmd.Emit[Msg],
  anchor? : @transcript_overview.TurnKey,
  offset? : Double = 10,
  overlap? : Int,
) -> (Model, @cmd.Cmd) {
  (
    { ..self, page: Some(page), overlap, pinned: false, },
    @cmd.batch([
      measure_page_after_render(),
      match anchor {
        Some(key) => scroll_turn_into_view(emit, key, offset~)
        None => restore_scroll_after_render(0)
      },
    ]),
  )
}
