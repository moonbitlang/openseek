///|
#derive(Eq)
pub(all) struct ContextMenuTrigger {
  class : String?
  title : String?
  content : @html.Html
}

///|
/// Keep the context menu mounted while its trigger follows the input.
/// RUI 0.5.0 binds the trigger and positioning anchor by DOM ID.
pub fn context_menu_with_input(
  input~ : @rabbita.Val[ContextMenuTrigger],
  id~ : String,
  tabindex~ : Int32 = 0,
  on_open_change? : @cmd.Emit[Bool],
  trigger_attrs? : @html.Attrs,
  trigger_style~ : Array[String] = [],
  popup : (@rui.ContextMenuScope) -> @html.Html,
) -> @rabbita.Val[@html.Html] {
  let (open, set_open) = @rabbita.create_variable(false)
  let menu = @rui.context_menu(
    id~,
    on_open_change=visible => {
      @cmd.batch([
        set_open(_ => visible),
        on_open_change.map_or(@cmd.none, emit => emit(visible)),
      ])
    },
    popup,
  )
  let trigger_id = id + "-trigger"
  input.view3(menu, open, (trigger, menu, open) => {
    let attrs = trigger_attrs.map_or(@html.Attrs::build(), attrs => attrs.copy())
    ignore(
      attrs
      .data_set("slot", "context-menu-trigger")
      .data_set("state", if open { "open" } else { "closed" })
      .data_set(if open { "open" } else { "closed" }, "")
      .tabindex(tabindex)
      .aria_haspopup("menu")
      .aria_expanded(open.to_string())
      .aria_controls(id + "-content"),
    )
    @html.fragment([
      @html.div(
        id=trigger_id,
        class?=trigger.class,
        title?=trigger.title,
        style=["box-sizing:border-box", "position:relative", ..trigger_style],
        attrs~,
        [
          @html.div(style=["display:contents"], trigger.content),
          @rui.popover_anchor(
            id=trigger_id + "-point",
            style=["position:absolute;width:0;height:0;pointer-events:none"],
            attrs=@html.Attrs::build().aria_hidden("true"),
            @html.nothing,
          ),
        ],
      ),
      menu,
    ])
  })
}
