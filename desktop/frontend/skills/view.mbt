// Everything the Skills page draws. Pure functions of `State` and `Input`,
// so the whole page can be rendered in a test from constant values.

///|
/// A titled card of rows: an accent-tinted icon and heading above a bordered
/// surface. The Settings page draws its sections the same way, which is what
/// makes the two pages read as siblings.
fn group(
  icon_image : () -> @html.Html,
  title : String,
  rows : Array[@html.Html],
) -> @html.Html {
  @html.div(class="settings-group", [
    @html.div(class="settings-group-head", [icon(icon_image), @html.h2(title)]),
    @html.div(class="settings-group-card", rows),
  ])
}

///|
/// One local-library row: name, description, and — for registry installs
/// only — the source tag and the uninstall button. Hand-written skills are
/// listed so the user sees everything the engine advertises, but the app
/// never offers to delete them.
fn installed_row(
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
        "hand-written"
      } else {
        skill.source
      },
    ),
  )
  let children : Array[@html.Html] = [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(class="skill-info", info),
  ]
  if skill.source.is_empty() {
    children.push(@html.span(class="skill-check ok", "✓"))
  } else {
    let busy = state.busy.contains(skill.id)
    children.push(
      @html.button(
        class="secondary skill-action",
        disabled=busy,
        on_click=emit(Uninstall(skill.id)),
        if busy {
          "Removing…"
        } else {
          "Uninstall"
        },
      ),
    )
  }
  @html.div(class="skill-row", children)
}

///|
/// One catalog row. The action button morphs: already installed at this
/// exact version reads as a disabled "Installed" (an older install keeps
/// the button alive as the upgrade path), an install in flight reads as
/// "Installing…".
fn market_row(
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
    @html.span(class="skill-check ok", "✓ Installed")
  } else {
    @html.button(
      class="secondary skill-action",
      disabled=busy,
      on_click=emit(Install(item)),
      if busy {
        "Installing…"
      } else {
        "Install"
      },
    )
  }
  @html.div(class="skill-row", title=item.repository, [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(class="skill-info", info),
    action,
  ])
}

///|
/// Whether a skill row survives the page's search filter: a blank query
/// keeps everything, otherwise any listed field must contain it
/// (case-insensitive).
fn matches(query : String, fields : Array[String]) -> Bool {
  let query = query.trim().to_owned().to_lower()
  if query.is_empty() {
    return true
  }
  for field in fields {
    if field.to_lower().contains(query) {
      return true
    }
  }
  false
}

///|
/// The Skills page, shown in the main area in place of the conversation:
/// header, search, the local library, then the mooncakes.io catalog.
fn page(state : State, input : Input, emit : @cmd.Emit[Msg]) -> @html.Html {
  let sections : Array[@html.Html] = [
    @html.div(class="skills-header", [
      @html.div(class="page-eyebrow", "Library"),
      @html.h1("Skills"),
      @html.div(
        class="skills-subtitle",
        "Playbooks the agent reads when a task matches. Skills apply to new chats.",
      ),
    ]),
    @html.div(
      class="skills-search",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      [
        icon(icon_search),
        @html.input(
          input_type=@html.InputType::Search,
          value=state.query,
          placeholder="Search skills…",
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
      installed_rows.push(installed_row(state, skill, emit))
    }
  }
  if installed_rows.is_empty() {
    installed_rows.push(
      @html.div(
        class="skills-empty",
        if input.installed.is_empty() {
          "No skills installed yet."
        } else {
          "No installed skill matches the search."
        },
      ),
    )
  }
  sections.push(group(icon_extensions, "Installed", installed_rows))
  let market_rows : Array[@html.Html] = []
  match state.catalog {
    Idle | Loading =>
      market_rows.push(
        @html.div(class="skills-empty", "Loading the skill catalog…"),
      )
    Failed(message) =>
      market_rows.push(@html.div(class="skills-empty danger", message))
    Ready(items) => {
      for item in items {
        if matches(state.query, [item.name, item.description, item.author]) {
          market_rows.push(market_row(state, input, item, emit))
        }
      }
      if market_rows.is_empty() {
        market_rows.push(
          @html.div(
            class="skills-empty",
            if items.is_empty() {
              "The registry lists no installable skills yet."
            } else {
              "No registry skill matches the search."
            },
          ),
        )
      }
    }
  }
  sections.push(group(icon_package, "Mooncakes registry", market_rows))
  @html.section(class="skills-page", [
    @html.div(class="skills-page-inner", sections),
  ])
}
