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

///|
test "workflow children fold under live or listed parents before inventory refresh" {
  let workspace = @interop.ChannelId::Local.test_project()
  for parent_listed in [false, true] {
    let page = subrun_page(active="desktop-test-sr-1")
    let page = page
      .replace_conversation({
        ..subrun_child_of(page),
        messages: [
          { kind: User("The criteria under audit"), ts: None, sequence: None, },
        ],
      })
      .with_dev(dev => {
        ..dev,
        active_project: Some(workspace),
        sessions: if parent_listed {
          [
            {
              id: "desktop-test",
              title: Some("<user_mentions>"),
              workspace,
              workspace_name: "work",
              updated_at_ms: Some(1.0),
            },
          ]
        } else {
          []
        },
      })
    let project = sidebar_project_for_test(page)
    assert_eq(project.conversations.length(), 1)
    let parent = project.conversations[0]
    assert_eq(parent.children.length(), 1)
    assert_eq(parent.children[0].label, "sr-1 · The criteria under audit")
    assert_true(parent.children[0].active)
    assert_true(parent.children[0].subrun)

    // Once the host lists both records, the same family remains without duplicates.
    let refreshed = page.with_dev(dev => {
      ..dev,
      sessions: [
        {
          id: "desktop-test",
          title: Some("<user_mentions>"),
          workspace,
          workspace_name: "work",
          updated_at_ms: Some(1.0),
        },
        {
          id: "desktop-test-sr-1",
          title: Some("The criteria under audit"),
          workspace,
          workspace_name: "work",
          updated_at_ms: Some(2.0),
        },
      ],
    })
    let project = sidebar_project_for_test(refreshed)
    assert_eq(project.conversations.length(), 1)
    assert_eq(project.conversations[0].children.length(), 1)
  }
}
