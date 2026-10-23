///|
/// Search durable titles on this host. A failed store is reported alongside
/// usable matches rather than being treated as an empty store.
pub async fn search_sessions(
  payload : @protocol.SessionSearchPayload,
) -> @protocol.SessionSearchReply {
  let query = payload.query.trim().to_owned().to_lower()
  guard !query.is_empty() else {
    return { hits: [], errors: [], has_more: false, }
  }
  let hits : Array[@protocol.SessionSearchHit] = []
  let errors : Array[String] = []
  for
    archived in (if payload.include_archived { [false, true] } else { [false] }) {
    let reply = if archived { archived_sessions() } else { list_sessions() }
    for group in reply.groups {
      if !group.error.is_empty() {
        errors.push("\{group.workspace}: \{group.error}")
        continue
      }
      for entry in group.sessions {
        // A side chat carries its conversation's title and is reached
        // through that conversation; it is never a result of its own.
        if @protocol.side_chat_parent(entry.id) is Some(_) {
          continue
        }
        let title = entry.title.unwrap_or("")
        if title.to_lower().contains(query) {
          hits.push({
            session: entry.id,
            workspace: group.workspace,
            title,
            archived,
            updated_at_ms: entry.updated_at_ms,
          })
        }
      }
    }
  }
  hits.sort_by((a, b) => {
    let order = b.updated_at_ms
      .unwrap_or(0)
      .compare(a.updated_at_ms.unwrap_or(0))
    if order != 0 {
      order
    } else {
      let workspace = a.workspace.compare(b.workspace)
      if workspace != 0 {
        workspace
      } else {
        a.session.compare(b.session)
      }
    }
  })
  {
    hits: hits[:hits.length().min(100)].to_owned(),
    errors,
    has_more: hits.length() > 100,
  }
}
