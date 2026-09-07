///|
test "shell classes leave native geometry to the window subscription" {
  assert_eq(app_shell_class(true), "app")
  assert_eq(app_shell_class(false), "app sidebar-collapsed")
}

///|
fn sidebar_project_for_test(model : Model) -> @project.Input raise {
  for section in model.sidebar_component_sections(model.dev()) {
    guard section.id().source() == "openseek.projects" else { continue }
    for entry in section.entries {
      if entry is @section.Project(project) {
        return project
      }
    }
  }
  fail("missing project sidebar input")
}

///|
test "a fresh chat selects its project and materializes on first send" {
  let workspace = @interop.ChannelId::Local.test_project()
  let fresh = test_model().with_dev(dev => {
    ..dev,
    active_project: Some(workspace),
  })
  let fresh_project = sidebar_project_for_test(fresh)
  assert_eq(fresh_project.activation, Some("desktop-test"))
  assert_true(fresh_project.conversations.is_empty())

  // Typing still belongs to the new-chat page; it does not manufacture a
  // selected child row before the user submits anything.
  let typed = fresh.replace_conversation({
    ..fresh.active(),
    task: "Explain the sidebar state",
    composer_draft_present: true,
  })
  assert_true(sidebar_project_for_test(typed).conversations.is_empty())

  let (_, submitted) = update(test_dispatch(), Send, typed)
  let submitted_project = sidebar_project_for_test(submitted)
  assert_eq(submitted_project.conversations.length(), 1)
  assert_eq(
    submitted_project.conversations[0].label,
    "Explain the sidebar state",
  )
  assert_true(submitted_project.conversations[0].active)

  // Opening Codex preserves the OpenSeek conversation for returning to it,
  // but must clear its sidebar highlight while the Codex page is visible.
  let (_, codex_page) = update(test_dispatch(), OpenCodex, submitted)
  assert_true(!sidebar_project_for_test(codex_page).conversations[0].active)
  assert_true(
    codex_page.conversation_selection() == submitted.conversation_selection(),
  )
}
