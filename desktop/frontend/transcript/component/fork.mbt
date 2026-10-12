///|
priv struct ForkAction {
  through : Int32
  pending : Bool
  disabled : Bool
} derive(Eq)

///|
fn Input::fork_action(
  self : Input,
  item : @transcript.TranscriptItem,
) -> ForkAction? {
  guard self.source is OpenSeek && self.can_fork else { return None }
  item
  .fork_through()
  .map(through => {
    through,
    pending: self.forking == Some(through),
    disabled: self.fork_busy,
  })
}

///|
fn ForkAction::render(
  self : ForkAction,
  locale~ : @i18n.Locale,
  fork : @cmd.Emit[Int32],
) -> @html.Html {
  let label = match locale {
    SimplifiedChinese => "从此处分叉"
    TraditionalChinese => "從此處分叉"
    English => "Fork from here"
    Japanese => "ここから分岐"
    Spanish => "Bifurcar desde aquí"
  }
  let tooltip = if self.disabled {
    match locale {
      SimplifiedChinese => "正在分叉，请稍候"
      TraditionalChinese => "正在分叉，請稍候"
      English => "Forking, please wait"
      Japanese => "分岐を作成中です。しばらくお待ちください"
      Spanish => "Creando bifurcación, espera un momento"
    }
  } else {
    label
  }
  @html.button(
    class="message-copy message-fork",
    type_="button",
    title=tooltip,
    disabled=self.disabled,
    attrs=@html.Attrs::build().aria_label(label),
    on_click=fork(self.through),
    if self.pending {
      @html.span(class="message-fork-spinner", @icons.icon(@icons.icon_loading))
    } else {
      @icons.icon(@icons.icon_worktree)
    },
  )
}
