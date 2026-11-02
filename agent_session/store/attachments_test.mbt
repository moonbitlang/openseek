///|
async test "image admission precedes append and migration is explicit" {
  let root = @fs.tmpdir(prefix="openseek-image-log-")
  defer @fs.rmdir(root, recursive=true)
  let home = root + "/user"
  let attachments = @attachments.AttachmentStore(home + "/attachments")
  let store = @store.SessionStore(root)
  let image = @agent_session.Image::from_bytes(b"\x89PNG\r\n\x1a\nfixture")
  let raw : @agent_session.Content = Content([Text("see"), Image(image)])
  let original = @agent_session.Session(
    SessionId("legacy"),
    system_prompt="system",
  ).append(User(UserMessage(raw)), unix_ms=1234)
  // Snapshot creation and ordinary append never change the supplied content.
  store.create(original)
  assert_eq(store.load(original.id()), original)
  let path = store.session_file(original.id())
  // Noncanonical header spacing/order exposes any snapshot rewrite on append.
  let legacy = " { \"system_prompt\": \"system\", \"version\": 1, \"id\": \"legacy\" } \n" +
    Json(original.events()[0]).stringify() +
    "\n"
  @fs.write_file(path, legacy, create_mode=CreateOrTruncate)
  assert_true(legacy.contains("\"data\":"))
  assert_eq(store.load(original.id()), original)
  assert_eq(@fs.read_file(path).text(), legacy)
  let admitted = attachments.admit(raw)
  let next = store.append(original, User(UserMessage(admitted)))
  assert_eq(next.events()[0], original.events()[0])
  assert_true(
    next.events()[1].item() is User(message) && message.content() == admitted,
  )
  assert_eq(store.load(next.id()), next)
  let stored = @fs.read_file(path).text()
  assert_true(
    @json.parse(stored.split("\n").collect()[0]) is { "version": 1, .. },
  )
  assert_eq(stored, legacy + Json(next.events()[1]).stringify() + "\n")
  let complete = store.append(next, Terminal(Finished("done")))
  let fork = store.fork(complete.id(), SessionId("fork"), system_prompt="fork")
  assert_eq(fork.events()[0], original.events()[0])
  assert_eq(store.load(fork.id()), fork)
  assert_true(
    @json.parse(
      @fs.read_file(store.session_file(fork.id())).text().split("\n").collect()[0],
    )
    is { "version": 1, .. },
  )
  // Only the explicit migration rewrites old inline bytes.
  let migrated = store.migrate_images(original.id(), attachments~)
  assert_eq(migrated.events()[0].sequence(), original.events()[0].sequence())
  assert_eq(migrated.events()[0].unix_ms(), original.events()[0].unix_ms())
  assert_true(
    migrated.events()[0].item() is User(message) &&
    message.content() == admitted,
  )
  assert_eq(migrated.events()[1], next.events()[1])
  assert_eq(store.migrate_images(original.id(), attachments~), migrated)
  let migrated_log = @fs.read_file(path).text()
  assert_false(migrated_log.contains("\"data\":"))
  assert_true(
    @json.parse(migrated_log.split("\n").collect()[0]) is { "version": 1, .. },
  )
  let reopened = @store.SessionStore(root)
  let appended = reopened.append(migrated, User(UserMessage(admitted)))
  assert_eq(reopened.load(appended.id()), appended)
}
