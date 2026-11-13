///|
/// The semantic version in a `moonc -v` line such as
/// `v0.10.20+65efd5b93 (2026-11-05)`, or in a seed version marker such as
/// `0.10.20+b410defd5`: the first word, without its leading `v`.
fn parse_compiler_version(text : StringView) -> @semver.SemVer? {
  let text = text.trim()
  let word = if text.split_once(" ") is Some((head, _)) { head } else { text }
  Some(@semver.parse(word.strip_prefix("v").unwrap_or(word).to_owned())) catch {
    _ => None
  }
}

///|
/// `moonc -v` results by compiler path, kept with the compiler's mtime so an
/// upgrade in place is noticed. Resolution runs on every engine spawn and
/// moonx request, and each probe spawns a process.
let compiler_versions : Map[String, (@fs.Timestamp, @semver.SemVer?)] = Map([])

///|
/// The version of the `moonc` in `bin_dir`; `None` when it is missing, fails,
/// or prints something unrecognized.
async fn compiler_version(bin_dir : @pathx.Absolute) -> @semver.SemVer? {
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
async fn probe_compiler_version(moonc : String) -> @semver.SemVer? {
  let result = @processx.collect_output_no_stdin(moonc, ["-v"]) catch {
    _ => return None
  }
  guard result.exit_code == 0 else { return None }
  parse_compiler_version(result.stdout_text())
}
