///|
pub(all) enum Msg {
  Changed(String)
  Clear
  Move(Int32)
  Pick
}

///|
struct Model {
  query : String
  selected : Int32
} derive(Eq, Debug)

///|
pub fn Model::Model() -> Model {
  { query: "", selected: 0, }
}

///|
pub fn Model::query(self : Model) -> String {
  self.query
}

///|
pub fn Model::selected(self : Model, count : Int32) -> Int32 {
  self.selected.clamp(min=0, max=(count - 1).max(0))
}

///|
/// Selection refers to the current sidebar projection, never a cached result
/// from another device, account, or Chat/Work mode.
pub fn Model::update(
  self : Model,
  msg : Msg,
  results : Array[@conversation.Id],
) -> (@cmd.Cmd, Model, @conversation.Id?) {
  match msg {
    Changed(query) => (@cmd.none, { query, selected: 0, }, None)
    Clear => (clear_input(focus=true), Model(), None)
    Move(delta) => {
      guard !self.query.is_blank() && !results.is_empty() else {
        return (@cmd.none, self, None)
      }
      let selected = (self.selected(results.length()) + delta).clamp(
        min=0,
        max=results.length() - 1,
      )
      (reveal_result(results[selected]), { ..self, selected, }, None)
    }
    Pick =>
      if self.query.is_blank() {
        (@cmd.none, self, None)
      } else {
        (@cmd.none, self, results.get(self.selected(results.length())))
      }
  }
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with Debug::{to_repr}
