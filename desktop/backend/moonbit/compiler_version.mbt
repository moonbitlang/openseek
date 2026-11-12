///|
/// `moonc -v` results by compiler path, kept with the compiler's mtime so an
/// upgrade in place is noticed. Resolution runs on every engine spawn and
/// moonx request, and each probe spawns a process.
let compiler_versions : Map[String, (@fs.Timestamp, @version.Version?)] = Map([])

///|
/// The version of the `moonc` in `bin_dir`; `None` when it is missing, fails,
/// or prints something unrecognized.
async fn compiler_version(bin_dir : @pathx.Absolute) -> @version.Version? {
  let moonc = bin_dir.join("moonc" + ExecutableSuffix).to_string()
  let modified = @fs.mtime(moonc) catch { _ => return None }
  if compiler_versions.get(moonc) is Some((seen, version)) && seen == modified {
    return version
  }
  let version = probe_compiler_version(moonc)
  compiler_versions[moonc] = (modified, version)
  version
}

///|
async fn probe_compiler_version(moonc : String) -> @version.Version? {
  let result = @processx.collect_output_no_stdin(moonc, ["-v"]) catch {
    _ => return None
  }
  guard result.exit_code == 0 else { return None }
  @version.parse(result.stdout_text())
}
