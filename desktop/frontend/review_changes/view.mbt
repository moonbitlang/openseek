///|
/// Shared selected-change presentation. A missing remove action renders the
/// immutable snapshot in a sent message; each owner keeps its own UI state.
pub(all) struct Control {
  id : String
  open : Bool
  collapsed : Array[String]
  toggle : @cmd.Cmd
  dismiss : @cmd.Cmd
  toggle_file : @cmd.Emit[String]
  open_review : @cmd.Emit[@mention_context.ReviewChanges]
  remove : @cmd.Emit[Array[@mention_context.ReviewChanges]]?
}

///|
fn changes_file_key(changes : @mention_context.ReviewChanges) -> String {
  changes.source.workspace + "/" + changes.source.file
}

///|
fn changes_label(
  locale : @i18n.Locale,
  changes : Array[@mention_context.ReviewChanges],
) -> String {
  let files : Array[String] = []
  for selection in changes {
    let key = changes_file_key(selection)
    if !files.contains(key) {
      files.push(key)
    }
  }
  match locale {
    SimplifiedChinese => return "更改 · \{files.length()} 个文件"
    Japanese => return "変更 · \{files.length()} ファイル"
    English => ()
  }
  "Changes · \{files.length()} \{if files.length() == 1 { "file" } else { "files" }}"
}

///|
pub fn Control::view(
  locale? : @i18n.Locale = English,
  self : Control,
  changes : Array[@mention_context.ReviewChanges],
) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.div(class="mention-chip changes-chip", [
      @html.button(
        class="mention-jump",
        type_="button",
        title=ReviewSelected.text(locale),
        attrs=@html.Attrs::build()
          .aria_expanded(if self.open { "true" } else { "false" })
          .aria_haspopup("dialog")
          .aria_controls(self.id + "-popup"),
        on_click=self.toggle,
        [
          @icons.icon(@icons.icon_diff_multiple),
          @html.span(class="mention-label", changes_label(locale, changes)),
          @html.span(
            class="changes-chevron",
            @icons.icon(@icons.icon_chevron_down),
          ),
        ],
      ),
      match self.remove {
        Some(remove) =>
          @html.button(
            class="mention-remove",
            type_="button",
            title=RemoveSelected.text(locale),
            on_click=remove(changes),
            @icons.icon(@icons.icon_close),
          )
        None => @html.nothing
      },
    ]),
  ]
  if self.open {
    children.push(self.popup(locale~, changes))
  }
  @html.div(
    id=self.id,
    class=if self.remove is Some(_) {
      "changes-context composer-changes"
    } else {
      "changes-context message-changes"
    },
    children,
  )
}

///|
fn change_line_ranges(lines : Array[@mention_context.ChangeLine]) -> String {
  let ranges : Array[String] = []
  let mut index = 0
  while index < lines.length() {
    let first = lines[index].number
    let mut last = first
    index += 1
    while index < lines.length() && lines[index].number == last + 1 {
      last = lines[index].number
      index += 1
    }
    ranges.push(if first == last { "L\{first}" } else { "L\{first}–\{last}" })
  }
  ranges.join(", ")
}

///|
fn excerpt_label(
  locale : @i18n.Locale,
  excerpt : @mention_context.ChangeExcerpt,
) -> String {
  let parts : Array[String] = []
  if !excerpt.original.is_empty() {
    parts.push(OldLines.text(locale) + change_line_ranges(excerpt.original))
  }
  if !excerpt.modified.is_empty() {
    parts.push(NewLines.text(locale) + change_line_ranges(excerpt.modified))
  }
  parts.join(" → ")
}

///|
fn excerpt_preview(
  excerpt : @mention_context.ChangeExcerpt,
  file : String,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  for
    (lines, sign, style) in [
      (excerpt.original, "−", "removed"),
      (excerpt.modified, "+", "added"),
    ] {
    let mut previous : Int? = None
    let source = lines.map(line => line.text).join("\n")
    let highlighted = if file.has_suffix(".mbt") || file.has_suffix(".mbti") {
      @syntax_html.moonbit_source_lines(source)
    } else {
      []
    }
    for index, line in lines {
      if previous is Some(number) && line.number != number + 1 {
        rows.push(@html.div(class="changes-preview-gap", "…"))
      }
      rows.push(
        @html.div(class="changes-preview-line \{style}", [
          @html.span(class="changes-line-number", line.number.to_string()),
          @html.span(class="changes-line-sign", sign),
          @html.code(
            class="changes-line-code",
            highlighted.get(index).unwrap_or(@html.text(line.text)),
          ),
        ]),
      )
      previous = Some(line.number)
    }
  }
  @html.div(class="changes-preview", rows)
}

///|
fn Control::popup(
  locale? : @i18n.Locale = English,
  self : Control,
  changes : Array[@mention_context.ReviewChanges],
) -> @html.Html {
  let files : Array[@html.Html] = []
  let keys : Array[String] = []
  for selection in changes {
    let key = changes_file_key(selection)
    if keys.contains(key) {
      continue
    }
    keys.push(key)
    let selections = changes.filter(other => changes_file_key(other) == key)
    let collapsed = self.collapsed.contains(key)
    let path = selection.source.file
    let (directory, name) = match path.rev_split_once("/") {
      Some((directory, name)) => (Some(directory.to_owned()), name.to_owned())
      None => (None, path)
    }
    let mut added = 0
    let mut removed = 0
    let cards : Array[@html.Html] = []
    for selection in selections {
      for excerpt in selection.excerpts {
        added += excerpt.modified.length()
        removed += excerpt.original.length()
        if !collapsed {
          let single = { ..selection, excerpts: [excerpt], }
          cards.push(
            @html.div(class="changes-excerpt", [
              @html.div(class="changes-excerpt-header", [
                @html.span(
                  class="changes-range",
                  excerpt_label(locale, excerpt),
                ),
                @html.button(
                  class="changes-open",
                  type_="button",
                  title=OpenReview.text(locale),
                  attrs=@html.Attrs::build().aria_label(OpenReview.text(locale)),
                  on_click=(self.open_review)(single),
                  OpenReviewLink.text(locale),
                ),
                match self.remove {
                  Some(remove) =>
                    @html.button(
                      class="changes-remove",
                      type_="button",
                      title=RemoveChange.text(locale),
                      on_click=remove([single]),
                      @icons.icon(@icons.icon_close),
                    )
                  None => @html.nothing
                },
              ]),
              excerpt_preview(excerpt, path),
            ]),
          )
        }
      }
    }
    files.push(
      @html.div(
        class="changes-file",
        [
          @html.button(
            class="changes-file-header",
            type_="button",
            title=path,
            attrs=@html.Attrs::build().aria_expanded(
              if collapsed {
                "false"
              } else {
                "true"
              },
            ),
            on_click=(self.toggle_file)(key),
            [
              @html.span(
                class="changes-chevron",
                @icons.icon(@icons.icon_chevron_down),
              ),
              @html.span(class="changes-file-path", [
                @html.strong(name),
                match directory {
                  Some(directory) =>
                    @html.span(class="changes-directory", directory)
                  None => @html.nothing
                },
              ]),
              @html.span(class="changes-count added", "+\{added}"),
              @html.span(class="changes-count removed", "−\{removed}"),
            ],
          ),
          ..cards,
        ],
      ),
    )
  }
  @html.div(
    class=if self.remove is Some(_) {
      "changes-popup composer-changes-popup"
    } else {
      "changes-popup message-changes-popup"
    },
    attrs={
      let attrs = @html.Attrs::build()
        .id(self.id + "-popup")
        .role("dialog")
        .aria_label(SelectedChanges.text(locale))
      if self.remove is Some(_) {
        attrs
      } else {
        attrs.popover("manual")
      }
    },
    [
      @html.div(class="changes-popup-header", [
        @html.div(class="changes-popup-heading", [
          @icons.icon(@icons.icon_diff_multiple),
          @html.strong(changes_label(locale, changes)),
        ]),
        @html.button(
          class="changes-close",
          type_="button",
          title=CloseSelected.text(locale),
          on_click=self.dismiss,
          @icons.icon(@icons.icon_close),
        ),
      ]),
      @html.div(
        class="changes-popup-subtitle",
        if self.remove is Some(_) {
          NextMessage.text(locale)
        } else {
          ThisMessage.text(locale)
        },
      ),
      @html.div(class="changes-popup-files", files),
      @html.div(class="changes-popup-footer", [
        @html.span(SelectedOnly.text(locale)),
        match self.remove {
          Some(remove) =>
            @html.button(
              type_="button",
              on_click=remove(changes),
              RemoveGroup.text(locale),
            )
          None => @html.nothing
        },
      ]),
    ],
  )
}
