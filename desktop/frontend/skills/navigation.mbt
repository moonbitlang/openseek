///|
pub(all) enum Detail {
  InstalledRef(String)
  MarketRef(String)
} derive(Eq)

///|
pub enum DetailResolution {
  Waiting
  Opened
  Missing
  Failed(String)
}

///|
pub fn State::detail(self : State) -> Detail? {
  let target = match self.preview {
    Closed => return None
    Loading(target~, ..) | Ready(target~, ..) | Failed(target~, ..) => target
  }
  Some(
    match target {
      Installed(item) => InstalledRef(item.id)
      Market(item) => MarketRef(source_label(item))
    },
  )
}

///|
pub fn State::open_detail(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  detail : Detail,
) -> (@cmd.Cmd, State, DetailResolution) {
  if self.detail() == Some(detail) {
    return (@cmd.none, self, Opened)
  }
  let message = match detail {
    InstalledRef(id) => {
      guard input.installed.iter().find_first(item => item.id == id)
        is Some(item) else {
        return (@cmd.none, self, Missing)
      }
      PreviewInstalled(item)
    }
    MarketRef(source) =>
      match self.catalog {
        Idle | Loading(..) => {
          let (cmd, next) = self.opening(emit, input)
          return (cmd, next, Waiting)
        }
        Failed(message) => return (@cmd.none, self, Failed(message))
        Ready(items) => {
          guard items.iter().find_first(item => source_label(item) == source)
            is Some(item) else {
            return (@cmd.none, self, Missing)
          }
          PreviewMarket(item)
        }
      }
  }
  let (command, state, _) = self.handle(emit, message, input)
  (command, state, Opened)
}

///|
pub extend Detail with Eq::{equal, not_equal}
