///|
async test "preview caches isolate SSH hosts and preserve content after a refused refresh" {
  let a = PreviewCache(@fs.tmpdir(prefix="ssh-preview-a-"))
  let b = PreviewCache(@fs.tmpdir(prefix="ssh-preview-b-"))
  defer a.close()
  defer b.close()
  let first : @protocol.FilePreviewContent = {
    media_type: "application/pdf",
    data_base64: @base64.encode(b"%PDF-first"),
  }
  let second : @protocol.FilePreviewContent = {
    media_type: "application/pdf",
    data_base64: @base64.encode(b"%PDF-second"),
  }
  let path_a = a.load("/same/report.pdf", () => first)
  let path_b = b.load("/same/report.pdf", () => second)
  assert_true(path_a != path_b)
  assert_eq(@fs.read_file(path_a).binary(), b"%PDF-first")
  assert_eq(@fs.read_file(path_b).binary(), b"%PDF-second")
  let refused = try {
    ignore(a.load("/same/report.pdf", () => raise SshError("disconnected")))
    false
  } catch {
    SshError(_) => true
    error => raise error
  }
  assert_true(refused)
  assert_eq(@fs.read_file(path_a).binary(), b"%PDF-first")
  assert_eq(a.load("/same/report.pdf", () => second), path_a)
  assert_eq(@fs.read_file(path_a).binary(), b"%PDF-second")
  let image : @protocol.FilePreviewContent = {
    media_type: "image/png",
    data_base64: @base64.encode(b"\x89PNG\r\n\x1a\n"),
  }
  let changed_format = a.load("/same/report.pdf", () => image)
  assert_true(changed_format != path_a && changed_format.has_suffix(".png"))
  assert_eq(@fs.read_file(path_a).binary(), b"%PDF-second")
}

///|
async test "preview cache enforces aggregate capacity and rejects disguised data" {
  let cache = PreviewCache(@fs.tmpdir(prefix="ssh-preview-budget-"), limit=20)
  defer cache.close()
  let content : @protocol.FilePreviewContent = {
    media_type: "application/pdf",
    data_base64: @base64.encode(b"%PDF-12345"),
  }
  let first = cache.load("/a", () => content)
  let second = cache.load("/b", () => content)
  let full = try {
    ignore(cache.load("/c", () => content))
    false
  } catch {
    SshError(_) => true
    error => raise error
  }
  assert_true(full)
  assert_eq(cache.load("/a", () => content), first)
  let invalid : @protocol.FilePreviewContent = {
    media_type: "image/png",
    data_base64: @base64.encode(b"<html>active content</html>"),
  }
  let refused = try {
    ignore(cache.load("/a", () => invalid))
    false
  } catch {
    SshError(_) => true
    error => raise error
  }
  assert_true(refused)
  assert_eq(@fs.read_file(first).binary(), b"%PDF-12345")
  assert_eq(@fs.read_file(second).binary(), b"%PDF-12345")
}

///|
async test "closing preview cache waits for its writer and rejects future reads" {
  let directory = @fs.tmpdir(prefix="ssh-preview-close-")
  let cache = PreviewCache(directory)
  let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let finish : @async.Queue[Unit] = Queue(kind=Blocking(1))
  @async.with_task_group(group => {
    let writer = group.spawn(() => {
      cache.load("/document.pdf", () => {
        entered.put(())
        finish.get()
        {
          media_type: "application/pdf",
          data_base64: @base64.encode(b"%PDF-document"),
        }
      })
    })
    entered.get()
    let closing = group.spawn(() => cache.close())
    finish.put(())
    ignore(writer.wait())
    closing.wait()
  })
  assert_false(@fs.exists(directory))
  let refused = try {
    ignore(cache.load("/after.pdf", () => fail("closed cache must not fetch")))
    false
  } catch {
    SshError(_) => true
    error => raise error
  }
  assert_true(refused)
}
