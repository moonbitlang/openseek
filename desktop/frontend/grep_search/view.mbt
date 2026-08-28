///|
const SearchInputId : String = "workspace-search-input"

///|
pub fn focus_query_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(SearchInputId).to_option()
        is Some(input) {
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "focus",
          ([] : Array[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
priv struct FileGroup {
  path : String
  matches : Array[@protocol.TextSearchMatch]
  count : Int
}

///|
fn grouped_matches(
  matches : Array[@protocol.TextSearchMatch],
) -> Array[FileGroup] {
  let groups : Array[FileGroup] = []
  let indexes : Map[String, Int] = Map([])
  for result in matches {
    match indexes.get(result.path) {
      Some(index) => {
        let group = groups[index]
        let rows = group.matches
        rows.push(result)
        groups[index] = {
          ..group,
          matches: rows,
          count: group.count + result.ranges.length(),
        }
      }
      None => {
        indexes[result.path] = groups.length()
        groups.push({
          path: result.path,
          matches: [result],
          count: result.ranges.length(),
        })
      }
    }
  }
  groups
}

///|
/// Preserve each file's complete occurrence count while taking only the
/// matching lines currently admitted to the DOM. This is deliberately a view
/// budget: Host search semantics and the 20,000-result ceiling remain intact.
fn visible_file_groups(page : Page) -> Array[FileGroup] {
  let visible : Array[FileGroup] = []
  let mut remaining = page.visible_lines.max(0)
  for group in grouped_matches(page.text.matches) {
    guard remaining > 0 else { break }
    let rows : Array[@protocol.TextSearchMatch] = []
    for result in group.matches {
      guard rows.length() < remaining else { break }
      rows.push(result)
    }
    visible.push({ ..group, matches: rows, })
    remaining -= rows.length()
  }
  visible
}

///|
fn file_label(path : String) -> (String, String) {
  match [..path.split("/")] {
    [] => (path, "")
    [last] => (last.to_owned(), "")
    [.. parents, last] =>
      (last.to_owned(), parents.map(part => part.to_owned()).join("/"))
  }
}

///|
fn toggle_button(
  label : String,
  title : String,
  pressed : Bool,
  command : @cmd.Cmd,
) -> @html.Html {
  @html.button(
    class=if pressed { "search-option pressed" } else { "search-option" },
    title~,
    attrs=@html.Attrs::build()
      .aria_pressed(pressed.to_string())
      .on_click(_ => command),
    label,
  )
}

///|
/// VS Code's `Codicon.wholeWord` (CC BY 4.0). Unlike a plain `ab` label, the
/// glyph carries the baseline bracket that identifies whole-word matching and
/// occupies the same 16 x 16 optical box as the other product icons.
fn icon_whole_word() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build().fill("currentColor"),
    [
      @svg.path(
        d="M15.5 12.5C15.776 12.5 16 12.724 16 13V13.5C16 14.327 15.327 15 14.5 15H1.5C0.673 15 0 14.327 0 13.5V13C0 12.724 0.224 12.5 0.5 12.5C0.776 12.5 1 12.724 1 13V13.5C1 13.775 1.224 14 1.5 14H14.5C14.776 14 15 13.775 15 13.5V13C15 12.724 15.224 12.5 15.5 12.5Z",
      ),
      @svg.path(
        attrs=@svg.Attrs::build().fill_rule("evenodd").clip_rule("evenodd"),
        d="M4.8584 5.6709C6.16516 5.73603 6.94308 6.48734 6.99707 7.69922L7 7.83594V11.5107C6.996 11.7596 6.80919 11.9649 6.56836 11.998L6.5 12.0029C6.24709 12.0029 6.038 11.8152 6.00488 11.5713L6 11.5029V11.4326C5.341 11.8096 4.73199 12.0029 4.16699 12.0029C2.941 12.0029 2 11.1399 2 9.83594C2.00003 8.68597 2.79247 7.83185 4.10645 7.67285C4.7283 7.59793 5.35918 7.64552 5.99902 7.81348C5.99202 7.07548 5.62762 6.70995 4.80762 6.66895C4.16686 6.637 3.7161 6.72717 3.45215 6.91211C3.22615 7.07111 2.91386 7.01604 2.75586 6.79004C2.5969 6.56404 2.65194 6.25174 2.87793 6.09375C3.31692 5.78579 3.91404 5.65006 4.66699 5.66406L4.8584 5.6709ZM5.79688 8.81836C5.25888 8.67037 4.73558 8.62843 4.22559 8.69043C3.40389 8.79054 2.99902 9.22747 2.99902 9.86035C2.99917 10.5911 3.47413 11.0273 4.16602 11.0273C4.62001 11.0273 5.17799 10.8168 5.83398 10.3848L5.99902 10.2725V8.87891L5.79688 8.81836Z",
      ),
      @svg.path(
        attrs=@svg.Attrs::build().fill_rule("evenodd").clip_rule("evenodd"),
        d="M9.55078 2.00586C9.78578 2.02986 9.97307 2.21715 9.99707 2.45215C10 2.46907 10 2.48601 10 2.50293V6.60254C10.418 6.22566 10.9371 6.00293 11.5 6.00293C12.881 6.00293 14 7.34596 14 9.00293C14 10.6599 12.881 12.0029 11.5 12.0029C10.9371 12.0029 10.418 11.7802 10 11.4033V11.5029C10 11.7619 9.80278 11.974 9.55078 12C9.53385 12.003 9.51693 12.0029 9.5 12.0029C9.224 12.0029 9 11.7789 9 11.5029V2.50293C9 2.486 9.00095 2.46907 9.00293 2.45215C9.02793 2.20015 9.241 2.00293 9.5 2.00293C9.51692 2.00293 9.53386 2.00388 9.55078 2.00586ZM11.4355 7.00391C11.0307 7.03208 10.5769 7.31545 10.29 7.82227C10.1232 8.12611 10.018 8.49479 10.002 8.89453C9.99995 8.92952 10 8.96597 10 9.00195C10 9.03795 10.001 9.07438 10.002 9.10938C10.018 9.50814 10.1222 9.87582 10.2891 10.1797C10.576 10.6875 11.0307 10.9728 11.4355 11C11.4565 11.002 11.478 11.002 11.5 11.002C11.522 11.002 11.5435 11.001 11.5645 11C11.9693 10.9728 12.424 10.6875 12.7109 10.1797C12.8778 9.87582 12.982 9.50814 12.998 9.10938C13 9.07438 13 9.03795 13 9.00195C13 8.96597 12.999 8.92952 12.998 8.89453C12.982 8.49479 12.8768 8.12611 12.71 7.82227C12.4231 7.31545 11.9693 7.03109 11.5645 7.00391C11.5435 7.00191 11.522 7.00195 11.5 7.00195C11.478 7.00195 11.4565 7.00291 11.4355 7.00391Z",
      ),
    ],
  )
}

///|
fn whole_word_toggle_button(
  title : String,
  pressed : Bool,
  command : @cmd.Cmd,
) -> @html.Html {
  @html.button(
    class=if pressed { "search-option pressed" } else { "search-option" },
    title~,
    attrs=@html.Attrs::build()
      .aria_label(title)
      .aria_pressed(pressed.to_string())
      .on_click(_ => command),
    [icon_whole_word()],
  )
}

///|
fn query_key_attrs(emit : @cmd.Emit[Msg]) -> @html.Attrs {
  @html.Attrs::build()
  .id(SearchInputId)
  .aria_label("Search")
  .aria_keyshortcuts("Meta+Shift+F Control+Shift+F")
  .data_set("focus-owner", "")
  .on_keydown(event => {
    if event.key() == "Enter" {
      event.prevent_default()
      emit(Submit)
    } else {
      @cmd.none
    }
  })
}

///|
/// The mode selector, modeled on semgrep's two search engines: plain text/grep
/// matching versus structural MoonBit code patterns. Switching modes retires
/// the armed query and its results via the generation fence.
fn mode_control(mode : Mode, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(class="search-mode", [
    @html.button(
      class=if mode is Text {
        "search-mode-button pressed"
      } else {
        "search-mode-button"
      },
      attrs=@html.Attrs::build()
        .aria_label("Text search")
        .aria_pressed((mode is Text).to_string())
        .on_click(_ => emit(ModeChanged(Text))),
      "Text",
    ),
    @html.button(
      class=if mode is Semantic {
        "search-mode-button pressed"
      } else {
        "search-mode-button"
      },
      attrs=@html.Attrs::build()
        .aria_label("Code search")
        .aria_pressed((mode is Semantic).to_string())
        .on_click(_ => emit(ModeChanged(Semantic))),
      "Code",
    ),
  ])
}

///|
/// The mode-specific query options.
fn mode_options(page : Page, emit : @cmd.Emit[Msg]) -> @html.Html {
  if page.mode is Text {
    @html.div(class="search-mode-options", [
      toggle_button(
        "Aa",
        "Match Case",
        page.text.case_sensitive,
        emit(ToggleCaseSensitive),
      ),
      whole_word_toggle_button(
        "Match Whole Word",
        page.text.whole_word,
        emit(ToggleWholeWord),
      ),
      toggle_button(
        ".*",
        "Use Regular Expression",
        page.text.regex,
        emit(ToggleRegex),
      ),
    ])
  } else {
    @html.nothing
  }
}

///|
fn pattern_repair_control(page : Page, emit : @cmd.Emit[Msg]) -> @html.Html {
  let requested = page.pattern_repair_phase is PatternRepairRequested
  let completed = page.pattern_repair_phase is PatternRepairPreview
  let failed = page.pattern_repair_phase is PatternRepairFailed
  @html.button(
    class=if requested {
      "search-option pressed pattern-repair-button"
    } else if completed {
      "search-option pressed pattern-repair-button"
    } else if failed {
      "search-option pressed pattern-repair-button"
    } else {
      "search-option pattern-repair-button"
    },
    title=if requested { "Cancel Pattern Repair" } else { "Fix Pattern" },
    attrs=@html.Attrs::build()
      .aria_label(
        if requested {
          "Cancel Pattern Repair"
        } else {
          "Fix Pattern"
        },
      )
      .aria_pressed(requested.to_string())
      .on_click(_ => emit(FixPattern)),
    @icons.icon(if requested { @icons.icon_close } else { @icons.icon_sparkle }),
  )
}

///|
fn pattern_repair_notice(page : Page, emit : @cmd.Emit[Msg]) -> @html.Html {
  if page.pattern_repair_phase is PatternRepairRequested {
    @html.div(
      class="search-empty",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      "Pattern repair is not connected yet.",
    )
  } else if page.pattern_repair_phase is PatternRepairPreview &&
    page.pattern_repair_candidate is Some(candidate) {
    @html.div(class="search-pattern-repair-preview", [
      @html.div(class="search-pattern-repair-title", "Suggested Pattern"),
      @html.pre(class="search-pattern-repair-candidate", candidate),
      if page.pattern_repair_message is Some(message) {
        @html.div(class="search-pattern-repair-message", message)
      } else {
        @html.nothing
      },
      @html.div(class="search-pattern-repair-actions", [
        @html.button(on_click=emit(AcceptPatternRepair), "Accept"),
        @html.button(on_click=emit(RejectPatternRepair), "Discard"),
      ]),
    ])
  } else if page.pattern_repair_message is Some(message) {
    @html.div(
      class=if page.pattern_repair_phase is PatternRepairFailed {
        "search-empty error"
      } else {
        "search-empty"
      },
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      message,
    )
  } else {
    @html.nothing
  }
}

///|
fn highlighted_preview(result : @protocol.TextSearchMatch) -> Array[@html.Html] {
  let children : Array[@html.Html] = []
  let preview_start = result.preview_start_column - 1
  let mut cursor = 0
  for range in result.ranges {
    let start = (range.start_column - 1 - preview_start)
      .max(0)
      .min(result.preview.length())
    let end = (range.end_column - 1 - preview_start)
      .max(0)
      .min(result.preview.length())
    if end <= cursor || start >= result.preview.length() {
      continue
    }
    let start = start.max(cursor)
    if start > cursor {
      children.push(@html.span(result.preview[cursor:start].to_owned()))
    }
    if end > start {
      children.push(
        @html.span(
          class="search-match-highlight",
          result.preview[start:end].to_owned(),
        ),
      )
      cursor = end
    }
  }
  if cursor < result.preview.length() {
    children.push(@html.span(result.preview[cursor:].to_owned()))
  }
  if children.is_empty() {
    children.push(@html.span(result.preview))
  }
  children
}

///|
fn result_row(
  result : @protocol.TextSearchMatch,
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  let range = result.ranges[0]
  let target = @common.Range(
    result.line_number,
    range.start_column,
    result.line_number,
    range.end_column,
  )
  @html.button(
    class="search-result-row",
    title="Open \{result.path}:\{result.line_number}",
    on_click=open_match(result.path, target),
    [
      @html.span(class="search-result-line", "\{result.line_number}"),
      @html.span(class="search-result-preview", highlighted_preview(result)),
    ],
  )
}

///|
fn file_group_view(
  page : Page,
  group : FileGroup,
  emit : @cmd.Emit[Msg],
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  let collapsed = page.collapsed.get(group.path).unwrap_or(false)
  let (name, parent) = file_label(group.path)
  let rows = if collapsed {
    ([] : Array[@html.Html])
  } else {
    group.matches.map(result => result_row(result, open_match))
  }
  @html.div(class="search-file-group", [
    @html.button(
      class="search-file-header",
      title=group.path,
      attrs=@html.Attrs::build()
        .aria_expanded((!collapsed).to_string())
        .on_click(_ => emit(ToggleFile(group.path))),
      [
        @html.span(
          class="search-file-chevron",
          attrs=@html.Attrs::build().aria_hidden("true"),
          if collapsed {
            "›"
          } else {
            "⌄"
          },
        ),
        @html.span(class="search-file-name", name),
        @html.span(class="search-file-parent", parent),
        @html.span(class="search-file-count", "\{group.count}"),
      ],
    ),
    @html.div(class="search-file-results", rows),
  ])
}

///|
fn search_message(page : Page) -> @html.Html? {
  match page.phase {
    Failed(code~, message~) => {
      let heading = match code {
        "invalid_regex" => "Invalid regular expression"
        "invalid_glob" => "Invalid file pattern"
        "permission_denied" => "Workspace is not readable"
        "rg_unavailable" => "Bundled ripgrep is unavailable"
        "invalid_pattern" => "Invalid code pattern"
        "moongrep_unavailable" => "Semantic search is unavailable"
        "invalid_request" => "Nothing to search"
        _ => "Search failed"
      }
      Some(
        @html.div(
          class="search-empty error",
          attrs=@html.Attrs::build().role("alert"),
          [
            @html.div(class="search-empty-title", heading),
            @html.div(class="search-empty-detail", message),
          ],
        ),
      )
    }
    Ready if page.active_result_count() == 0 =>
      Some(
        @html.div(
          class="search-empty",
          attrs=@html.Attrs::build().role("status").aria_live("polite"),
          match page.mode {
            Text => "No results found."
            Semantic => "No matching code found."
          },
        ),
      )
    Idle if page.text.query.is_empty() =>
      Some(
        @html.div(
          class="search-empty",
          match page.mode {
            Text => "Search across files in the current checkout."
            Semantic => "Search MoonBit code patterns in the current checkout."
          },
        ),
      )
    Idle if page.active_result_count() == 0 =>
      Some(
        @html.div(
          class="search-empty",
          "Search results cleared. Press Enter to search again.",
        ),
      )
    _ => None
  }
}

///|
/// Dispatch the results body to the armed Search engine: ripgrep text rows or
/// moongrep structural hits, mirroring semgrep's mode split.
fn search_body(
  page : Page,
  emit : @cmd.Emit[Msg],
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  match page.mode {
    Text => text_search_body(page, emit, open_match)
    Semantic => semantic_search_body(page, emit, open_match)
  }
}

///|
fn text_search_body(
  page : Page,
  emit : @cmd.Emit[Msg],
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  let children : Array[@html.Html] = []
  let busy = page.phase is Debouncing || page.phase is Loading
  let summary = page.result_summary()
  let file_count = page.active_file_count()
  let summary_text = if busy {
    "Searching…"
  } else if summary.match_count == 1 {
    "1 result in \{file_count} file"
  } else {
    "\{summary.match_count} results in \{file_count} files"
  }
  children.push(
    @html.div(
      class="search-summary",
      attrs=@html.Attrs::build().aria_live("polite").aria_busy(busy.to_string()),
      summary_text,
    ),
  )
  if summary.limit_hit {
    children.push(
      @html.div(
        class="search-truncated",
        attrs=@html.Attrs::build().role("status"),
        "Only the first 20,000 matches are shown. Narrow the search to see more.",
      ),
    )
  }
  if search_message(page) is Some(message) {
    children.push(message)
  } else {
    for group in visible_file_groups(page) {
      children.push(file_group_view(page, group, emit, open_match))
    }
    let shown = page.visible_lines.min(page.text.matches.length())
    if shown < page.text.matches.length() {
      let next = VisibleSearchLineStep.min(page.text.matches.length() - shown)
      children.push(
        @html.div(class="search-show-more", [
          @html.button(
            on_click=emit(ShowMore),
            "Show \{next} more matching lines",
          ),
          @html.div(
            class="search-show-more-detail",
            "\{shown} of \{page.text.matches.length()} matching lines rendered",
          ),
        ]),
      )
    }
  }
  @html.div(class="search-results", children)
}

///|
priv struct SemanticFileGroup {
  path : String
  hits : Array[@protocol.SemanticSearchHit]
  count : Int
}

///|
fn semantic_grouped_hits(
  hits : Array[@protocol.SemanticSearchHit],
) -> Array[SemanticFileGroup] {
  let groups : Array[SemanticFileGroup] = []
  let indexes : Map[String, Int] = Map([])
  for hit in hits {
    match indexes.get(hit.path) {
      Some(index) => {
        let group = groups[index]
        let rows = group.hits
        rows.push(hit)
        groups[index] = { ..group, hits: rows, count: group.count + 1, }
      }
      None => {
        indexes[hit.path] = groups.length()
        groups.push({ path: hit.path, hits: [hit], count: 1, })
      }
    }
  }
  groups
}

///|
fn visible_semantic_file_groups(page : Page) -> Array[SemanticFileGroup] {
  let visible : Array[SemanticFileGroup] = []
  let mut remaining = page.visible_lines.max(0)
  for group in semantic_grouped_hits(page.semantic.hits) {
    guard remaining > 0 else { break }
    let rows : Array[@protocol.SemanticSearchHit] = []
    for hit in group.hits {
      guard rows.length() < remaining else { break }
      rows.push(hit)
    }
    visible.push({ ..group, hits: rows, })
    remaining -= rows.length()
  }
  visible
}

///|
/// One moongrep context line: gutter line number plus the source text, with the
/// matched lines highlighted, in the style of semgrep's pattern-match output.
fn semantic_context_line_view(
  line : @protocol.SemanticContextLine,
) -> @html.Html {
  @html.div(
    class=if line.is_match {
      "search-context-line matched"
    } else {
      "search-context-line"
    },
    [
      @html.span(class="search-context-gutter", "\{line.line}"),
      @html.span(class="search-context-text", line.text),
    ],
  )
}

///|
fn semantic_hit_view(
  hit : @protocol.SemanticSearchHit,
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  let target = @common.Range(
    hit.start_line,
    hit.start_column,
    hit.end_line,
    hit.end_column,
  )
  @html.div(
    class="search-semantic-hit",
    attrs=@html.Attrs::build().on_click(_ => open_match(hit.path, target)),
    [
      @html.div(class="search-semantic-meta", [
        @html.span(class="search-semantic-rule", hit.rule_id),
        if hit.description is Some(description) && !description.is_empty() {
          @html.span(class="search-semantic-desc", description)
        } else {
          @html.nothing
        },
      ]),
      @html.div(
        class="search-semantic-context",
        hit.source_context.map(line => semantic_context_line_view(line)),
      ),
    ],
  )
}

///|
fn semantic_file_group_view(
  page : Page,
  group : SemanticFileGroup,
  emit : @cmd.Emit[Msg],
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  let collapsed = page.collapsed.get(group.path).unwrap_or(false)
  let (name, parent) = file_label(group.path)
  let rows = if collapsed {
    ([] : Array[@html.Html])
  } else {
    group.hits.map(hit => semantic_hit_view(hit, open_match))
  }
  @html.div(class="search-file-group", [
    @html.button(
      class="search-file-header",
      title=group.path,
      attrs=@html.Attrs::build()
        .aria_expanded((!collapsed).to_string())
        .on_click(_ => emit(ToggleFile(group.path))),
      [
        @html.span(
          class="search-file-chevron",
          attrs=@html.Attrs::build().aria_hidden("true"),
          if collapsed {
            "›"
          } else {
            "⌄"
          },
        ),
        @html.span(class="search-file-name", name),
        @html.span(class="search-file-parent", parent),
        @html.span(class="search-file-count", "\{group.count}"),
      ],
    ),
    @html.div(class="search-file-results", rows),
  ])
}

///|
fn semantic_search_body(
  page : Page,
  emit : @cmd.Emit[Msg],
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  let children : Array[@html.Html] = []
  let busy = page.phase is Debouncing || page.phase is Loading
  let result_summary = page.result_summary()
  let file_count = page.active_file_count()
  let summary = if busy {
    if page.semantic.hits.is_empty() {
      "Searching…"
    } else {
      // The scan is still running; these counts are the partial stream, not
      // the final totals the reply will replace.
      "\{result_summary.match_count} matches in \{file_count} files so far…"
    }
  } else if result_summary.match_count == 1 {
    "1 match in \{file_count} file"
  } else {
    "\{result_summary.match_count} matches in \{file_count} files"
  }
  children.push(
    @html.div(
      class="search-summary",
      attrs=@html.Attrs::build().aria_live("polite").aria_busy(busy.to_string()),
      summary,
    ),
  )
  if result_summary.limit_hit {
    children.push(
      @html.div(
        class="search-truncated",
        attrs=@html.Attrs::build().role("status"),
        "Only the first 20,000 matches are shown. Narrow the search to see more.",
      ),
    )
  }
  if page.semantic.partial {
    children.push(
      @html.div(
        class="search-truncated",
        attrs=@html.Attrs::build().role("status"),
        "Results may be incomplete — moongrep could not parse some files.",
      ),
    )
  }
  if search_message(page) is Some(message) {
    children.push(message)
  }
  for group in visible_semantic_file_groups(page) {
    children.push(semantic_file_group_view(page, group, emit, open_match))
  }
  let shown = page.visible_lines.min(page.semantic.hits.length())
  if shown < page.semantic.hits.length() {
    let next = VisibleSearchLineStep.min(page.semantic.hits.length() - shown)
    children.push(
      @html.div(class="search-show-more", [
        @html.button(on_click=emit(ShowMore), "Show \{next} more matches"),
        @html.div(
          class="search-show-more-detail",
          "\{shown} of \{page.semantic.hits.length()} matches rendered",
        ),
      ]),
    )
  }

  @html.div(class="search-results", children)
}

///|
fn page_view(
  page : Page,
  emit : @cmd.Emit[Msg],
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  let details = if page.details_open {
    let details : Array[@html.Html] = [
      @html.label([
        @html.span("files to include"),
        @html.input(
          input_type=@html.InputType::Text,
          value=page.include_glob,
          placeholder="e.g. src/**, tests/**",
          on_input=emit.map(value => IncludeChanged(value)),
          attrs=@html.Attrs::build()
            .aria_label("files to include")
            .data_set("focus-owner", ""),
        ),
      ]),
      @html.label([
        @html.span("files to exclude"),
        @html.input(
          input_type=@html.InputType::Text,
          value=page.exclude_glob,
          placeholder="e.g. **/*.snap, generated/**",
          on_input=emit.map(value => ExcludeChanged(value)),
          attrs=@html.Attrs::build()
            .aria_label("files to exclude")
            .data_set("focus-owner", ""),
        ),
      ]),
    ]
    @html.div(class="search-details", details)
  } else {
    @html.nothing
  }
  @html.div(class="workspace-search", [
    @html.div(class="search-query-row", [
      mode_control(page.mode, emit),
      if page.mode is Text {
        @html.input(
          input_type=@html.InputType::Text,
          value=page.text.query,
          placeholder="Search",
          on_input=emit.map(value => QueryChanged(value)),
          attrs=query_key_attrs(emit),
        )
      } else {
        @html.input(
          input_type=@html.InputType::Text,
          value=page.semantic.patterns[0],
          placeholder="inspect($(x:arg))",
          on_input=emit.map(value => PatternChanged(0, value)),
          attrs=@html.Attrs::build()
            .aria_label("pattern")
            .data_set("focus-owner", ""),
        )
      },
      if page.mode is Semantic {
        pattern_repair_control(page, emit)
      } else {
        @html.nothing
      },
      mode_options(page, emit),
      @html.button(
        class=if page.details_open {
          "search-option pressed search-details-toggle"
        } else {
          "search-option search-details-toggle"
        },
        title="Toggle Search Details",
        attrs=@html.Attrs::build()
          .aria_expanded(page.details_open.to_string())
          .on_click(_ => emit(ToggleDetails)),
        "…",
      ),
    ]),
    if page.mode is Semantic {
      let patterns : Array[@html.Html] = []
      for index, pattern in page.semantic.patterns {
        if index > 0 {
          patterns.push(
            @html.div(class="search-semantic-source", [
              @html.input(
                input_type=@html.InputType::Text,
                value=pattern,
                placeholder="inspect($(x:arg))",
                on_input=emit.map(value => PatternChanged(index, value)),
                attrs=@html.Attrs::build()
                  .aria_label("pattern")
                  .data_set("focus-owner", ""),
              ),
              @html.button(on_click=emit(RemovePattern(index)), "−"),
            ]),
          )
        }
      }
      patterns.push(@html.button(on_click=emit(AddPattern), "+ Add pattern"))
      @html.div(class="search-code-patterns", patterns)
    } else {
      @html.nothing
    },
    if page.mode is Semantic {
      pattern_repair_notice(page, emit)
    } else {
      @html.nothing
    },
    details,
    @html.div(class="search-toolbar", [
      @html.button(title="Refresh", on_click=emit(Refresh), "Refresh"),
      @html.button(
        title="Clear Search Results",
        on_click=emit(ClearResults),
        "Clear",
      ),
      @html.button(
        title="Collapse All",
        on_click=emit(CollapseAll),
        "Collapse All",
      ),
    ]),
    search_body(page, emit, open_match),
  ])
}

///|
/// Search is composed into the file explorer beside its Files and Changes
/// inventories. Fileeditor supplies the one active checkout projection.
pub fn State::explorer_view(
  self : State,
  input : Input,
  emit : @cmd.Emit[Msg],
  open_match : (String, @common.Range) -> @cmd.Cmd,
) -> @html.Html {
  match input.root {
    Some(_) => page_view(self.page, emit, open_match)
    None =>
      @html.div(class="workspace-search search-no-workspace", [
        @html.div(class="search-empty-title", "No checkout available"),
        @html.div(
          class="search-empty-detail",
          "Open a conversation or task with a checkout to search its files.",
        ),
      ])
  }
}
