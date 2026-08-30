///|
fn test_uri() -> @base_common.Uri {
  try! @base_common.Uri::parse("readonly-remote://workspace/src/main.mbt")
}

///|
test "crossing in-flight responses resolve their own requests" {
  let first = next_request_id("hover")
  let second = next_request_id("hover")
  let resolved : Array[String] = []
  pending_requests[first] = {
    resolve: packet => {
      resolved.push("first<-\{server_packet_request_id(packet)}")
    },
    cancellation_subscription: None,
    sent: false,
  }
  pending_requests[second] = {
    resolve: packet => {
      resolved.push("second<-\{server_packet_request_id(packet)}")
    },
    cancellation_subscription: None,
    sent: false,
  }
  // The second request answers before the first: ids keep them apart.
  assert_true(
    resolve_pending_response(
      HoverResult({
        id: second,
        uri: test_uri(),
        revision: "rev-2",
        hover: None,
      }),
    ),
  )
  assert_true(
    resolve_pending_response(
      HoverResult({
        id: first,
        uri: test_uri(),
        revision: "rev-1",
        hover: None,
      }),
    ),
  )
  debug_inspect(
    resolved,
    content=(
      #|["second<-hover-2", "first<-hover-1"]
    ),
  )
  // Each entry resolves exactly once.
  assert_false(
    resolve_pending_response(
      HoverResult({
        id: first,
        uri: test_uri(),
        revision: "rev-1",
        hover: None,
      }),
    ),
  )
  assert_eq(pending_requests.length(), 0)
}

///|
test "push packets without a pending id fall through" {
  assert_false(
    resolve_pending_response(
      DocumentChanged({
        id: "watch:readonly-remote://workspace/src/main.mbt",
        document: DocumentSnapshot(
          test_uri(),
          "main.mbt",
          "moonbit",
          "rev",
          "fn main {}",
        ),
      }),
    ),
  )
  assert_false(
    resolve_pending_response(
      RemoteError(ProtocolError(ProtocolProviderError, "boom")),
    ),
  )
}

///|
test "cancelling an in-flight request resumes once and consumes its late response" {
  let id = next_request_id("definition-cancel")
  let observed_provider_code = Ref("")
  let unexpected_packet = Ref(false)
  let subscription_disposals = Ref(0)
  pending_requests[id] = {
    resolve: packet => {
      match packet {
        RemoteError(error) => observed_provider_code.val = error.provider_code
        _ => unexpected_packet.val = true
      }
    },
    cancellation_subscription: Some(
      @base_common.Disposable::from(() => subscription_disposals.val += 1),
    ),
    sent: true,
  }

  cancel_pending_request(id)
  assert_eq(observed_provider_code.val, "Cancelled")
  assert_false(unexpected_packet.val)
  assert_eq(subscription_disposals.val, 1)
  assert_false(pending_requests.contains(id))
  assert_true(cancelled_request_ids.contains(id))

  // The server has no cancellation packet yet, so a result may still arrive.
  // Its tombstone must consume the packet rather than treating it as a push.
  assert_true(
    resolve_pending_response(
      DefinitionResult({
        id,
        uri: test_uri(),
        revision: "rev-late",
        locations: [],
      }),
    ),
  )
  assert_false(cancelled_request_ids.contains(id))
  assert_false(
    resolve_pending_response(
      DefinitionResult({
        id,
        uri: test_uri(),
        revision: "rev-late",
        locations: [],
      }),
    ),
  )
}

///|
test "send failure resumes every pending request without waiting for Closed" {
  let first = next_request_id("definition-send-failed")
  let second = next_request_id("preview-send-failed")
  let messages : Array[String] = []
  let subscription_disposals = Ref(0)
  let unexpected_packet = Ref(false)
  let pending = id => PendingProtocolRequest::{
    resolve: packet => {
      match packet {
        RemoteError(error) => messages.push("\{id}:\{error.message}")
        _ => unexpected_packet.val = true
      }
    },
    cancellation_subscription: Some(
      @base_common.Disposable::from(() => subscription_disposals.val += 1),
    ),
    sent: true,
  }
  pending_requests[first] = pending(first)
  pending_requests[second] = pending(second)
  cancelled_request_ids["old-tombstone"] = ()

  fail_pending_requests("WebSocket send failed.")

  assert_eq(pending_requests.length(), 0)
  assert_eq(cancelled_request_ids.length(), 0)
  assert_eq(subscription_disposals.val, 2)
  assert_false(unexpected_packet.val)
  assert_eq(messages.length(), 2)
  assert_true(messages.contains("\{first}:WebSocket send failed."))
  assert_true(messages.contains("\{second}:WebSocket send failed."))
}
