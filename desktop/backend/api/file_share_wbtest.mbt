///|
async test "file share RPC checks account authority before capturing workspace files" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="seekmoon-file-share-auth-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  @fs.write_file(root.join("auth.json").to_string(), share_account_fixture())
  let store = @auth.AuthStore::load(runtime_dir=root)
  let state = ApiState(engine="unused", auth=store)
  for (local_share, user_id) in [(false, "123"), (true, "other-account")] {
    let endpoint = endpoints(state, HostConnection(), local_share~)
      .iter()
      .find_first(endpoint => endpoint.name() == "fs.share_file")
      .unwrap()
    let payload : @protocol.FileSharePayload = {
      source: { root: None, path: "not-a-file", },
      idempotency_key: "a".repeat(64),
      authorization: LocalAccount(user_id~),
    }
    let reply : @protocol.SessionShareReply = @json.from_json(
      endpoint.invoke(payload.to_json()),
    )
    assert_true(
      reply is Failed(message~) &&
      message.contains(
        if local_share {
          "Sign-in changed"
        } else {
          "upload grant"
        },
      ),
    )
    assert_true(store.signed_in())
  }
}
