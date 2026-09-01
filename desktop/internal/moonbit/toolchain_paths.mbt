///|
const MoonbitBundleStampFile : String = ".openseek-moonbit-bundle-version"

///|
const MoonbitSeedVersionFile : String = ".openseek-moonbit-seed-version"

///|
/// The seed-relative reference-docs path (FHS `share/doc/moonbit` under the
/// toolchain prefix). Packaging stages the pinned moonbit-docs markdown build
/// here (`MoonbitDocsRelDir` in `desktop/package/build.mjs`), the payload copy
/// carries it verbatim, and the engine advertises the tree to the model as
/// `OPENSEEK_REFERENCES`.
const MoonbitDocsRelDir : String = "share/doc/moonbit"

///|
/// A seed is detected by the version stamp packaging writes as its final
/// step — after extracting the binary and core archives and verifying the
/// staged compiler answers `moonc -v` with the expected version. The stamp's
/// presence therefore already asserts a complete seed; re-probing individual
/// files here would re-litigate what packaging proved, and the sealed app
/// bundle guards integrity from there.
async fn bundled_moonbit_seed_dir(engine_command : String) -> @pathx.Absolute? {
  let command_dir = @pathx.Path(engine_command).dirname().resolve()
  // Every installed engine is `seekmoon/bin/openseek[.exe]`; Proton exposes
  // the containing resource directory consistently on all three platforms.
  // Platform names still differ because each package carries a native seed,
  // but there is only one structural location to search.
  let root = command_dir.join("..").normalize()
  let candidates = [
    root.join("toolchains/moonbit/windows-x64"),
    root.join("toolchains/moonbit/linux-x64"),
    root.join("toolchains/moonbit/macos-arm64"),
  ]
  for candidate in candidates {
    let version = bundled_moonbit_seed_version(candidate)
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_seed_candidate",
        "engine_command": engine_command,
        "command_dir": command_dir.to_string(),
        "candidate": candidate.to_string(),
        "seed_version": version,
      }
    if version is Some(_) {
      @xlog.debug() <?
        {
          "event": "desktop_moonbit_seed_selected",
          "candidate": candidate.to_string(),
        }
      return Some(candidate)
    }
  }
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_seed_missing",
      "engine_command": engine_command,
      "command_dir": command_dir.to_string(),
    }
  None
}

///|
async fn prepared_moonbit_payload_dir(
  seed_dir~ : @pathx.Absolute,
  runtime_dir? : @pathx.Path,
) -> @pathx.Path? {
  guard runtime_dir is Some(runtime_dir) else {
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_payload_dir_missing_runtime",
        "seed_dir": seed_dir.to_string(),
      }
    return None
  }
  let seed_name = seed_dir.to_path().basename().to_owned()
  if seed_name.is_empty() {
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_payload_dir_missing_seed_name",
        "seed_dir": seed_dir.to_string(),
        "runtime_dir": runtime_dir.to_string(),
      }
    return None
  }
  let root = runtime_dir.join("toolchains/moonbit")
  @fsx.ensure_dir(root)
  let moon_home = root.join(seed_name)
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_payload_dir",
      "seed_dir": seed_dir.to_string(),
      "runtime_dir": runtime_dir.to_string(),
      "moon_home": moon_home.to_string(),
    }
  Some(moon_home)
}

///|
fn moonbit_bin_dir(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.join("bin")
}

///|
/// The moonbit-docs markdown build packaging stages inside the seed at
/// `share/doc/moonbit`, so the prepared payload carries the docs describing
/// exactly its toolchain.
fn moonbit_docs_dir(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.join(MoonbitDocsRelDir)
}

///|
#cfg(platform="windows")
const ExecutableSuffix : String = ".exe"

///|
#cfg(not(platform="windows"))
const ExecutableSuffix : String = ""

///|
fn moonbit_command(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.join("bin/moon\{ExecutableSuffix}")
}

///|
fn moonbit_compiler_command(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.join("bin/moonc\{ExecutableSuffix}")
}

///|
fn moonbit_bundle_stamp_path(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.join(MoonbitBundleStampFile)
}

///|
fn moonbit_seed_version_path(seed_dir : @pathx.Absolute) -> @pathx.Absolute {
  seed_dir.join(MoonbitSeedVersionFile)
}

///|
fn moonbit_native_bundle_probe_path(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.join("lib/core/_build/native/release/bundle/prelude/prelude.mi")
}

///|
fn moonbit_wasm_gc_bundle_probe_path(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.join("lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi")
}

///|
/// Lay a fake completed seed under `root`, including the version stamp that
/// packaging writes only after it has verified the extracted toolchain.
async fn write_fake_seed(root : @pathx.Absolute) -> Unit {
  @fs.mkdir(root.join("bin").to_string(), recursive=true)
  @fs.mkdir(root.join("lib/core").to_string(), recursive=true)
  @fs.write_file(
    root.join("bin/moon").to_string(),
    "",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root.join("bin/moonc").to_string(),
    "",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root.join("lib/core/moon.mod").to_string(),
    "{}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root.join(MoonbitSeedVersionFile).to_string(),
    "test-version",
    create_mode=CreateOrTruncate,
  )
}

///|
/// The installed engine and native MoonBit seed always share the canonical
/// `seekmoon/` resource root, independent of Proton's outer package layout.
async test "the seed is found in the canonical seekmoon resource tree" {
  let tmp = @pathx.Path(@fs.tmpdir(prefix="openseek-moonbit-seed-layout-")).resolve()
  defer (@fs.rmdir(tmp.to_string(), recursive=true) catch { _ => () })
  let resources = tmp.join("seekmoon")
  let seed = resources.join("toolchains/moonbit/macos-arm64")
  write_fake_seed(seed)
  @fs.mkdir(resources.join("bin").to_string(), recursive=true)
  let found = bundled_moonbit_seed_dir(
    resources.join("bin/openseek").to_string(),
  ).map(dir => dir.to_string())
  assert_eq(found, Some(seed.normalize().to_string()))
}
