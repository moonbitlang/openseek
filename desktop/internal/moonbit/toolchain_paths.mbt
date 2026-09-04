///|
const MoonbitBundleStampFile : String = ".openseek-moonbit-bundle-version"

///|
const MoonbitSeedVersionFile : String = ".openseek-moonbit-seed-version"

///|
/// The seed-relative reference-docs path (FHS `share/doc/moonbit` under the
/// toolchain prefix). Packaging stages the pinned moonbit-docs markdown build
/// here (`MoonbitDocsRelDir` in
/// `desktop/package/internal/moonbit/toolchain.mbt`), the payload copy
/// carries it verbatim, and the engine advertises the tree to the model as
/// `OPENSEEK_REFERENCES`.
const MoonbitDocsRelDir : String = "share/doc/moonbit"

///|
fn moonbit_toolchain_dir(
  base : @pathx.Absolute,
  name : String,
) -> @pathx.Absolute {
  base.join("toolchains").join("moonbit").join(name).normalize()
}

///|
/// The seed of a package that keeps its executables in a `bin/` directory of
/// their own, so the toolchain is the binary's uncle rather than its sibling
/// — the macOS bundle, whose Proton package input stages `bin/openseek`
/// beside `toolchains/` (`package/macos/main.mbt`). The Linux AppImage and
/// the Windows bundle drop the engine straight into the directory that holds
/// `toolchains/`, which `moonbit_toolchain_dir` already covers.
fn bin_sibling_toolchain_dir(
  command_dir : @pathx.Absolute,
  name : String,
) -> @pathx.Absolute {
  moonbit_toolchain_dir(command_dir.join("..").normalize(), name)
}

///|
/// A seed is detected by the version stamp packaging writes as its final
/// step — after extracting the binary and core archives and verifying the
/// staged compiler answers `moonc -v` with the expected version. The stamp's
/// presence therefore already asserts a complete seed; re-probing individual
/// files here would re-litigate what packaging proved, and the sealed app
/// bundle guards integrity from there.
async fn bundled_moonbit_seed_dir(engine_command : String) -> @pathx.Absolute? {
  let command_dir = @pathx.Path(engine_command).dirname().resolve()
  let candidates = [
    moonbit_toolchain_dir(command_dir, "windows-x64"),
    moonbit_toolchain_dir(command_dir, "linux-x64"),
    moonbit_toolchain_dir(command_dir, "macos-arm64"),
    bin_sibling_toolchain_dir(command_dir, "windows-x64"),
    bin_sibling_toolchain_dir(command_dir, "linux-x64"),
    bin_sibling_toolchain_dir(command_dir, "macos-arm64"),
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
/// The macOS bundle stages the engine one level below the toolchain
/// (`<input>/bin/openseek` beside `<input>/toolchains/`), unlike the Linux
/// AppImage and the Windows bundle, which put the engine straight into the
/// directory holding `toolchains/`. Both shapes must resolve, or the engine
/// never spawns — `resolve_toolchain` raises before it.
async test "the seed is found beside the engine and one level above it" {
  let tmp = @pathx.Path(@fs.tmpdir(prefix="openseek-moonbit-seed-layout-")).resolve()
  defer (@fs.rmdir(tmp.to_string(), recursive=true) catch { _ => () })
  // macOS: `<input>/bin/openseek` with `<input>/toolchains/…`.
  let bundle = tmp.join("proton-package-input")
  let bundle_seed = bundle.join("toolchains/moonbit/macos-arm64")
  write_fake_seed(bundle_seed)
  @fs.mkdir(bundle.join("bin").to_string(), recursive=true)
  let bundle_found = bundled_moonbit_seed_dir(
    bundle.join("bin/openseek").to_string(),
  ).map(dir => dir.to_string())
  // Linux/Windows: the engine sits in the directory that holds `toolchains/`.
  let flat = tmp.join("usr/bin")
  let flat_seed = flat.join("toolchains/moonbit/linux-x64")
  write_fake_seed(flat_seed)
  let flat_found = bundled_moonbit_seed_dir(flat.join("openseek").to_string()).map(dir => {
      dir.to_string()
    },
  )
  assert_eq(bundle_found, Some(bundle_seed.normalize().to_string()))
  assert_eq(flat_found, Some(flat_seed.normalize().to_string()))
}
