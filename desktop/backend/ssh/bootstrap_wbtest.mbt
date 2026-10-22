///|
test "SSH startup ignores shell banners and unrelated JSON before structured records" {
  let records = [
    "Welcome to the build host", "", "{not JSON}", "{\"motd\":\"Updates available\"}",
    "42", "{\"stage\":\"downloading\"}", "shell setup complete", "{\"stage\":\"installing\"}",
    "{\"port\":1234,\"instance\":\"server\",\"protocol\":1,\"extra\":true}\r",
  ].filter_map(line => bootstrap_record(line))
  assert_true(
    records
    is [
      Progress("downloading"),
      Progress("installing"),
      Endpoint(port=1234, instance="server"),
    ],
  )
}

///|
test "recognized SSH bootstrap records reject malformed endpoints and progress" {
  for
    line in [
      "{\"stage\":null}", "{\"port\":1234}", "{\"port\":1234,\"instance\":\"server\",\"protocol\":2}",
      "{\"port\":1234,\"instance\":null,\"protocol\":1}", "{\"port\":0,\"instance\":\"server\",\"protocol\":1}",
      "{\"port\":65536,\"instance\":\"server\",\"protocol\":1}", "{\"port\":1.5,\"instance\":\"server\",\"protocol\":1}",
    ] {
    let rejected = try {
      ignore(bootstrap_record(line))
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=line)
  }
}
