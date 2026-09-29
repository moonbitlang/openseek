///|
/// Wheel events do not expose a portable touchpad gesture boundary. Require a
/// quiet interval before crossing, and never cross twice within one burst.
priv struct PageGesture {
  mut last : Double?
  mut direction : Bool?
}

///|
fn PageGesture::new() -> PageGesture {
  { last: None, direction: None, }
}

///|
fn PageGesture::wheel(
  self : PageGesture,
  now : Double,
  boundary : Bool,
  forward : Bool,
) -> Bool {
  let fresh = self.last is Some(last) && now - last >= 250
  let cross = fresh && boundary && self.direction == Some(forward)
  self.last = Some(now)
  self.direction = Some(forward)
  cross
}

///|
fn at_page_bottom(element : @dom.Element) -> Bool {
  element.get_scroll_height() -
  element.get_scroll_top() -
  element.get_client_height() <=
  1
}

///|
fn nested_scrollable(
  element : @dom.Element,
  transcript : @dom.Element,
  forward : Bool,
) -> Bool {
  let mut current = Some(element)
  while current is Some(node) && !node.is_same_node(transcript.as_node()) {
    if node.get_scroll_height() > node.get_client_height() + 1 &&
      (if forward { !at_page_bottom(node) } else { node.get_scroll_top() > 1 }) {
      return true
    }
    current = node.get_parent_element()
  }
  false
}

///|
/// Retain just the boundary turn, then restore its screen position. The extra
/// turn lives only in this reading page and is dropped on explicit navigation.
fn Model::cross_page(
  self : Model,
  turns : TurnIndex,
  forward : Bool,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let page = turns.page_rows(self.page).page
  let index = page.index + (if forward { 1 } else { -1 })
  guard index >= 0 && index < page.count else { return (self, @cmd.none) }
  let boundary = if forward { page.end - 1 } else { page.start }
  guard turns.keys.get(boundary) is Some(key) else { return (self, @cmd.none) }
  let offset = @dom.document()
    .get_element_by_id(key.anchor())
    .to_option()
    .bind(bubble => {
      @dom.document()
      .get_element_by_id("transcript")
      .to_option()
      .map(transcript => {
        bubble.get_bounding_client_rect().get_top() -
        transcript.get_bounding_client_rect().get_top()
      })
    })
  (
    { ..self, page: Some(index), overlap: Some(boundary), pinned: false, },
    @cmd.batch([
      measure_page_after_render(),
      @cmd.custom_cmd(
        scheduler => {
          if offset is Some(offset) &&
            @dom.document().get_element_by_id(key.anchor()).to_option()
            is Some(bubble) &&
            @dom.document().get_element_by_id("transcript").to_option()
            is Some(transcript) {
            let next = bubble.get_bounding_client_rect().get_top() -
              transcript.get_bounding_client_rect().get_top()
            transcript.set_scroll_top(
              transcript.get_scroll_top() + next - offset,
            )
            scheduler.add(
              emit(Overview(ActiveChanged(visible_turn(transcript)))),
            )
          }
        },
        kind=@cmd.after_render,
      ),
    ]),
  )
}

///|
fn page_scroll_hint(locale : @i18n.Locale, forward~ : Bool) -> @html.Html {
  let text = match (locale, forward) {
    (English, true) => "Scroll again to continue to newer messages"
    (English, false) => "Scroll again to continue to older messages"
    (SimplifiedChinese, true) => "再次向下滚动，继续阅读后续对话"
    (SimplifiedChinese, false) =>
      "再次向上滚动，继续阅读更早的对话"
    (TraditionalChinese, true) =>
      "再次向下捲動，繼續閱讀後續對話"
    (TraditionalChinese, false) =>
      "再次向上捲動，繼續閱讀更早的對話"
    (Japanese, true) =>
      "もう一度下にスクロールして新しい会話を表示"
    (Japanese, false) =>
      "もう一度上にスクロールして以前の会話を表示"
    (Spanish, true) =>
      "Desplázate de nuevo hacia abajo para ver mensajes posteriores"
    (Spanish, false) =>
      "Desplázate de nuevo hacia arriba para ver mensajes anteriores"
  }
  @html.p(class="transcript-page-hint", text)
}
