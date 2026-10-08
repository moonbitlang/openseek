///|
test "selected option does not request a change command" {
  let requested_changes : Array[String] = []
  let control = @select_control.Control::{
    id: "provider-select",
    groups: [
      {
        label: "Provider",
        options: [
          { value: "deepseek", label: "DeepSeek", },
          { value: "custom", label: "Custom URL", },
        ],
      },
    ],
    selected: Some("deepseek"),
    disabled: false,
    open: true,
    toggle: @cmd.none,
    dismiss: @cmd.none,
    // Emit is the caller boundary. Recording which payload commands the view
    // asks it to construct proves that the selected row cannot later dispatch
    // a false change, while an unselected row still receives its command.
    change: @cmd.Emit(value => {
      requested_changes.push(value)
      @cmd.none
    }),
    title: "Provider",
    aria_label: "Provider",
    presentation: @select_control.Setting,
  }
  ignore(control.render())
  @debug.assert_eq(requested_changes, ["custom"])
}

///|
test "no selection keeps every action available including an empty value" {
  let requested_changes : Array[String] = []
  let control = @select_control.Control::{
    id: "action-select",
    groups: [
      {
        label: "Actions",
        options: [
          { value: "", label: "Default action", },
          { value: "images", label: "Attach images", },
        ],
      },
    ],
    selected: None,
    disabled: false,
    open: true,
    toggle: @cmd.none,
    dismiss: @cmd.none,
    change: @cmd.Emit(value => {
      requested_changes.push(value)
      @cmd.none
    }),
    title: "Actions",
    aria_label: "Actions",
    presentation: @select_control.Setting,
  }
  ignore(control.render())
  @debug.assert_eq(requested_changes, ["", "images"])
  requested_changes.clear()
  // An empty string can still be an actual selected value; it is not absence.
  ignore({ ..control, selected: Some(""), }.render())
  @debug.assert_eq(requested_changes, ["images"])
}
