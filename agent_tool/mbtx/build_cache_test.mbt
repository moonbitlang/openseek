///|
/// The session cache is where a wired job dir (or lab) lets wasm builds keep
/// their compiled dependencies between calls. Every test here binds a job dir
/// so the cache is active; the tests in `mbtx_test.mbt` that build a bare
/// definition exercise the no-owner path, which stays a cold per-call build.

///|
/// Negative control for the shared snippet directory: every inline snippet
/// builds at the SAME artifact path, so a later call must never run an
/// earlier call's program — the trap a shared build dir sets without the
/// per-call copy.
async test "cache: consecutive inline snippets each run their own program" {
  @vfs.with_tmpdir(prefix="mbtx-cache-snippets-", ws => {
    let spill = "\{ws}/spill"
    @fs.mkdir(spill)
    let definition = @mbtx.definition(workspace_root=ws, job_dir=spill)
    let alice = dispatch(definition, {
      "source": "fn main { println(\"I AM ALICE\") }",
    })
    assert_false(alice.is_error, msg=alice.content)
    assert_true(alice.content.contains("I AM ALICE"))
    let bob = dispatch(definition, {
      "source": "fn main { println(\"I AM BOB\") }",
    })
    assert_false(bob.is_error, msg=bob.content)
    assert_true(bob.content.contains("I AM BOB"))
    assert_false(bob.content.contains("ALICE"))
    // An exact repeat is the one inline case moon can serve as a no-op.
    let again = dispatch(definition, {
      "source": "fn main { println(\"I AM ALICE\") }",
    })
    assert_true(again.content.contains("I AM ALICE"))
    // One shared directory holds the snippet's build; the per-call dirs are
    // reclaimed as before, so nothing but the cache survives the calls.
    assert_true(@fs.exists("\{spill}/mbtx-cache/snippet/gen-0/_build"))
    assert_eq(
      @fs.read_file("\{spill}/mbtx-cache/snippet/gen-0/snippet.mbtx").text(),
      "fn main { println(\"I AM ALICE\") }",
    )
    assert_eq(@fs.readdir(spill), ["mbtx-cache"])
    assert_eq(@fs.readdir("\{spill}/mbtx-cache"), ["snippet"])
  })
}

///|
/// A named script gets a directory of its own, keyed by its resolved path,
/// and keeps it across calls; editing the script rebuilds in place.
async test "cache: a named script builds in one keyed dir and follows edits" {
  @vfs.with_tmpdir(prefix="mbtx-cache-named-", ws => {
    let spill = "\{ws}/spill"
    @fs.mkdir(spill)
    @fs.mkdir("\{ws}/scripts")
    let definition = @mbtx.definition(workspace_root=ws, job_dir=spill)
    let v1 = "fn main { println(\"hello v1\") }"
    @fs.write_file("\{ws}/scripts/hello.mbtx", v1, create_mode=CreateOrTruncate)
    let first = dispatch(definition, { "filename": "scripts/hello.mbtx" })
    assert_false(first.is_error, msg=first.content)
    assert_true(first.content.contains("hello v1"))
    let second = dispatch(definition, { "filename": "scripts/hello.mbtx" })
    assert_true(second.content.contains("hello v1"))
    // An inline snippet in between must not disturb the named script's dir.
    let inline = dispatch(definition, {
      "source": "fn main { println(\"inline\") }",
    })
    assert_true(inline.content.contains("inline"))
    let keyed = @fs.readdir("\{spill}/mbtx-cache").filter(name => {
      name.has_prefix("named-hello.mbtx-")
    })
    assert_eq(keyed.length(), 1)
    let stage = "\{spill}/mbtx-cache/\{keyed[0]}/gen-0"
    assert_eq(@fs.read_file("\{stage}/snippet.mbtx").text(), v1)
    assert_true(@fs.exists("\{stage}/_build"))
    // Edit the script: the same directory is rebuilt, not a new one.
    let v2 = "fn main { println(\"hello v2\") }"
    @fs.write_file("\{ws}/scripts/hello.mbtx", v2, create_mode=CreateOrTruncate)
    let third = dispatch(definition, { "filename": "scripts/hello.mbtx" })
    assert_true(third.content.contains("hello v2"), msg=third.content)
    assert_false(third.content.contains("v1"))
    assert_eq(@fs.read_file("\{stage}/snippet.mbtx").text(), v2)
    assert_eq(
      @fs.readdir("\{spill}/mbtx-cache")
      .filter(name => name.has_prefix("named-"))
      .length(),
      1,
    )
  })
}

///|
/// Two scripts that share a basename but not a path are different programs
/// and must not share a build directory.
async test "cache: same basename at different paths keys separately" {
  @vfs.with_tmpdir(prefix="mbtx-cache-basename-", ws => {
    let spill = "\{ws}/spill"
    @fs.mkdir(spill)
    @fs.mkdir("\{ws}/a")
    @fs.mkdir("\{ws}/b")
    @fs.write_file(
      "\{ws}/a/run.mbtx",
      "fn main { println(\"from a\") }",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{ws}/b/run.mbtx",
      "fn main { println(\"from b\") }",
      create_mode=CreateOrTruncate,
    )
    let definition = @mbtx.definition(workspace_root=ws, job_dir=spill)
    let a = dispatch(definition, { "filename": "a/run.mbtx" })
    let b = dispatch(definition, { "filename": "b/run.mbtx" })
    let a_again = dispatch(definition, { "filename": "a/run.mbtx" })
    assert_true(a.content.contains("from a"), msg=a.content)
    assert_true(b.content.contains("from b"), msg=b.content)
    assert_true(a_again.content.contains("from a"), msg=a_again.content)
    assert_eq(
      @fs.readdir("\{spill}/mbtx-cache")
      .filter(name => name.has_prefix("named-run.mbtx-"))
      .length(),
      2,
    )
  })
}

///|
/// Build diagnostics name the program as the model knows it, never the cache
/// directory the compiler actually read.
async test "cache: build errors are reported against the source, not the cache" {
  @vfs.with_tmpdir(prefix="mbtx-cache-diag-", ws => {
    let spill = "\{ws}/spill"
    @fs.mkdir(spill)
    let definition = @mbtx.definition(workspace_root=ws, job_dir=spill)
    let out = dispatch(definition, {
      "source": "fn main { let x : Int = \"not an int\" }",
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("BUILD failed"), msg=out.content)
    assert_false(out.content.contains("mbtx-cache"), msg=out.content)
    assert_false(out.content.contains("snippet.mbtx"), msg=out.content)
  })
}

///|
/// A build stopped by its bound must not leave its half-written output for the
/// next call to trust. Stopping `moon` does not stop the compilers it spawned,
/// so the stop retires the key's generation; the next call builds in a fresh
/// directory and sweeps the retired one.
async test "cache: a build stopped by its bound retires its generation" {
  @vfs.with_tmpdir(prefix="mbtx-cache-abort-", ws => {
    let spill = "\{ws}/spill"
    @fs.mkdir(spill)
    let bounded = @mbtx.definition(
      workspace_root=ws,
      job_dir=spill,
      build_timeout_ms=1,
    )
    let stopped = dispatch(bounded, { "source": "fn main { println(1) }" })
    assert_true(stopped.is_error)
    assert_true(stopped.content.contains("BUILD did not finish"))
    assert_eq(
      @fs.read_file("\{spill}/mbtx-cache/snippet/generation").text(),
      "1",
    )
    let definition = @mbtx.definition(workspace_root=ws, job_dir=spill)
    let ok = dispatch(definition, { "source": "fn main { println(1) }" })
    assert_false(ok.is_error, msg=ok.content)
    assert_true(ok.content.contains("1"))
    assert_true(@fs.exists("\{spill}/mbtx-cache/snippet/gen-1/_build"))
    assert_false(@fs.exists("\{spill}/mbtx-cache/snippet/gen-0"))
    // Once discarded, the cache serves the next call as usual.
    let again = dispatch(definition, { "source": "fn main { println(2) }" })
    assert_true(again.content.contains("2"), msg=again.content)
  })
}

///|
/// A cache hit is a no-op rebuild that reports nothing but the artifact, so a
/// caller asking for warnings must get a real recompile, or the second call
/// would silently lose diagnostics the first one showed.
async test "cache: requested warnings survive an unchanged script" {
  @vfs.with_tmpdir(prefix="mbtx-cache-warn-", ws => {
    let spill = "\{ws}/spill"
    @fs.mkdir(spill)
    let definition = @mbtx.definition(workspace_root=ws, job_dir=spill)
    let source = "fn main { let unused = 1; println(\"ran\") }"
    let first = dispatch(definition, { "source": source, "warning": "on" })
    assert_false(first.is_error, msg=first.content)
    assert_true(first.content.contains("nused"), msg=first.content)
    let second = dispatch(definition, { "source": source, "warning": "on" })
    assert_false(second.is_error, msg=second.content)
    assert_true(second.content.contains("nused"), msg=second.content)
    assert_true(second.content.contains("ran"))
  })
}

///|
/// A run handed to the background reclaims its own per-call directory at
/// terminal status. That must reclaim ONLY the per-call directory: the cache
/// is the session's, and the program keeps running from its private copy.
async test "cache: a detached job's cleanup keeps the cache and its own run" {
  @vfs.with_tmpdir(prefix="mbtx-cache-bg-", ws => {
    let spill = "\{ws}/spill"
    @fs.mkdir(spill)
    @async.with_task_group() <| group => {
      let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=spill)
      let definition = @mbtx.definition(
        workspace_root=ws,
        bg_runtime=bg,
        job_dir=spill,
        auto_background_after_ms=1,
      )
      let source =
        #|import { "moonbitlang/async" }
        #|
        #|async fn main {
        #|  @async.sleep(300)
        #|  println("late")
        #|}
      let output = dispatch(definition, { "source": source })
      assert_false(output.is_error, msg=output.content)
      assert_true(output.content.contains("moved to the background"))
      // Rebuild the shared snippet dir underneath the running job. With the
      // 1ms handoff bound this run is adopted too, but its BUILD happened
      // synchronously first, in the shared directory, while the job ran.
      let other = dispatch(definition, {
        "source": "fn main { println(\"other\") }",
      })
      assert_false(other.is_error, msg=other.content)
      // The job's per-call build dir is reclaimed when it ends...
      let mut reclaimed = false
      for _ in 0..<200 {
        if !@fs.exists("\{spill}/snippet-0/build") {
          reclaimed = true
          break
        }
        @async.sleep(50)
      }
      assert_true(
        reclaimed,
        msg="the job's terminal must reclaim its build dir",
      )
      // ...and the cache is still there for the next call.
      assert_true(@fs.exists("\{spill}/mbtx-cache/snippet/gen-0/_build"))
      let after = dispatch(definition, {
        "source": "fn main { println(\"after\") }",
      })
      assert_false(after.is_error, msg=after.content)
    }
  })
}
