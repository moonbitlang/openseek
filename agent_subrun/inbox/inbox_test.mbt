///|
async test "a post reaches the reader once, in order" {
  let dir = @fs.tmpdir(prefix="openseek-inbox-")
  defer @fs.rmdir(dir, recursive=true)
  // The receiver's own directory does not exist until it opens the inbox.
  let path = "\{dir}/sessions/p-sr-1/inbox.jsonl"
  let reader = @inbox.Reader(path)
  let first = @inbox.Message(from="p", text="look at src/ first")
  // Not open yet: nothing to take, and nothing is written.
  assert_eq(reader.take(), [])
  assert_false(@inbox.post(path, first))
  assert_true(@inbox.read(path) is None)
  assert_false(@fs.exists("\{dir}/sessions"))
  @inbox.open(path)
  assert_true(@inbox.read(path) is Some({ messages: [], unreadable: 0, }))
  let second = @inbox.Message(from="p", text="two\nlines — and “quotes”")
  assert_true(first.id != second.id)
  assert_true(@inbox.post(path, first))
  assert_true(@inbox.post(path, second))
  assert_eq(reader.take(), [first, second])
  assert_eq(reader.take(), [])
  let third = @inbox.Message(from="p", text="and tests")
  assert_true(@inbox.post(path, third))
  assert_eq(reader.take(), [third])
  // Re-opening an inbox keeps what was posted.
  @inbox.open(path)
  assert_true(
    @inbox.read(path) is Some({ messages: [_, _, _], unreadable: 0, }),
  )
}

///|
async test "a damaged line costs only itself" {
  let dir = @fs.tmpdir(prefix="openseek-inbox-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/inbox.jsonl"
  @inbox.open(path)
  let before = @inbox.Message(from="p", text="whole")
  assert_true(@inbox.post(path, before))
  // A write that died part-way, inside a multi-byte character.
  let file = @fs.open(path, mode=WriteOnly, append=true)
  file.write(b"{\"v\":1,\"id\":\"x\",\"from\":\"p\",\"text\":\"caf\xc3")
  file.close()
  // The torn tail is not a message yet, and does not spoil what precedes it.
  assert_true(@inbox.read(path) is Some({ messages: [_], unreadable: 0, }))
  // The next post closes it off: one unreadable line, and the new message
  // is intact.
  let after = @inbox.Message(from="p", text="after the damage")
  assert_true(@inbox.post(path, after))
  assert_eq(
    @inbox.read(path),
    Some({ messages: [before, after], unreadable: 1, }),
  )
}

///|
async test "a record this build does not know is not delivered" {
  let dir = @fs.tmpdir(prefix="openseek-inbox-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/inbox.jsonl"
  @fs.write_file(
    path,
    (
      #|{"v":2,"id":"a","from":"p","kind":"instruction","text":"newer format"}
      #|{"v":1,"id":"b","from":"p-sr-2","kind":"note","text":"a kind from later"}
      #|{"text":"no envelope"}
      #|
    ),
    create_mode=CreateNew,
  )
  assert_eq(@inbox.read(path), Some({ messages: [], unreadable: 3, }))
  assert_eq(@inbox.Reader(path).take(), [])
}

///|
async test "two senders' messages with one id stay two messages" {
  let dir = @fs.tmpdir(prefix="openseek-inbox-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/inbox.jsonl"
  @inbox.open(path)
  let ours : @inbox.Message = { id: "m1", from: "p", text: "from the parent", }
  let theirs : @inbox.Message = {
    id: "m1",
    from: "q",
    text: "from a stranger",
  }
  assert_true(ours.receipt() != theirs.receipt())
  assert_true(@inbox.post(path, ours))
  assert_true(@inbox.post(path, theirs))
  assert_eq(@inbox.Reader(path).take(), [ours, theirs])
}
