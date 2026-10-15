///|
const DialogId = "session-search-dialog"

///|
pub(all) enum Msg {
  Open(@interop.ChannelId)
  Close
  Changed(String)
  ToggleArchived
  Due(Int32)
  Loaded(Int32, Result[@protocol.SessionSearchReply, String])
  Move(Int32)
  Pick(Int32)
}

///|
priv enum Phase {
  Empty
  Waiting
  Loading
  Ready(@protocol.SessionSearchReply)
  Failed(String)
} derive(Eq)

///|
priv struct Search {
  channel : @interop.ChannelId
  query : String
  include_archived : Bool
  selected : Int32
  phase : Phase
} derive(Eq)

///|
struct Model {
  generation : Int32
  search : Search?
} derive(Eq)

///|
pub fn Model::Model() -> Model {
  { generation: 0, search: None, }
}

///|
pub fn Model::is_open(self : Model) -> Bool {
  self.search is Some(_)
}

///|
pub(all) struct Selection {
  channel : @interop.ChannelId
  hit : @protocol.SessionSearchHit
}

///|
pub fn Model::update(
  self : Model,
  emit : @cmd.Emit[Msg],
  msg : Msg,
) -> (@cmd.Cmd, Model, Selection?) {
  match msg {
    Open(channel) =>
      (
        @dialog.show(DialogId),
        {
          generation: self.generation + 1,
          search: Some({
            channel,
            query: "",
            include_archived: false,
            selected: 0,
            phase: Empty,
          }),
        },
        None,
      )
    Close =>
      (
        @dialog.close(DialogId),
        { search: None, generation: self.generation + 1, },
        None,
      )
    _ => {
      guard self.search is Some(search) else { return (@cmd.none, self, None) }
      match msg {
        Changed(query) => self.schedule(emit, { ..search, query, })
        ToggleArchived =>
          self.schedule(emit, {
            ..search,
            include_archived: !search.include_archived,
          })
        Due(generation) if generation == self.generation &&
          search.phase is Waiting => {
          let command = @cmd.perform(
            result => emit(Loaded(generation, result)),
            async fn() noraise {
              Ok(
                @interop.bridge_request(
                  search.channel,
                  @commands.session_search,
                  {
                    query: search.query.trim().to_owned(),
                    include_archived: search.include_archived,
                  },
                ),
              ) catch {
                error => Err(@interop.bridge_error_text(error))
              }
            },
          )
          (
            command,
            { ..self, search: Some({ ..search, phase: Loading, }), },
            None,
          )
        }
        Loaded(generation, result) if generation == self.generation &&
          search.phase is Loading =>
          (
            @cmd.none,
            {
              ..self,
              search: Some({
                ..search,
                phase: match result {
                  Ok(reply) => Ready(reply)
                  Err(error) => Failed(error)
                },
              }),
            },
            None,
          )
        Move(delta) => {
          guard search.phase is Ready(reply) && !reply.hits.is_empty() else {
            return (@cmd.none, self, None)
          }
          let selected = (search.selected + delta).clamp(
            min=0,
            max=reply.hits.length() - 1,
          )
          (
            reveal_result(selected),
            { ..self, search: Some({ ..search, selected, }), },
            None,
          )
        }
        Pick(index) => {
          guard search.phase is Ready(reply) &&
            reply.hits.get(index) is Some(hit) else {
            return (@cmd.none, self, None)
          }
          (
            @dialog.close(DialogId),
            { search: None, generation: self.generation + 1, },
            Some({ channel: search.channel, hit, }),
          )
        }
        _ => (@cmd.none, self, None)
      }
    }
  }
}

///|
fn Model::schedule(
  self : Model,
  emit : @cmd.Emit[Msg],
  search : Search,
) -> (@cmd.Cmd, Model, Selection?) {
  let generation = self.generation + 1
  let empty = search.query.is_blank()
  (
    if empty {
      @cmd.none
    } else {
      @cmd.delay(emit(Due(generation)), 250)
    },
    {
      generation,
      search: Some({
        ..search,
        selected: 0,
        phase: if empty {
          Empty
        } else {
          Waiting
        },
      }),
    },
    None,
  )
}

///|
pub extend Model with Eq::{equal, not_equal}
