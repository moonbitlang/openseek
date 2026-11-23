///|
priv suberror AtomicWriteTestError {
  PartialWriteFailed
  CommitRejected
}

///|
async test "atomic text saves create and replace a file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/registry.json"
    @fsx.write_text_atomic(path, "first")
    assert_eq(@fs.read_text(path), "first")
    @fsx.write_text_atomic(path, "second")
    assert_eq(@fs.read_text(path), "second")
    assert_eq(@fs.readdir(dir, include_hidden=true), ["registry.json"])
  })
}

///|
#cfg(not(platform="windows"))
async test "atomic text saves leave a preexisting temporary symlink alone" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/registry.json"
    let victim = "\{dir}/victim.txt"
    let link = "\{path}.tmp"
    @fs.write_text(victim, "precious")
    @fs.symlink(link, target=victim)
    @fsx.write_text_atomic(path, "saved")
    assert_eq(@fs.read_text(path), "saved")
    assert_eq(@fs.read_text(victim), "precious")
    assert_true(@fs.kind(link, follow_symlink=false) is SymLink)
  })
}

///|
async test "an atomic text save leaves an occupied directory intact" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/registry.json"
    let kept = "\{path}/keep.txt"
    @fs.mkdir(path)
    @fs.write_text(kept, "precious")
    let refused = try {
      @fsx.write_text_atomic(path, "clobber")
      false
    } catch {
      _ => true
    }
    assert_true(refused)
    assert_eq(@fs.read_text(kept), "precious")
    assert_eq(@fs.readdir(dir, include_hidden=true), ["registry.json"])
  })
}

///|
async test "atomic writes expose the completed file only after the commit check" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/target"
    @fs.write_binary(path, b"old")
    @fsx.write_atomic(
      path,
      file => {
        file.write(b"\x00")
        assert_eq(@fs.read_binary(path), b"old")
        file.write(b"\xff")
      },
      replace=true,
      before_commit=() => assert_eq(@fs.read_binary(path), b"old"),
    )
    assert_eq(@fs.read_binary(path), b"\x00\xff")
    assert_eq(@fs.readdir(dir, include_hidden=true), ["target"])
  })
}

///|
async test "atomic writes preserve the old target after a partial write fails or is cancelled" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/target"
    @fs.write_binary(path, b"old")
    let failed = try {
      @fsx.write_atomic(
        path,
        file => {
          file.write(b"partial")
          raise PartialWriteFailed
        },
        replace=true,
      )
      false
    } catch {
      PartialWriteFailed => true
      error => raise error
    }
    assert_true(failed)
    assert_eq(@fs.read_binary(path), b"old")
    assert_eq(@fs.readdir(dir, include_hidden=true), ["target"])

    let wrote_partial = Ref(false)
    let cancelled = @async.with_timeout_opt(500, () => {
      @fsx.write_atomic(
        path,
        file => {
          file.write(b"partial")
          wrote_partial.val = true
          @async.sleep(60_000)
        },
        replace=true,
      )
    })
    assert_true(wrote_partial.val)
    assert_true(cancelled is None)
    assert_eq(@fs.read_binary(path), b"old")
    assert_eq(@fs.readdir(dir, include_hidden=true), ["target"])
  })
}

///|
async test "an atomic creation cannot replace a file created before the rename" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/target"
    let failed = try {
      @fsx.write_atomic(path, file => file.write(b"candidate"), replace=false, before_commit=() => {
        @fs.write_binary(path, b"other", create_mode=CreateNew)
      })
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(@fs.read_binary(path), b"other")
    assert_eq(@fs.readdir(dir, include_hidden=true), ["target"])
  })
}

///|
async test "a rejected commit check discards the prepared file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/target"
    @fs.write_binary(path, b"old")
    let failed = try {
      @fsx.write_atomic(path, file => file.write(b"candidate"), replace=true, before_commit=() => {
        raise CommitRejected
      })
      false
    } catch {
      CommitRejected => true
      error => raise error
    }
    assert_true(failed)
    assert_eq(@fs.read_binary(path), b"old")
    assert_eq(@fs.readdir(dir, include_hidden=true), ["target"])
  })
}
