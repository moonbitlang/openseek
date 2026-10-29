// Everything the Skills page draws. Pure functions of `State` and `Input`,
// so the whole page can be rendered in a test from constant values.

///|
/// The list aggregates notices; a detail shows only its skill's operation
/// failures. Library loading errors apply to either view.
fn notice_views(
  state : State,
  input : Input,
  target : PreviewTarget?,
) -> Array[@html.Html] {
  let nodes : Array[@html.Html] = []
  for notice in state.notices {
    let message = match notice {
      LibraryLoadFailed(message) => message
      BuiltinSyncFailed(channel~, error~) => {
        guard channel == input.channel else { continue }
        let identity = (error.registry.module_name, error.registry.package_path)
        if target is Some(target) {
          let belongs = match target {
            Market(item) => item.identity() == identity
            Installed(item) => item.identity() == Some(identity)
          }
          guard belongs else { continue }
        }
        let source = if error.registry.package_path.is_empty() {
          error.registry.module_name
        } else {
          "\{error.registry.module_name}/\{error.registry.package_path}"
        }
        "\{source}: \{error.message}"
      }
      SkillActionFailed(operation~, message~) => {
        guard operation.channel == input.channel else { continue }
        guard target is Some(target) else {
          "\{operation.action.source()}: \{message}"
        }
        let belongs = match operation.identity {
          Registry(identity) =>
            match target {
              Market(item) => item.identity() == identity
              Installed(item) => item.identity() == Some(identity)
            }
          LibraryEntry(id) => target is Installed(item) && item.id == id
        }
        guard belongs else { continue }
        message
      }
    }
    nodes.push(@html.div(class="skills-notice danger", message))
  }
  nodes
}

///|
fn PendingSkillAction::label(self : PendingSkillAction) -> UiMessage {
  match self {
    Installing(..) => Installing
    Uninstalling(..) => Removing
    Updating(..) => Updating
    SettingEnabled(enabled~, ..) => if enabled { Enabled } else { Disabled }
  }
}

///|
/// One local-library row: name, description, and — for registry installs
/// only — the source tag and management menu. Hand-written skills are
/// listed alongside registry installs, including disabled entries, but the
/// app never offers to delete them.
fn installed_row(
  locale~ : @i18n.Locale = English,
  state : State,
  channel : @interop.ChannelId,
  skill : InstalledItem,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let info : Array[@html.Html] = [
    @html.div(class="skill-meta-line", [
      @html.span(
        class="skill-meta",
        if skill.source.is_empty() {
          ui(locale, HandWritten)
        } else {
          skill.source
        },
      ),
    ]),
  ]
  if !skill.description.is_blank() {
    info.push(@html.span(class="skill-desc", skill.description))
  }
  let header : Array[@html.Html] = [
    @html.button(
      class="skill-summary",
      attrs=@html.Attrs::build().aria_label(skill.name),
      [
        @html.span(class="skill-avatar", icon(icon_extensions)),
        @html.span(class="skill-title", [
          @html.span(class="skill-name", skill.name),
          builtin_badge(locale, skill),
        ]),
      ],
    ),
  ]
  header.push(
    installed_actions(locale, state, channel, skill, emit, "skill-action"),
  )
  @html.div(class="skill-row", on_click=emit(PreviewInstalled(skill)), [
    @html.div(class="skill-header", header),
    @html.div(class="skill-info", info),
  ])
}

///|
/// One uninstalled catalog row, with its install action or pending operation.
fn market_row(
  locale~ : @i18n.Locale = English,
  state : State,
  channel : @interop.ChannelId,
  item : MarketItem,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let source = source_label(item)
  let pending = state.pending_action(channel, item.identity())
  let info : Array[@html.Html] = [@html.span(class="skill-meta", source)]
  if !item.description.is_blank() {
    info.push(@html.span(class="skill-desc", item.description))
  }
  let action = @html.div(class="skill-actions", [
    @html.button(
      class="button secondary skill-action",
      disabled=pending is Some(_),
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        emit(Install(item))
      }),
      if pending is Some(action) {
        ui(locale, action.label())
      } else {
        ui(locale, Install)
      },
    ),
  ])
  let header = [
    @html.button(
      class="skill-summary",
      attrs=@html.Attrs::build().aria_label(item.name),
      [
        @html.span(class="skill-avatar", icon(icon_package)),
        @html.span(class="skill-name", item.name),
      ],
    ),
    action,
  ]
  @html.div(
    class="skill-row",
    title=item.repository,
    on_click=emit(PreviewMarket(item)),
    [
      @html.div(class="skill-header", header),
      @html.div(class="skill-info", info),
    ],
  )
}

///|
fn detail_page(
  locale~ : @i18n.Locale = English,
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
  locale~ : @i18n.Locale = English,
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
  locale~ : @i18n.Locale = English,
  target : PreviewTarget,
  content : @html.Html,
  input : Input,
  state : State,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @page_shell.body(class="skills-page skill-detail-page", [
    @html.div(class="skill-detail-header", [
      @html.div(class="page-eyebrow", ui(locale, Details)),
      @html.div(class="skill-header", [
        @html.div(class="skill-title", [
          @html.h2(preview_name(target)),
          if detail_action_target(target, state, input) is Some(Installed(item)) {
            builtin_badge(locale, item)
          } else {
            @html.nothing
          },
        ]),
        detail_action(locale~, target, state, input, emit),
      ]),
      @html.div(class="skill-detail-meta", preview_meta(locale~, target)),
      @html.div(notice_views(state, input, Some(target))),
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
  locale~ : @i18n.Locale = English,
  target : PreviewTarget,
) -> String {
  match target {
    Market(item) => source_label(item)
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
  locale~ : @i18n.Locale = English,
  target : PreviewTarget,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  // The preview target records where the document came from. Resolve actions
  // against the live library instead of treating that snapshot as an install.
  guard detail_action_target(target, state, input) is Some(target) else {
    return @html.span(class="skill-meta", ui(locale, NotInstalled))
  }
  match target {
    Market(item) => {
      let pending = state.pending_action(input.channel, item.identity())
      @html.button(
        class="button primary skill-detail-action",
        disabled=pending is Some(_),
        on_click=emit(Install(item)),
        if pending is Some(action) {
          ui(locale, action.label())
        } else {
          ui(locale, InstallSkill)
        },
      )
    }
    Installed(item) =>
      installed_actions(
        locale,
        state,
        input.channel,
        item,
        emit,
        "skill-detail-action",
      )
  }
}

///|
fn detail_action_target(
  target : PreviewTarget,
  state : State,
  input : Input,
) -> PreviewTarget? {
  match target {
    Market(item) => Some(preview_target_for_market(input.installed, item))
    Installed(item) => {
      for installed in input.installed {
        guard installed.id == item.id else { continue }
        return Some(Installed(installed))
      }
      // Keep the same detail page usable after uninstall, when its version
      // still exists in the catalog. Never send an id from a removed snapshot.
      guard state.catalog is Ready(items) else { return None }
      for market in items {
        guard source_label(market) == item.source else { continue }
        return Some(Market(market))
      }
      None
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
  locale~ : @i18n.Locale = English,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let catalog_loading = match state.catalog {
    Loading(channel~) => channel == input.channel
    _ => false
  }
  let sections : Array[@html.Html] = [
    @html.div(class="skills-header", [
      @html.div(class="skills-heading", [
        @html.div(class="page-eyebrow", ui(locale, Library)),
        @html.button(
          class="button skills-refresh",
          disabled=catalog_loading,
          on_click=emit(RefreshCatalog),
          if catalog_loading {
            ui(locale, Refreshing)
          } else {
            ui(locale, Refresh)
          },
        ),
      ]),
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
  for notice in notice_views(state, input, None) {
    sections.push(notice)
  }
  let installed_rows : Array[@html.Html] = []
  for skill in input.installed {
    guard matches(state.query, [skill.name, skill.description, skill.source]) else {
      continue
    }
    installed_rows.push(
      installed_row(locale~, state, input.channel, skill, emit),
    )
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
      let installed = input.installed_registry_skills()
      let available = items.filter(item => {
        !installed.contains((item.module_name, item.package_path))
      })
      for item in available {
        guard matches(state.query, [
          item.name,
          item.description,
          item.author,
          source_label(item),
        ]) else {
          continue
        }
        market_rows.push(market_row(locale~, state, input.channel, item, emit))
      }
      if market_rows.is_empty() {
        market_rows.push(
          @html.div(
            class="skills-empty",
            if available.is_empty() {
              ui(locale, EmptyRegistry)
            } else {
              ui(locale, NoRegistryMatch)
            },
          ),
        )
      }
    }
  }
  sections.push(
    @html.div(class="settings-group", [
      @html.div(class="settings-group-head", [
        icon(icon_package),
        @html.h2(ui(locale, Registry)),
      ]),
      @html.div(class="settings-group-card", market_rows),
    ]),
  )
  @page_shell.body(
    class="skills-page",
    attrs=@html.Attrs::build().on_scroll(event => {
      guard event.target().to_element() is Some(element) else {
        return @cmd.none
      }
      emit(SkillsScrolled(element.get_scroll_top()))
    }),
    sections,
  )
}

///|
fn page(
  locale~ : @i18n.Locale = English,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  guard state.preview_channel == Some(input.channel) else {
    return list_page(locale~, state, input, emit)
  }
  match state.preview {
    Closed => list_page(locale~, state, input, emit)
    _ => detail_page(locale~, state, input, emit)
  }
}

///|
fn installed_actions(
  locale : @i18n.Locale,
  state : State,
  channel : @interop.ChannelId,
  item : InstalledItem,
  emit : @cmd.Emit[Msg],
  button_class : String,
) -> @html.Html {
  let enabled = item.enabled
  let label = ui(locale, if enabled { Enabled } else { Disabled })
  let identity = item.identity()
  let pending = identity.bind(registry => {
    state.pending_action(channel, registry)
  })
  let enablement_locked = state.pending_enabled(channel, item.id) ||
    pending.map_or(false, action => action.blocks_enablement())
  let buttons : Array[@html.Html] = [
    @settings.switch_control(
      enabled~,
      label="\{item.name}: \{label}",
      title=label,
      disabled=enablement_locked,
      on_click=emit(ToggleEnabled(item.id)),
    ),
  ]
  if identity is Some(_) &&
    (
      !item.builtin ||
      state.update_candidate(item) is Some(_) ||
      pending is Some(_)
    ) {
    let label = pending
      .map(action => ui(locale, action.label()))
      .unwrap_or(ui(locale, ManageSkill))
    buttons.push(
      @html.button(
        class="skill-menu-trigger \{button_class}",
        type_="button",
        title=label,
        disabled=pending is Some(_),
        attrs=@action_menu.button_attrs(installed_menu_target(channel, item)).aria_label(
          label,
        ),
        icon(@icons.icon_more),
      ),
    )
  }
  @html.div(
    class="skill-actions",
    attrs=@html.Attrs::build().on_click(event => {
      event.stop_propagation()
      @cmd.none
    }),
    [
      installed_status(locale, state, channel, item),
      @html.div(class="skill-actions skill-installed-actions", buttons),
    ],
  )
}

///|
fn builtin_badge(locale : @i18n.Locale, item : InstalledItem) -> @html.Html {
  if item.builtin {
    @html.span(class="skill-builtin-badge", ui(locale, Builtin))
  } else {
    @html.nothing
  }
}

///|
fn installed_status(
  locale : @i18n.Locale,
  state : State,
  channel : @interop.ChannelId,
  item : InstalledItem,
) -> @html.Html {
  guard item.identity() is Some(identity) else { return @html.nothing }
  if state.pending_action(channel, identity) is Some(action) {
    return @html.span(
      class="skill-operation",
      attrs=@html.Attrs::build().role("status"),
      ui(locale, action.label()),
    )
  }
  guard state.update_candidate(item) is Some(_) else { return @html.nothing }
  @html.span(class="skill-update-badge", [
    icon(@icons.icon_arrow_up),
    @html.span(ui(locale, UpdateAvailable)),
  ])
}
