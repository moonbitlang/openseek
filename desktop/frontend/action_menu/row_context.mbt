///|
pub(all) struct RowContext {
  target : String
  revision : String
  content : @html.Html
  definition : Definition?
}

///|
pub impl Eq for RowContext with fn equal(a, b) {
  physical_equal(a, b)
}

///|
pub extend RowContext with Eq::{equal, not_equal}

///|
/// The visible content is the native trigger. A changed content revision
/// replaces the menu instance; unrelated trailing status and child rows do not.
pub fn row_context(
  input : @rabbita.Val[RowContext],
) -> @rabbita.Val[@html.Html] {
  input.switch_by(
    input => {
      guard input.definition is Some(definition) else {
        return @rabbita.Val::constant(input.content)
      }
      let (_, emit) = @rabbita.create_state_with_init(
        init=_ => (false, @cmd.none),
        update=(_, visible : Bool, _) => (visible, @cmd.none),
        subscriptions=(visible, _) => {
          if visible {
            @dismiss.on_back("row-context-back", level=TopLayer, _ => {
              @rui.popover_close(input.target + ":context-content")
            })
          } else {
            @sub.none
          }
        },
      )
      @rui.context_menu(id=input.target + ":context", on_open_change=emit, scope => {
        @html.fragment([
          @rui.context_menu_trigger(
            scope,
            tabindex=-1,
            class="sidebar-context-trigger",
            input.content,
          ),
          @rui.context_menu_content(
            scope,
            aria_label=definition.label,
            class="action-menu",
            definition.entries.map(entry => {
              match entry {
                Separator => @rui.context_menu_separator()
                Action(item) =>
                  @rui.context_menu_item(
                    scope,
                    disabled=!item.enabled,
                    destructive=item.destructive,
                    on_select=item.command,
                    class="action-menu-item",
                    title=item.title,
                    item_children(item),
                  )
              }
            }),
          ),
        ])
      })
    },
    by=input => input.revision,
  )
}
