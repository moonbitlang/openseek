///|
async test "prepare bundled home raises when seed is missing" {
  let dir = @fs.tmpdir(prefix="openseek-moonbit-missing-seed-")
  let engine = @path.Path(dir).join("engine").to_string()
  try prepare_bundled_home(engine) catch {
    Failure::Failure(message) => {
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
      assert_true(message.contains("bundled MoonBit toolchain seed not found"))
    }
    error => {
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
      raise error
    }
  } noraise {
    _ => {
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
      fail("missing seed prepared successfully")
    }
  }
}

///|
async test "prepared payload dir accepts existing toolchain root" {
  let runtime = @path.Path(@fs.tmpdir(prefix="openseek-moonbit-runtime-"))
  let root = runtime.join("toolchains/moonbit")
  @fs.mkdir(root.to_string(), recursive=true)
  let expected = root.join("macos-arm64").to_string()
  let result = prepared_moonbit_payload_dir(
    seed_dir=runtime.join("seed").join("macos-arm64"),
    runtime_dir=runtime,
  ) catch {
    error => {
      @fs.rmdir(runtime.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  let actual = match result {
    Some(path) => path.to_string()
    None => "<none>"
  }
  @fs.rmdir(runtime.to_string(), recursive=true)
  assert_eq(actual, expected)
}
