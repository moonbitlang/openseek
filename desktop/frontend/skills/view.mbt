// Everything the Skills page draws. Pure functions of `State` and `Input`,
// so the whole page can be rendered in a test from constant values.

///|
/// One local-library row: name, description, and — for registry installs
/// only — the source tag and the uninstall button. Hand-written skills are
/// listed so the user sees everything the engine advertises, but the app
/// never offers to delete them.
fn installed_row(
  locale? : @i18n.Locale = English,
  state : State,
  skill : InstalledItem,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let info : Array[@html.Html] = [@html.div(class="skill-name", skill.name)]
  if !skill.description.is_blank() {
    info.push(@html.div(class="skill-desc", skill.description))
  }
  info.push(
    @html.div(
      class="skill-meta",
      if skill.source.is_empty() {
        ui(locale, HandWritten)
      } else {
        skill.source
      },
    ),
  )
  let children : Array[@html.Html] = [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(
      class="skill-info skill-summary",
      on_click=emit(PreviewInstalled(skill)),
      info,
    ),
  ]
  if skill.source.is_empty() {
    children.push(
      @html.div(class="skill-actions", [
        @html.span(class="skill-check ok", "✓"),
      ]),
    )
  } else {
    let busy = state.busy.contains(skill.id)
    children.push(
      @html.div(class="skill-actions", [
        @html.button(
          class="button secondary skill-action",
          disabled=busy,
          on_click=emit(Uninstall(skill.id)),
          if busy {
            ui(locale, Removing)
          } else {
            ui(locale, Uninstall)
          },
        ),
      ]),
    )
  }
  @html.div(class="skill-row", children)
}

///|
/// One catalog row. The action button morphs: already installed at this
/// exact version reads as a disabled ui(locale, InstalledLabel) (an older install keeps
/// the button alive as the upgrade path), an install in flight reads as
/// ui(locale, Installing).
fn market_row(
  locale? : @i18n.Locale = English,
  state : State,
  input : Input,
  item : MarketItem,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let source = source_label(item)
  let busy = state.busy.contains(source)
  let installed = input.has_installed(source)
  let info : Array[@html.Html] = [@html.div(class="skill-name", item.name)]
  if !item.description.is_blank() {
    info.push(@html.div(class="skill-desc", item.description))
  }
  let meta = if item.author.is_empty() {
    "v\{item.version}"
  } else {
    "v\{item.version} · \{item.author}"
  }
  info.push(@html.div(class="skill-meta", meta))
  let action = if installed {
    @html.div(class="skill-actions", [
      @html.span(class="skill-check ok", ui(locale, InstalledCheck)),
    ])
  } else {
    @html.div(class="skill-actions", [
      @html.button(
        class="button secondary skill-action",
        disabled=busy,
        on_click=emit(Install(item)),
        if busy {
          ui(locale, Installing)
        } else {
          ui(locale, Install)
        },
      ),
    ])
  }
  let children = [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(
      class="skill-info skill-summary",
      on_click=emit(PreviewMarket(item)),
      info,
    ),
    action,
  ]
  @html.div(class="skill-row", title=item.repository, children)
}

///|
fn detail_page(
  locale? : @i18n.Locale = English,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  match state.preview {
    Closed => list_page(locale~, state, input, emit)
    Loading(target~, ..) =>
      detail_shell(
        locale~,
        target,
        @html.div(class="skills-empty", ui(locale, LoadingDocument)),
        input,
        state,
        emit,
      )
    Ready(target~, content~, ..) =>
      detail_shell(
        locale~,
        target,
        skill_document_view(locale~, content),
        input,
        state,
        emit,
      )
    Failed(target~, message~, ..) =>
      detail_shell(
        locale~,
        target,
        @html.div(class="skills-empty danger", message),
        input,
        state,
        emit,
      )
  }
}

///|
fn skill_document_view(
  locale? : @i18n.Locale = English,
  source : String,
) -> @html.Html {
  let document = parse_skill_document(source)
  let nodes : Array[@html.Html] = []
  if !document.metadata.is_empty() {
    let rows = document.metadata.map(entry => {
      let (key, value) = entry
      @html.tr([@html.th(key), @html.td(value)])
    })
    nodes.push(
      @html.div(class="skill-metadata", [
        @html.div(class="skill-metadata-title", ui(locale, Metadata)),
        @html.div(class="skill-metadata-scroll", [
          @html.table(class="skill-metadata-table", rows),
        ]),
      ]),
    )
  }
  nodes.push(
    @html.div(
      class="skill-preview-markdown msg-content markdown",
      @markdown.markdown_nodes(locale~, document.body),
    ),
  )
  @html.div(nodes)
}

///|
fn detail_shell(
  locale? : @i18n.Locale = English,
  target : PreviewTarget,
  content : @html.Html,
  input : Input,
  state : State,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @html.section(class="skills-page", [
    @html.div(class="skills-page-inner skill-detail-page", [
      @html.button(
        class="button secondary skill-back",
        on_click=emit(BackToList),
        ui(locale, Back),
      ),
      @html.div(class="skill-detail-header", [
        @html.div(class="page-eyebrow", ui(locale, Details)),
        @html.h1(preview_name(target)),
        @html.div(class="skill-detail-meta", preview_meta(locale~, target)),
        detail_action(locale~, target, state, input, emit),
      ]),
      @html.div(class="skill-detail-card", [
        @html.div(class="skill-file-bar", [
          @html.span(class="skill-file-name", "SKILL.md"),
          match state.preview {
            Ready(content~, ..) =>
              @html.button(
                class="button secondary skill-copy-button",
                attrs=@html.Attrs::build().aria_label(ui(locale, CopyDocument)),
                on_click=copy_content(content),
                ui(locale, Copy),
              )
            _ => @html.span(class="skill-file-status", ui(locale, Loading))
          },
        ]),
        content,
      ]),
    ]),
  ])
}

///|
fn preview_name(target : PreviewTarget) -> String {
  match target {
    Market(item) => item.name
    Installed(item) => item.name
  }
}

///|
fn preview_meta(
  locale? : @i18n.Locale = English,
  target : PreviewTarget,
) -> String {
  match target {
    Market(item) =>
      if item.author.is_empty() {
        "v\{item.version}"
      } else {
        "v\{item.version} · \{item.author}"
      }
    Installed(item) =>
      if item.source.is_empty() {
        ui(locale, HandWritten)
      } else {
        item.source
      }
  }
}

///|
fn detail_action(
  locale? : @i18n.Locale = English,
  target : PreviewTarget,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  match target {
    Market(item) => {
      let key = source_label(item)
      let busy = state.busy.contains(key)
      if input.has_installed(key) {
        @html.span(class="skill-check ok", ui(locale, InstalledCheck))
      } else {
        @html.button(
          class="button primary skill-detail-action",
          disabled=busy,
          on_click=emit(Install(item)),
          if busy {
            ui(locale, Installing)
          } else {
            ui(locale, InstallSkill)
          },
        )
      }
    }
    Installed(item) =>
      if item.source.is_empty() {
        @html.span(class="skill-check ok", ui(locale, HandWrittenSkill))
      } else {
        let busy = state.busy.contains(item.id)
        @html.button(
          class="button secondary skill-detail-action",
          disabled=busy,
          on_click=emit(Uninstall(item.id)),
          if busy {
            ui(locale, Removing)
          } else {
            ui(locale, Uninstall)
          },
        )
      }
  }
}

///|
/// Whether a skill row survives the page's search filter: a blank query
/// keeps everything, otherwise any listed field must contain it
/// (case-insensitive).
fn matches(query : String, fields : Array[String]) -> Bool {
  let query = query.trim().to_lower()
  query.is_empty() || fields.any(field => field.to_lower().contains(query))
}

///|
/// The Skills page, shown in the main area in place of the conversation:
/// header, search, the local library, then the mooncakes.io catalog.
fn list_page(
  locale? : @i18n.Locale = English,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let sections : Array[@html.Html] = [
    @html.div(class="skills-header", [
      @html.div(class="page-eyebrow", ui(locale, Library)),
      @html.h1(ui(locale, Skills)),
      @html.div(class="skills-subtitle", ui(locale, Description)),
    ]),
    @html.div(
      class="skills-search",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      [
        icon(icon_search),
        @html.input(
          input_type=@html.InputType::Search,
          value=state.query,
          placeholder=ui(locale, Search),
          on_input=emit.map(value => QueryChanged(value)),
          attrs=@html.Attrs::build().data_set("focus-target", ""),
        ),
      ],
    ),
  ]
  if !state.notice.is_empty() {
    sections.push(@html.div(class="skills-notice danger", state.notice))
  }
  let installed_rows : Array[@html.Html] = []
  for skill in input.installed {
    if matches(state.query, [skill.name, skill.description, skill.source]) {
      installed_rows.push(installed_row(locale~, state, skill, emit))
    }
  }
  if installed_rows.is_empty() {
    installed_rows.push(
      @html.div(
        class="skills-empty",
        if input.installed.is_empty() {
          ui(locale, EmptyInstalled)
        } else {
          ui(locale, NoInstalledMatch)
        },
      ),
    )
  }
  sections.push(
    @settings.group(icon_extensions, ui(locale, InstalledLabel), installed_rows),
  )
  let market_rows : Array[@html.Html] = []
  match state.catalog {
    Idle | Loading(_) =>
      market_rows.push(
        @html.div(class="skills-empty", ui(locale, LoadingCatalog)),
      )
    Failed(message) =>
      market_rows.push(@html.div(class="skills-empty danger", message))
    Ready(items) => {
      for item in items {
        if matches(state.query, [item.name, item.description, item.author]) {
          market_rows.push(market_row(locale~, state, input, item, emit))
        }
      }
      if market_rows.is_empty() {
        market_rows.push(
          @html.div(
            class="skills-empty",
            if items.is_empty() {
              ui(locale, EmptyRegistry)
            } else {
              ui(locale, NoRegistryMatch)
            },
          ),
        )
      }
    }
  }
  let catalog_loading = match state.catalog {
    Loading(channel~) => channel == input.channel
    _ => false
  }
  sections.push(
    @html.div(class="settings-group", [
      @html.div(class="settings-group-head", [
        icon(icon_package),
        @html.h2(ui(locale, Registry)),
        @html.button(
          class="button secondary skills-refresh",
          disabled=catalog_loading,
          on_click=emit(RefreshCatalog),
          if catalog_loading {
            ui(locale, Refreshing)
          } else {
            ui(locale, Refresh)
          },
        ),
      ]),
      @html.div(class="settings-group-card", market_rows),
    ]),
  )
  @html.section(
    class="skills-page",
    attrs=@html.Attrs::build().on_scroll(event => {
      guard event.target().to_element() is Some(element) else {
        return @cmd.none
      }
      emit(SkillsScrolled(element.get_scroll_top()))
    }),
    [@html.div(class="skills-page-inner", sections)],
  )
}

///|
fn page(
  locale? : @i18n.Locale = English,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  match state.preview {
    Closed => list_page(locale~, state, input, emit)
    _ => detail_page(locale~, state, input, emit)
  }
}
