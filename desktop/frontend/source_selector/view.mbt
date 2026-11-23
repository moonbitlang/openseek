///|
/// The target of an operation, independent of how its owner reaches it.
/// Cloud is a Skills source, not an engine host.
#derive(Eq)
pub(all) enum Source {
  Device(@interop.ChannelId)
  Cloud
}

///|
fn Source::key(self : Source) -> String {
  match self {
    Device(channel) => "device:\{channel.uri_authority()}"
    Cloud => "cloud"
  }
}

///|
#derive(Eq)
pub(all) struct Choice {
  source : Source
  label : String
  title : String?
  disabled : Bool
}

///|
#derive(Eq)
pub(all) struct Input {
  label : String
  selected : Source
  choices : Array[Choice]
}

///|
pub fn local_label(locale : @i18n.Locale) -> String {
  match locale {
    English => "This computer"
    Spanish => "Este equipo"
    SimplifiedChinese => "此计算机"
    TraditionalChinese => "此電腦"
    Japanese => "このコンピュータ"
  }
}

///|
pub fn Input::render(
  self : Input,
  id~ : String,
  class~ : String,
  choose : @cmd.Emit[Source],
) -> @rabbita.Val[@html.Html] {
  let options = self.choices.map(choice => {
    @rui.select_option(
      value=choice.source.key(),
      label=choice.label,
      disabled=choice.disabled,
    )
  })
  let selected_label = self.choices
    .iter()
    .find_first(choice => choice.source == self.selected)
    .map_or(self.label, choice => choice.label)
  @rui.select(
    id~,
    class="source-selector \{class}",
    options~,
    default_value=self.selected.key(),
    placeholder=selected_label,
    on_value_change=@cmd.Emit(value => {
      if self.choices.iter().find_first(choice => choice.source.key() == value)
        is Some(choice) {
        choose(choice.source)
      } else {
        @cmd.none
      }
    }),
    render=scope => {
      @html.fragment([
        @rui.select_trigger(
          scope~,
          aria_label=self.label,
          class="setting-select-button field-surface",
        ),
        @rui.select_content(
          scope~,
          class="menu-surface",
          self.choices.map(choice => {
            @rui.select_item(
              scope~,
              value=choice.source.key(),
              disabled=choice.disabled,
              title?=choice.title,
              class="menu-option",
              choice.label,
            )
          }),
        ),
      ])
    },
  )
}

///|
/// RUI takes a snapshot of its options at mount time. Rebuild only when
/// the source list or selection changes, not when the dialog loads a folder.
pub fn component(
  input : @rabbita.Val[Input?],
  id~ : String,
  class~ : String,
  choose : @cmd.Emit[Source],
) -> @rabbita.Val[@html.Html] {
  input.switch_by(
    input => {
      match input {
        Some(input) => input.render(id~, class~, choose)
        None => @rabbita.Val::constant(@html.nothing)
      }
    },
    by=input => {
      match input {
        None => ""
        Some(input) => {
          let choices = input.choices.map(choice => {
            let key : Json = [
              choice.source.key(),
              choice.label,
              choice.title.map_or(Json::null(), Json::string),
              choice.disabled,
            ]
            key
          })
          let key : Json = [
            input.label,
            input.selected.key(),
            Json::array(choices),
          ]
          key.stringify()
        }
      }
    },
  )
}
