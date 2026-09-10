///|
async fn main {
  match @env.args() {
    [_, "hosted-child", name, mode, calls, child] =>
      hosted_child(name, mode, calls, child)
    _ =>
      match @env.get_env_var("OPENSEEK_CI_FIXTURE") {
        Some(dir) => ci_child(dir)
        None => {
          let root = @fs.realpath(".")
          guard @env.args() is [exe] else {
            fail("Run this fixture without arguments")
          }
          let exe = @fs.realpath(exe)
          @vfs.with_tmpdir(temp => {
            verify_hosted(root, temp, exe)
            verify_ci(root, temp, exe)
          })
        }
      }
  }
}

///|
async fn write(path : String, text : String) -> Unit {
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
async fn append(path : String, text : String) -> Unit {
  @fs.write_file(path, text + "\n", append=true, create_mode=OpenOrCreate)
}

///|
async fn read_calls(path : String) -> Array[Json] {
  if !@fs.exists(path) {
    return []
  }
  let calls : Array[Json] = []
  for line in @fs.read_file(path).text().split("\n") {
    if !line.is_empty() {
      calls.push(@json.parse(line))
    }
  }
  calls
}

///|
fn occurrences(text : String, part : String) -> Int {
  text.split(part).count() - 1
}

///|
async fn compile(root : String, temp : String, name : String) -> String {
  let dir = temp + "/" + name
  @fs.mkdir(dir)
  let source = dir + "/" + name + ".mbtx"
  write(
    source,
    @fs.read_file(root + "/share/workflow/" + name + ".mbtx").text(),
  )
  let build = @shell.Cmd(
    "moon",
    ["run", "--build-only", "--deny-warn", "--target", "wasm", source],
    cwd=root,
  ).output(timeout_ms=60000)
  build.check()
  guard @json.parse(build.stdout())
    is { "artifacts_path": [String(artifact)], .. } else {
    fail("Build returned no script artifact: \{build.stdout()}")
  }
  artifact
}

///|
fn clean_env() -> Map[String, String] {
  let env = @env.get_env_vars()
  env.remove("WORKFLOW_HOST")
  env.remove("OPENSEEK_CI_FIXTURE")
  env
}
