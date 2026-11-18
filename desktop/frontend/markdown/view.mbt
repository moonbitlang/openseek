///|
/// An HTML subtree with slots for the menus found while rendering Markdown.
enum View {
  Static(@html.Html)
  Parent(Array[View], (Array[@html.Html]) -> @html.Html)
  Menu(String, View)
}

///|
pub impl Eq for View with fn equal(left, right) {
  physical_equal(left, right)
}

///|
pub fn View::from_html(html : @html.Html) -> View {
  Static(html)
}

///|
pub fn View::compose(
  children : Array[View],
  render : (Array[@html.Html]) -> @html.Html,
) -> View {
  let static_children = []
  for child in children {
    guard child is Static(html) else { return Parent(children, render) }
    static_children.push(html)
  }
  Static(render(static_children))
}

///|
pub fn View::render(self : View, menus : Map[String, @html.Html]) -> @html.Html {
  match self {
    Static(html) => html
    Parent(children, render) =>
      render(children.map(child => child.render(menus)))
    Menu(key, content) =>
      match menus.get(key) {
        Some(menu) => menu
        None => content.render(menus)
      }
  }
}

///|
impl MarkdownNode for View with fn from_html(html) {
  View::from_html(html)
}

///|
impl MarkdownNode for View with fn compose(children, render) {
  View::compose(children, render)
}

///|
impl MarkdownNode for View with fn with_link_menu(content, menus, locale, link) {
  Menu(menus.add(locale, link, content), content)
}

///|
#derive(Debug)
priv struct LinkPresentation {
  target : @action_menu.ContextTarget
  revision : String
  children : Array[String]
  inline : Bool
}

///|
priv struct LinkMenu {
  key : String
  locale : @i18n.Locale
  presentation : LinkPresentation
  content : View
}

///|
impl Eq for LinkMenu with fn equal(left, right) {
  // A key includes the destination, presentation and duplicate occurrence.
  left.key == right.key
}

///|
/// The link menus produced by one rendering of a transcript block.
struct LinkMenus {
  items : Array[LinkMenu]
  occurrences : Map[String, Int32]
  prefix : String
  documents : Ref[Int32]
}

///|
pub impl Eq for LinkMenus with fn equal(left, right) {
  physical_equal(left, right)
}

///|
pub fn LinkMenus::LinkMenus(prefix : String) -> LinkMenus {
  { items: [], occurrences: Map([]), prefix, documents: Ref(0), }
}

///|
fn LinkMenus::next_document(self : LinkMenus) -> String {
  let index = self.documents.val
  self.documents.val += 1
  "\{self.prefix}-note-\{index}"
}

///|
fn LinkMenus::add(
  self : LinkMenus,
  locale : @i18n.Locale,
  presentation : LinkPresentation,
  content : View,
) -> String {
  let identity = Repr::Repr((locale.tag(), presentation)).to_string()
  let occurrence = self.occurrences.get(identity).unwrap_or(0)
  self.occurrences[identity] = occurrence + 1
  let key = "\{identity}:\{occurrence}"
  self.items.push({ key, locale, presentation, content, })
  key
}

///|
/// Keep each menu in a keyed branch for as long as its link exists. Source
/// cards can contain secondary link menus, so resolve inline menus first.
pub fn LinkMenus::component(
  self : @rabbita.Val[LinkMenus],
  prefix : String,
  context : @rabbita.Val[@action_menu.ContextInput],
  actions : @action_menu.ContextActions,
) -> @rabbita.Val[Map[String, @html.Html]] {
  let next = Ref(0)
  let revision = Ref(0)
  let policies = context.map(input => {
    revision.val += 1
    (revision.val, input)
  })
  let inline = self
    .map(menus => {
      @vector.from_array(menus.items.filter(menu => menu.presentation.inline))
    })
    .assoc_by(
      (key, menu) => {
        let id = "\{prefix}-\{next.val}"
        next.val += 1
        let content = menu.map(menu => menu.content.render(Map([])))
        link_menu_component(id, menu, policies, actions, content).map(html => {
          (key, html)
        })
      },
      by=menu => menu.key,
    )
    .map(items => Map::from_array(items.to_array()))
  let cards = self
    .map(menus => {
      @vector.from_array(menus.items.filter(menu => !menu.presentation.inline))
    })
    .assoc_by(
      (key, menu) => {
        let id = "\{prefix}-\{next.val}"
        next.val += 1
        let children = menu.map2(inline, (menu, inline) => {
          let children = Map([])
          for key in menu.presentation.children {
            if inline.get(key) is Some(html) {
              children[key] = html
            }
          }
          children
        })
        let content = menu.map2(children, (menu, children) => {
          menu.content.render(children)
        })
        link_menu_component(id, menu, policies, actions, content).map(html => {
          (key, html)
        })
      },
      by=menu => menu.key,
    )
  inline.map2(cards, (inline, cards) => {
    let result = inline.copy()
    for pair in cards {
      result[pair.0] = pair.1
    }
    result
  })
}

///|
fn link_menu_component(
  id : String,
  menu : @rabbita.Val[LinkMenu],
  policies : @rabbita.Val[(Int32, @action_menu.ContextInput)],
  actions : @action_menu.ContextActions,
  content : @rabbita.Val[@html.Html],
) -> @rabbita.Val[@html.Html] {
  menu
  .map2(policies, (menu, policy) => (menu, policy))
  .switch_by(
    value => {
      let (menu, (_, policy)) = value
      @action_menu.link_context(
        id,
        menu.locale,
        policy,
        menu.presentation.target,
        actions,
        content,
        inline=menu.presentation.inline,
      )
    },
    by=value => value.1.0.to_string(),
  )
  .map(
    // RUI binds native listeners to the trigger. Replace that DOM when a
    // different link takes this position in an otherwise unkeyed paragraph.
    menu => @html.span(style=["display:contents"], Map([(id, menu)])),
  )
}

///|
/// The parser omits source locations by default, so repeated parses can
/// compare the content of labels and source cards across streaming updates.
fn[T : Debug] markdown_revision(value : T) -> String {
  @debug.render(Repr::Repr(value), max_depth=@int.MAX_VALUE)
}
