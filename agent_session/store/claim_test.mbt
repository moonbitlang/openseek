///|
async fn claimed(store : @store.SessionStore, id : String) -> String {
  guard store.claim(SessionId(id)) is Claimed(token~) else {
    fail("expected \{id} to be claimed")
  }
  token
}

///|
/// The message of the failure `body` raises, without the source location
/// `fail` prefixes it with.
async fn refusal(body : async () -> Unit) -> String {
  try body() catch {
    Failure(message) =>
      match message.split("FAILED: ").last() {
        Some(text) => text.to_owned()
        None => message
      }
    error => "\{error}"
  } noraise {
    _ => fail("expected a refusal")
  }
}

///|
async test "a claim creates the session directory once" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let token = claimed(store, "p-sr-1")
  assert_eq(token.length(), 32)
  assert_true(store.exists(SessionId("p-sr-1")))
  // Only the token's digest is on disk: reading the claim does not give it.
  let recorded = @fs.read_file("\{store.root()}/sessions/p-sr-1/claim.json").text()
  assert_false(recorded.contains(token))
  assert_true(store.claim(SessionId("p-sr-1")) is Taken)
  // The claim keeps its id taken in the listing the ordinal floor reads.
  assert_eq(store.list().map(id => id.value()), ["p-sr-1"])
}

///|
async test "concurrent claims on one id have exactly one winner" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let outcomes : Array[Bool] = []
  @async.with_task_group(group => {
    for _ in 0..<8 {
      group.spawn_bg(() => {
        outcomes.push(store.claim(SessionId("p-sr-2")) is Claimed(_))
      })
    }
  })
  assert_eq(outcomes.filter(won => won).length(), 1)
}

///|
async test "a claim is accepted once, with its token, and then records" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("p-sr-3")
  let token = claimed(store, "p-sr-3")
  inspect(
    refusal(() => store.accept_claim(id, wrong_token)),
    content="session p-sr-3 was claimed for another run",
  )
  store.accept_claim(id, token)
  inspect(
    refusal(() => store.accept_claim(id, token)),
    content="session p-sr-3 holds no claim; it was accepted already",
  )
  // Accepted, the directory is an ordinary new session.
  let session = @agent_session.Session(id, system_prompt="system").append(
    User(UserMessage(Content([Text("hello")]))),
  )
  store.create(session)
  assert_eq(store.load(id).id().value(), "p-sr-3")
}

///|
async test "a claim is refused once its session has records" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("p-sr-4")
  let token = claimed(store, "p-sr-4")
  @fs.write_file(session_file(store, "p-sr-4"), "", create_mode=CreateNew)
  inspect(
    refusal(() => store.accept_claim(id, token)),
    content="session p-sr-4 already has records of its own",
  )
}

///|
async test "a claim is refused for a session nobody claimed" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  inspect(
    refusal(() => store.accept_claim(SessionId("p-sr-5"), wrong_token)),
    content="session p-sr-5 was not claimed: it does not exist",
  )
  @fs.mkdir("\{store.root()}/sessions/p-sr-6", recursive=true)
  inspect(
    refusal(() => store.accept_claim(SessionId("p-sr-6"), wrong_token)),
    content="session p-sr-6 holds no claim; it was accepted already",
  )
}

///|
async test "a reader's session lock does not block acceptance" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("p-sr-7")
  let token = claimed(store, "p-sr-7")
  @fs.write_file(
    "\{store.root()}/sessions/p-sr-7/session.lock",
    "",
    create_mode=CreateNew,
  )
  store.accept_claim(id, token)
}

///|
async test "of two runs presenting one token, one is accepted" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("p-sr-8")
  let token = claimed(store, "p-sr-8")
  let accepted : Array[Bool] = []
  @async.with_task_group(group => {
    for _ in 0..<4 {
      group.spawn_bg(() => {
        accepted.push(
          try store.accept_claim(id, token) catch {
            _ => false
          } noraise {
            _ => true
          },
        )
      })
    }
  })
  assert_eq(accepted.filter(won => won).length(), 1)
}

///|
/// The shape of a real token, but not the one any claim recorded.
let wrong_token : String = "00000000000000000000000000000000"

///|
/// A claimed child that has not recorded anything is a reserved id, not a
/// session: listings leave it out, pending or accepted, until its first
/// record; then it lists like any session and its marker is gone.
async test "listings leave out claims until their first record" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let pending = claimed(store, "p-sr-9")
  ignore(pending)
  let id = @agent_session.SessionId("p-sr-10")
  store.accept_claim(id, claimed(store, "p-sr-10"))
  // A husk with nothing claimed in it stays visible, as before.
  @fs.mkdir("\{store.root()}/sessions/husk", recursive=true)
  assert_eq(store.listings().map(row => row.id().value()), ["husk"])
  let session = @agent_session.Session(id, system_prompt="system")
  let session = store.append(session, User(UserMessage(Content([Text("hi")]))))
  ignore(session)
  store.settle_claim(id)
  assert_false(@fs.exists("\{store.root()}/sessions/p-sr-10/claim.accepted"))
  assert_eq(store.listings().map(row => row.id().value()), ["p-sr-10", "husk"])
  // Settling twice is harmless.
  store.settle_claim(id)
}
