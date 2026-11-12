///|
/// The ordered part of a MoonBit compiler version: `0.10.20` in
/// `v0.10.20+b410defd5 (2026-11-04)`. The `+…` build hash carries no order,
/// so two builds of one release compare equal.
#derive(Eq, Compare)
priv struct CompilerVersion {
  major : Int32
  minor : Int32
  patch : Int32
}

///|
/// Parse `moonc -v` output or a seed version stamp: an optional `v`, then
/// `X.Y.Z`, then an optional `+build` and anything after the first space.
fn parse_compiler_version(text : StringView) -> CompilerVersion? {
  let text = text.trim()
  let token = if text.split_once(" ") is Some((head, _)) { head } else { text }
  let token = token.strip_prefix("v").unwrap_or(token)
  let release = if token.split_once("+") is Some((head, _)) {
    head
  } else {
    token
  }
  guard release.split(".").to_array() is [major, minor, patch] else {
    return None
  }
  Some({
    major: @string.parse_int(major),
    minor: @string.parse_int(minor),
    patch: @string.parse_int(patch),
  }) catch {
    _ => None
  }
}

///|
/// `moonc -v` results by compiler path, kept with the compiler's mtime so an
/// upgrade in place is noticed. Resolution runs on every engine spawn and
/// moonx request, and each probe spawns a process.
let compiler_versions : Map[String, (@fs.Timestamp, CompilerVersion?)] = Map([])

///|
/// The version of the `moonc` in `bin_dir`; `None` when it is missing, fails,
/// or prints something unrecognized.
async fn compiler_version(bin_dir : @pathx.Absolute) -> CompilerVersion? {
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
async fn probe_compiler_version(moonc : String) -> CompilerVersion? {
  let result = @processx.collect_output_no_stdin(moonc, ["-v"]) catch {
    _ => return None
  }
  guard result.exit_code == 0 else { return None }
  parse_compiler_version(result.stdout_text())
}
