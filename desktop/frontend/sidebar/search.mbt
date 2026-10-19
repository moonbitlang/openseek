///|
fn matching_rows(
  rows : Array[@conversation.Input],
  query : String,
) -> Array[@conversation.Input] {
  rows.filter_map(row => {
    let children = matching_rows(row.children, query)
    if row.id().source() != @conversation.CodexDraft &&
      (row.label.to_lower().contains(query) || !children.is_empty()) {
      Some({ ..row, children, })
    } else {
      None
    }
  })
}

///|
/// Filter the complete catalog before the project component applies its
/// compact preview. Folder identities and normal row actions remain intact.
pub fn Input::filtered(self : Input) -> Input {
  let query = self.search.query().trim().to_owned().to_lower()
  if query.is_empty() {
    return self
  }
  let sections = self.sections.filter_map(section => {
    let entries = section.entries.filter_map(entry => {
      match entry {
        @section.Project(project) => {
          let conversations = matching_rows(project.conversations, query)
          if conversations.is_empty() {
            None
          } else {
            Some(@section.Project({ ..project, conversations, }))
          }
        }
        @section.Conversation(row) =>
          matching_rows([row], query)
          .get(0)
          .map(row => @section.Conversation(row))
        @section.Placeholder(_) => None
      }
    })
    if entries.is_empty() {
      None
    } else {
      Some({ ..section, entries, })
    }
  })
  { ..self, sections, }
}

///|
fn push_results(
  results : Array[@conversation.Id],
  rows : Array[@conversation.Input],
  query : String,
) -> Unit {
  for row in rows {
    if row.openable && row.label.to_lower().contains(query) {
      results.push(row.id())
    }
    push_results(results, row.children, query)
  }
}

///|
/// Keyboard order is the displayed folder/row order, across all sources.
pub fn Input::search_results(self : Input) -> Array[@conversation.Id] {
  let results : Array[@conversation.Id] = []
  let query = self.search.query().trim().to_owned().to_lower()
  if query.is_empty() {
    return results
  }
  for section in self.sections {
    for entry in section.entries {
      match entry {
        @section.Project(project) =>
          push_results(results, project.conversations, query)
        @section.Conversation(row) => push_results(results, [row], query)
        @section.Placeholder(_) => ()
      }
    }
  }
  results
}
