///|
async test "session scratch permits raw file IO and script saving outside the workspace" {
  @vfs.with_tmpdir(root => {
    let workspace = "\{root}/project"
    let scratch = "\{root}/session/scratch"
    @fs.mkdir(workspace)
    let tool = @mbtx.definition(workspace_root=workspace, scratch_dir=scratch)
    let source =
      #|import {
      #|  "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/shell",
      #|  "moonbitlang/core/env",
      #|}
      #|async fn main {
      #|  let args = @env.args()
      #|  let dir = args[1]
      #|  @fs.mkdir("\{dir}/data", recursive=true)
      #|  @fs.write_file("\{dir}/data/value.bin", b"\x00\xff")
      #|  let code = @shell.Cmd("moon", ["--version"], stdout=ToFile("\{dir}/version.txt")).status()
      #|  guard code == 0 else { fail("command failed") }
      #|  for path in [args[2], "\{dir}/../outside.txt"] {
      #|    try @fs.write_file(path, "forbidden") catch {
      #|      _ => ()
      #|    } noraise { _ => fail("write escaped scratch") }
      #|  }
      #|  println("saved")
      #|}
    let saved = dispatch(tool, {
      "source": source,
      "filename": "\{scratch}/helper.mbtx",
      "args": [scratch, "\{workspace}/project.txt"],
      "ptc": false,
    })
    assert_false(saved.is_error, msg=saved.content)
    assert_eq(@fs.read_file("\{scratch}/data/value.bin").binary(), b"\x00\xff")
    assert_true(@fs.read_file("\{scratch}/version.txt").text().contains("moon"))
    let reopened = @mbtx.definition(
      workspace_root=workspace,
      scratch_dir=scratch,
    )
    let read = dispatch(reopened, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/core/env" }
        #|async fn main {
        #|  let dir = @env.args()[1]
        #|  guard @fs.read_file("\{dir}/data/value.bin").binary() == b"\x00\xff" else { fail("lost bytes") }
        #|  @fs.remove("\{dir}/data/value.bin")
        #|  @fs.rmdir("\{dir}/data")
        #|  println("read and removed")
        #|}
      ),
      "args": [scratch],
      "ptc": false,
    })
    assert_false(read.is_error, msg=read.content)
    assert_false(@fs.exists("\{scratch}/data"))
    let outside = dispatch(reopened, {
      "source": "fn main {}",
      "filename": "\{root}/outside.mbtx",
    })
    assert_true(outside.is_error)
    let changed = dispatch(reopened, {
      "source": "fn main {}",
      "filename": "\{scratch}/helper.mbtx",
    })
    assert_true(changed.is_error)
    assert_eq(@fs.read_file("\{scratch}/helper.mbtx").text(), source)
  })
}

///|
#cfg(not(platform="windows"))
async test "session scratch cannot grant writes through an escaping symlink" {
  @vfs.with_tmpdir(root => {
    let workspace = "\{root}/project"
    let scratch = "\{root}/scratch"
    let outside = "\{root}/outside"
    for dir in [workspace, scratch, outside] {
      @fs.mkdir(dir)
    }
    @fs.symlink(target=outside, "\{scratch}/link")
    let tool = @mbtx.definition(workspace_root=workspace, scratch_dir=scratch)
    let saved = dispatch(tool, {
      "source": "fn main {}",
      "filename": "\{scratch}/link/escaped.mbtx",
    })
    assert_true(saved.is_error)
    let raw = dispatch(tool, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/core/env" }
        #|async fn main { @fs.write_file(@env.args()[1], "escaped") }
      ),
      "args": ["\{scratch}/link/escaped.txt"],
      "ptc": false,
    })
    assert_true(raw.is_error)
    assert_false(@fs.exists("\{outside}/escaped.mbtx"))
    assert_false(@fs.exists("\{outside}/escaped.txt"))
  })
}

///|
async test "scratch script saving preserves read-only and worker restrictions" {
  @vfs.with_tmpdir(root => {
    let workspace = "\{root}/project"
    let scratch = "\{root}/scratch"
    @fs.mkdir(workspace)
    let worker = match @write_scope.WriteScope::create(root=workspace) {
      Ok(scope) => scope
      Err(reason) => fail(reason)
    }
    for
      tool in [
        @mbtx.definition(
          workspace_root=workspace,
          scratch_dir=scratch,
          read_only=true,
        ),
        @mbtx.definition(
          workspace_root=workspace,
          scratch_dir=scratch,
          write_scope=worker,
        ),
      ] {
      let out = dispatch(tool, {
        "source": "fn main {}",
        "filename": "\{scratch}/blocked.mbtx",
      })
      assert_true(out.is_error)
      assert_false(@fs.exists("\{scratch}/blocked.mbtx"))
    }
  })
}
