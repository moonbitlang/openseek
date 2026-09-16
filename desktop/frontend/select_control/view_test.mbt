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
    selected: "deepseek",
    disabled: false,
    open: true,
    toggle: @cmd.none,
    dismiss: @cmd.none,
    // Emit is the caller boundary. Recording which payload commands the view
    // asks it to construct proves that the selected row cannot later dispatch
    // a false change, while an unselected row still receives its command.
    change: Emit(value => {
      requested_changes.push(value)
      @cmd.none
    }),
    title: "Provider",
    aria_label: "Provider",
    presentation: Setting,
  }
  ignore(control.render())
  @debug.assert_eq(requested_changes, ["custom"])
}
