///|
test "the sidebar input keeps peer sections in one component value" {
  let input : Input = {
    notices: [],
    sections: [
      {
        id: @section.Id(source="openseek.projects", channel="local"),
        label: "Projects",
        initially_collapsed: false,
        activation: None,
        action: None,
        entries: [],
      },
      {
        id: @section.Id(source="archived", channel="local"),
        label: "Archived chats",
        initially_collapsed: true,
        activation: Some("desktop-test"),
        action: None,
        entries: [],
      },
    ],
    update_label: None,
    update_enabled: false,
    skills_active: false,
    settings_active: false,
    account: None,
  }
  assert_eq(input.sections.length(), 2)
  assert_eq(input.sections[0].id().source(), "openseek.projects")
  assert_eq(input.sections[1].id().source(), "archived")
}
