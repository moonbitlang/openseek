///|
fn scroll_results_to_start() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id("skills-results").to_option()
        is Some(results) {
        results.set_scroll_top(0.0)
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn skill_card(
  name : String,
  description : String,
  source : String,
  open : @cmd.Cmd,
  action : @html.Html,
  badge~ : @html.Html = @html.nothing,
  menu~ : @html.Html = @html.nothing,
) -> @html.Html {
  @html.div(class="skill-row", [
    @html.div(class="skill-header", [
      @html.button(
        class="skill-summary",
        title=name,
        attrs=@html.Attrs::build()
          .aria_label(name)
          .on_click(event => {
            // The native detail dialog restores this opener even on browsers that
            // do not focus buttons on pointer activation.
            if event.current_target().to_option() is Some(target) &&
              target.to_html_element() is Some(button) {
              button.focus()
            }
            open
          }),
        [@html.span(class="skill-name", name), badge],
      ),
      menu,
    ]),
    @html.div(class="skill-desc", description),
    @html.div(class="skill-footer", [
      @html.span(class="skill-meta", title=source, source),
      action,
    ]),
  ])
}

///|
fn market_card(
  locale : @i18n.Locale,
  state : State,
  input : Input,
  item : MarketItem,
  installed : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let pending = state.pending_action(input.library, item.identity())
  let action = if pending is Some(action) {
    @html.span(
      class="skill-operation",
      attrs=@html.Attrs::build().role("status"),
      ui(locale, action.label()),
    )
  } else if installed {
    @html.span(class="skill-operation", ui(locale, InstalledLabel))
  } else {
    @html.button(
      class="button secondary skill-action",
      on_click=emit(Install(item)),
      ui(locale, Install),
    )
  }
  skill_card(
    item.name,
    item.description,
    if item.author.is_blank() {
      item.module_name
    } else {
      item.author
    },
    emit(PreviewMarket(item)),
    action,
  )
}

///|
fn filter_control(
  locale : @i18n.Locale,
  state : State,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let choices : Array[(StatusFilter, String, UiMessage)] = [
    (AllSkills, "all", AllStatuses),
    (EnabledSkills, "enabled", Enabled),
    (DisabledSkills, "disabled", Disabled),
    (WithUpdates, "updates", UpdateAvailable),
  ]
  let options = choices.map(choice => {
    @select_control.ViewOption(value=choice.1, label=ui(locale, choice.2))
  })
  let selected = choices
    .iter()
    .find_first(choice => choice.0 == state.filter)
    .unwrap().1
  let label = ui(locale, Status)
  @select_control.Control(
    id="skills-status-filter",
    groups=[{ label, options, }],
    selected~,
    disabled=false,
    open=state.filter_open,
    toggle=emit(SetFilterOpen(!state.filter_open)),
    dismiss=emit(SetFilterOpen(false)),
    title=label,
    aria_label=label,
    presentation=Setting,
    change=@cmd.Emit(value => {
      for choice in choices {
        if choice.1 == value {
          return emit(FilterBy(choice.0))
        }
      }
      @cmd.none
    }),
  ).render()
}

///|
fn list_page(
  locale~ : @i18n.Locale,
  state : State,
  input : Input,
  emit : @cmd.Emit[Msg],
  menus : Array[(InstalledItem, @html.Html)],
  selector : @html.Html,
) -> @html.Html {
  let discover = state.section is Discover
  let tabs : Array[@html.Html] = []
  let total = input.installed.length()
  let library_failed = state.notices.any(notice => {
    notice is LibraryLoadFailed(_)
  })
  for
    (section, id, label) in [
      (BrowseSection::Discover, "discover", DiscoverLabel),
      (InstalledSkills, "installed", InstalledLabel),
    ] {
    tabs.push(
      @rui.tabs_trigger(
        value=id,
        id="skills-tab-" + id,
        controls="skills-results",
        selected=section == state.section,
        on_value_change=@cmd.Emit(_ => emit(Browse(section))),
        class="skills-tab",
        style=[
          "flex:none;padding:var(--space-3);background:transparent;border:0;font-size:var(--font-size-sm)",
        ],
        [
          @html.span(ui(locale, label)),
          if section is InstalledSkills &&
            input.available() &&
            !state.installed_loading &&
            !(library_failed && total == 0) {
            @html.span(class="skills-tab-count", total.to_string())
          } else {
            @html.nothing
          },
        ],
      ),
    )
  }
  let toolbar = @html.div(class="skills-toolbar", [
    @rui.tabs_list(
      variant=TabsLine,
      aria_label=ui(locale, Library),
      style=["flex-wrap:wrap;gap:var(--space-4);padding:0"],
      tabs,
    ),
    @html.div(
      class="search-field field-surface",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      [
        icon(icon_search),
        @html.input(
          input_type=@html.InputType::Search,
          value=state.query,
          placeholder=ui(locale, Search),
          on_input=emit.map(value => QueryChanged(value)),
          attrs=@html.Attrs::build()
            .id("skills-search")
            .data_set("focus-target", "")
            .aria_label(ui(locale, Search))
            .disabled(!input.available()),
        ),
      ],
    ),
    if !discover {
      filter_control(locale, state, emit)
    } else {
      @html.nothing
    },
  ])
  let cards : Map[String, @html.Html] = Map([])
  let notices = if input.available() {
    notice_views(state, input, None)
  } else {
    []
  }
  let catalog_needed = discover || state.filter is WithUpdates
  let mut count : Int32? = None
  let mut empty : UiMessage? = None
  if !input.available() {
    empty = Some(LibraryUnavailable)
  } else if catalog_needed &&
    !(state.catalog is Ready(library~, ..) && library == input.library) {
    match state.catalog {
      Failed(library~, message~) if library == input.library =>
        notices.push(@html.div(class="skills-empty danger", message))
      _ => empty = Some(LoadingCatalog)
    }
  } else if state.installed_loading {
    empty = Some(Loading)
  } else if discover && state.catalog is Ready(items~, ..) {
    let installed = input.installed_registry_skills()
    for item in items {
      let source = source_label(item)
      guard matches(state.query, [
        item.name,
        item.description,
        item.author,
        source,
      ]) else {
        continue
      }
      cards["\{input.library.key()}:market:\{source}"] = market_card(
        locale,
        state,
        input,
        item,
        installed.contains(item.identity()),
        emit,
      )
    }
    count = Some(cards.length())
    if cards.is_empty() {
      empty = Some(if items.is_empty() { EmptyRegistry } else { NoMatch })
    }
  } else if !(library_failed && total == 0) {
    for (item, menu) in menus {
      let source = match item.registry {
        Some(registry) => registry.module_name
        None => preview_meta(locale~, Installed(item))
      }
      let controls = installed_controls(
        locale,
        state,
        input.library,
        item,
        emit,
        "skill-action",
        menu,
      )
      cards["\{input.library.key()}:installed:\{item.id}"] = skill_card(
        item.name,
        item.description,
        source,
        emit(PreviewInstalled(item)),
        @html.div(class="skill-actions", [controls.status, controls.toggle]),
        badge=builtin_badge(locale, item),
        menu=controls.menu,
      )
    }
    count = Some(cards.length())
    if cards.is_empty() {
      empty = Some(if total == 0 { EmptyInstalled } else { NoMatch })
    }
  }
  let content = [
    @html.div(notices),
    if empty is Some(message) {
      @html.div(class="skills-empty", ui(locale, message))
    } else {
      @html.nothing
    },
    @html.div(class="skills-grid", cards),
  ]
  let catalog_loading = state.catalog is Loading(library~) &&
    library == input.library
  let tab = if discover { "discover" } else { "installed" }
  @rui.tabs_root(
    class="skills-page",
    value=tab,
    style=[
      "display:grid;grid-template-rows:auto auto minmax(0,1fr);gap:var(--space-4)",
    ],
    [
      @html.div(class="skills-context", [
        selector,
        @html.button(
          class="button skills-refresh",
          disabled=catalog_loading || !input.available(),
          on_click=emit(RefreshCatalog),
          ui(locale, if catalog_loading { Refreshing } else { Refresh }),
        ),
      ]),
      toolbar,
      @html.div(class="skills-results-region", [
        @html.div(class="skills-results-meta", [
          if count is Some(n) {
            @html.span(
              attrs=@html.Attrs::build().role("status"),
              ui(locale, Results(n)),
            )
          } else {
            @html.nothing
          },
          if !state.query.is_blank() ||
            (!discover && !(state.filter is AllSkills)) {
            @html.button(
              class="button",
              on_click=emit(ClearFilters),
              ui(locale, Clear),
            )
          } else {
            @html.nothing
          },
        ]),
        @rui.tabs_content(
          id="skills-results",
          value=tab,
          selected=true,
          labelledby="skills-tab-" + tab,
          class="skills-results",
          attrs=@html.Attrs::build().on_scroll(event => {
            if event.current_target().to_option() is Some(target) &&
              target.to_element() is Some(results) {
              let scrolled = results.get_scroll_top() > 0.0
              if scrolled != results.has_attribute("data-scrolled") {
                if scrolled {
                  results.set_attribute("data-scrolled", "")
                } else {
                  results.remove_attribute("data-scrolled")
                }
              }
            }
            @cmd.none
          }),
          content,
        ),
      ]),
    ],
  )
}
