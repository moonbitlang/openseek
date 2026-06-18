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
