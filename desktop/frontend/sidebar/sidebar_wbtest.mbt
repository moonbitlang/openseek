///|
#warnings("-alert_unstable")
test "section keeps disclosure and action controls separate" {
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      Section::{
        label: "Projects",
        toggle: @cmd.none,
        collapsed: true,
        action: Some({
          title: "Add a project",
          command: @cmd.none,
          disabled: false,
        }),
        selected: true,
      }.render(),
    )
  })
  assert_true(
    html.contains(
      "sidebar-heading section-heading collapsible collapsed active",
    ),
  )
  assert_true(html.contains(">Projects</span>"))
  assert_true(html.contains("title=\"Add a project\""))
}

///|
#warnings("-alert_unstable")
test "conversation row preserves disclosure status and archive slots" {
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      ConversationRow::{
        title: "thread-1",
        label: "Inspect changes",
        open: @cmd.none,
        nested: true,
        subrun: false,
        active: true,
        running: true,
        subruns: Subruns(count=2, expanded=true, toggle=@cmd.none),
        status: [@html.span(class="run-dot accent pulse", "")],
        archive: Some({ title: "Archive conversation", command: @cmd.none }),
      }.render(),
    )
  })
  assert_true(html.contains("conversation-row nested active running"))
  assert_true(html.contains("row-twisty expanded"))
  assert_true(html.contains("2 subagent runs"))
  assert_true(html.contains("row-status"))
  assert_true(html.contains("row-actions"))
  assert_true(html.contains("title=\"Archive conversation\""))
}

///|
#warnings("-alert_unstable")
test "workspace menu button precedes the actions, and its body only renders open" {
  let closed = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      WorkspaceRow::{
        title: "/workspace",
        label: "workspace",
        active: false,
        collapsed: true,
        toggle: @cmd.none,
        menu: Some({
          title: "More actions",
          open: false,
          toggle: @cmd.none,
          body: () => @html.div(class="workspace-menu", "items"),
        }),
        actions: [
          {
            title: "New conversation",
            command: @cmd.none,
            image: @icons.icon_add,
          },
        ],
      }.render(),
    )
  })
  let more = closed.find("title=\"More actions\"").unwrap()
  let create = closed.find("title=\"New conversation\"").unwrap()
  assert_true(more < create)
  assert_false(closed.contains("workspace-menu\""))
  assert_false(closed.contains("menu-open"))
  assert_true(closed.contains("workspace-row collapsible collapsed"))
  assert_true(closed.contains("aria-expanded=\"false\""))
  let open = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      WorkspaceRow::{
        title: "/workspace",
        label: "workspace",
        active: false,
        collapsed: false,
        toggle: @cmd.none,
        menu: Some({
          title: "More actions",
          open: true,
          toggle: @cmd.none,
          body: () => @html.div(class="workspace-menu", "items"),
        }),
        actions: [],
      }.render(),
    )
  })
  assert_true(open.contains("workspace-row collapsible menu-open"))
  assert_true(open.contains("aria-expanded=\"true\""))
  assert_true(open.contains("workspace-menu-button open"))
  assert_true(open.contains("workspace-menu\""))
}
