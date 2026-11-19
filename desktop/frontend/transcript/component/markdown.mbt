///|
const MessageMarkdownClass : String = "msg-content markdown moonbit-viewer-markdown-content"

///|
priv struct TranscriptMarkdown {
  input : @rabbita.Val[@action_menu.ContextInput]
  actions : @action_menu.ContextActions
}

///|
fn TranscriptMarkdown::body(
  self : TranscriptMarkdown,
  input : @rabbita.Val[@markdown.MarkdownInput?],
  open_file : (String) -> @cmd.Cmd,
  id : String,
) -> @rabbita.Val[@html.Html] {
  input.switch_by(
    request => {
      guard request is Some(initial) else {
        return @rabbita.Val::constant(@html.nothing)
      }
      @markdown.markdown_component(
        input.map(value => value.unwrap_or(initial)),
        id,
        open_file~,
        self.input,
        self.actions,
      )
    },
    by=request => if request is Some(_) { "markdown" } else { "empty" },
  )
}

///|
fn message_markdown(
  locale : @i18n.Locale,
  source : String,
  class~ : String = MessageMarkdownClass,
  artifact_view? : (@workspace_file_ref.WorkspaceFileRef) -> @html.Html,
  defer_artifacts~ : Bool = false,
) -> @markdown.MarkdownInput {
  { source, locale, class, defer_artifacts, artifact_view, }
}

///|
fn Block::prose_markdown(
  self : Block,
  locale : @i18n.Locale,
  owner : ArtifactOwner,
  actions : Actions,
) -> @markdown.MarkdownInput? {
  let render_artifact = reference => {
    artifact_file_view(reference, locale, actions.open, owner)
  }
  match self.content {
    Live(prose~, ..) =>
      prose.map(text => message_markdown(locale, text, defer_artifacts=true))
    Item(item={ kind: Assistant(prose~, finished~, ..), .. }, ..) =>
      prose.map(text => {
        message_markdown(
          locale,
          text,
          defer_artifacts=!finished,
          artifact_view?=if finished { Some(render_artifact) } else { None },
        )
      })
    Item(item={ kind: Answer(text), .. }, ..) =>
      Some(message_markdown(locale, text, artifact_view=render_artifact))
    Item(item={ kind: Summary(text), .. }, ..) =>
      Some(
        message_markdown(
          locale,
          text,
          class=MessageMarkdownClass + " summary-card-body",
        ),
      )
    _ => None
  }
}

///|
fn Block::thought_markdown(
  self : Block,
  locale : @i18n.Locale,
) -> @markdown.MarkdownInput? {
  let reasoning = match self.content {
    Live(reasoning~, reasoning_complete=true, ..)
    | Item(item={ kind: Assistant(reasoning~, ..), .. }, ..) => reasoning
    _ => None
  }
  reasoning.map(text => {
    message_markdown(
      locale,
      text,
      class=MessageMarkdownClass + " activity-thinking",
    )
  })
}

///|
fn minimal_component(
  input : @rabbita.Val[(@i18n.Locale, MinimalContent, ArtifactOwner, Bool)],
  actions : Actions,
  menus : TranscriptMarkdown,
  id : String,
) -> @rabbita.Val[@html.Html] {
  let parts = input.map(input => {
    let (locale, content, owner, _) = input
    if content is Messages(parts, active_group~) {
      @vector.from_array(
        parts.map(part => {
          (
            part.identity,
            (locale, part.content, owner, active_group == Some(part.identity)),
          )
        }),
      )
    } else {
      @vector.Vector::new()
    }
  })
  let group = parts
    .assoc((key, part) => {
      minimal_component(part, actions, menus, "transcript-link-" + @uuid.mint()).map(html => {
          (key, html)
        },
      )
    })
    .map(parts => {
      @html.div(
        class="minimal-messages minimal-rows",
        Map::from_array(parts.to_array()),
      )
    })
  let body = menus.body(
    input.map(input => {
      let (locale, content, owner, _) = input
      match content {
        Prose(text~, finished~, live~, ..) =>
          Some(
            message_markdown(
              locale,
              text,
              defer_artifacts=!finished || live,
              artifact_view?=if finished && !live {
                Some(reference => {
                  artifact_file_view(reference, locale, actions.open, owner)
                })
              } else {
                None
              },
            ),
          )
        ContextSummary(text) =>
          Some(
            message_markdown(
              locale,
              text,
              class="minimal-process-body " + MessageMarkdownClass,
            ),
          )
        _ => None
      }
    }),
    path => (actions.open)(path),
    id,
  )
  input.map3(group, body, (input, group, body) => {
    let (locale, content, _, active) = input
    match content {
      Messages(_) => group
      _ => content.render(locale~, actions, body, active~)
    }
  })
}
