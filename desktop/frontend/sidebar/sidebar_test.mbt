///|
test "the sidebar input keeps peer sections in one component value" {
  let input : @sidebar.Input = {
    search: @session_search.Model(),
    locale: English,
    mode: WorkMode,
    has_host: true,
    work_available: true,
    skills_available: true,
    notices: [],
    chat_sections: [],
    work_sections: [
      {
        id: @section.Id(source="openseek.projects", channel="local"),
        label: None,
        activation: None,
        action: None,
        secondary_actions: [],
        entries: [],
      },
      {
        id: @section.Id(source="archived", channel="local"),
        label: Some("Archived chats"),
        activation: Some("desktop-test"),
        action: None,
        secondary_actions: [],
        entries: [],
      },
    ],
    update_label: None,
    update_enabled: false,
    schedules_active: false,
    skills_active: false,
    settings_active: false,
    downloads: false,
    account: None,
  }
  assert_eq(input.work_sections.length(), 2)
  assert_eq(input.work_sections[0].id().source(), "openseek.projects")
  assert_eq(input.work_sections[1].id().source(), "archived")
}
