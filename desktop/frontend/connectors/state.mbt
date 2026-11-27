///|
#derive(Eq)
priv enum Operation {
  Idle
  Loading
  Starting(String)
  Waiting(String, @protocol.ConnectorAuthorization)
  Changing(String)
}

///|
#derive(Eq)
struct State {
  rows : @vector.Vector[@protocol.ConnectorInfo]
  loaded : Bool
  operation : Operation
  epoch : Int32
  error : String?
}

///|
pub fn State::empty() -> State {
  {
    rows: @vector.Vector::empty(),
    loaded: false,
    operation: Idle,
    epoch: 0,
    error: None,
  }
}

///|
pub(all) enum Msg {
  Refresh
  Connect(String)
  Disconnect(String)
  Cancel
  Poll(Int32, String, String)
  Received(Int32, String?, @protocol.ConnectorReply)
}

///|
fn request(
  emit : @cmd.Emit[Msg],
  operation : String,
  epoch : Int32,
  id? : String,
  attempt? : String,
  cloud_token? : String,
) -> @cmd.Cmd {
  @cmd.perform(reply => emit(Received(epoch, id, reply)), () => {
    try {
      if cloud_token is Some(token) {
        @json.from_json(
          @cloud_client.request(
            @cloud_client.CloudOrigin,
            "/v1/me/connectors/" + operation,
            Post,
            token~,
            body={ "id": Json(id.unwrap_or("")), "attempt": Json(attempt) },
          ),
        )
      } else if operation == "list" {
        @interop.bridge_request(
          Local,
          @commands.connectors_list,
          @protocol.NoPayload,
        )
      } else {
        let command = match operation {
          "connect" => @commands.connectors_connect
          "poll" => @commands.connectors_poll
          "cancel" => @commands.connectors_cancel
          _ => @commands.connectors_disconnect
        }
        @interop.bridge_request(Local, command, {
          id: id.unwrap_or(""),
          attempt,
        })
      }
    } catch {
      error =>
        {
          connectors: [],
          authorization: None,
          error: Some(@interop.bridge_error_text(error)),
        }
    }
  })
}

///|
pub fn update(
  emit : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
  cloud_token? : String,
  open_external~ : (String) -> @cmd.Cmd,
) -> (@cmd.Cmd, State) {
  match msg {
    Refresh => {
      if !(state.operation is Idle) {
        return (@cmd.none, state)
      }
      let epoch = state.epoch + 1
      (
        request(emit, "list", epoch, cloud_token?),
        { ..state, epoch, operation: Loading, error: None, },
      )
    }
    Connect(id) | Disconnect(id) => {
      guard state.operation is Idle else { return (@cmd.none, state) }
      let epoch = state.epoch + 1
      let connecting = msg is Connect(_)
      (
        request(
          emit,
          if connecting {
            "connect"
          } else {
            "disconnect"
          },
          epoch,
          id~,
          cloud_token?,
        ),
        {
          ..state,
          epoch,
          error: None,
          operation: if connecting {
            Starting(id)
          } else {
            Changing(id)
          },
        },
      )
    }
    Cancel => {
      guard state.operation is Waiting(id, authorization) else {
        return (@cmd.none, state)
      }
      let epoch = state.epoch + 1
      (
        request(
          emit,
          "cancel",
          epoch,
          id~,
          attempt=authorization.attempt,
          cloud_token?,
        ),
        { ..state, epoch, operation: Changing(id), error: None, },
      )
    }
    Poll(epoch, id, attempt) => {
      guard epoch == state.epoch && state.operation is Waiting(_, _) else {
        return (@cmd.none, state)
      }
      (request(emit, "poll", epoch, id~, attempt~, cloud_token?), state)
    }
    Received(epoch, id, reply) => {
      guard epoch == state.epoch else { return (@cmd.none, state) }
      if reply.error is Some(error) {
        return (@cmd.none, { ..state, operation: Idle, error: Some(error), })
      }
      let rows = @vector.from_array(reply.connectors)
      if reply.authorization is Some(authorization) && id is Some(id) {
        (
          @cmd.batch([
            @cmd.delay(emit(Poll(epoch, id, authorization.attempt)), 1000),
            if state.operation is Starting(started) && started == id {
              open_external(authorization.url)
            } else {
              @cmd.none
            },
          ]),
          {
            ..state,
            rows,
            loaded: true,
            operation: Waiting(id, authorization),
            error: None,
          },
        )
      } else {
        (
          @cmd.none,
          { ..state, rows, loaded: true, operation: Idle, error: None, },
        )
      }
    }
  }
}

///|
pub extend State with Eq::{equal, not_equal}

///|
/// Whether a successful list reply confirms that there are no connectors.
pub fn State::is_empty(self : State) -> Bool {
  self.loaded &&
  self.rows.is_empty() &&
  self.error is None &&
  self.operation is Idle
}
