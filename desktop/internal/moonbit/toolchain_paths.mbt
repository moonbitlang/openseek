///|
const MoonbitBundleStampFile : String = ".openseek-moonbit-bundle-version"

///|
const MoonbitSeedVersionFile : String = ".openseek-moonbit-seed-version"

///|
fn moonbit_toolchain_dir(base : @path.Path, name : String) -> @path.Path {
  base.join("toolchains").join("moonbit").join(name).normalize().to_string()
}

///|
fn macos_resources_toolchain_dir(command_dir : @path.Path) -> @path.Path {
  command_dir
  .join("..")
  .join("Resources")
  .join("toolchains")
  .join("moonbit")
  .join("macos-arm64")
  .normalize()
}

///|
async fn executable_exists(root : @path.Path, name : String) -> Bool {
  @fs.exists(root.join("bin").join(name).to_string()) ||
  @fs.exists(root.join("bin").join("\{name}.exe").to_string())
}

///|
async fn moonbit_seed_looks_complete(path : @path.Path) -> Bool {
  executable_exists(path, "moon") &&
  executable_exists(path, "moonc") &&
  @fs.exists(path.join("lib/core/moon.mod").to_string())
}

///|
async fn bundled_moonbit_seed_dir(engine_command : String) -> @path.Path? {
  let command_dir = @path.Path(engine_command).dirname().resolve()
  let candidates = [
    moonbit_toolchain_dir(command_dir, "windows-x64"),
    moonbit_toolchain_dir(command_dir, "linux-x64"),
    moonbit_toolchain_dir(command_dir, "macos-arm64"),
    macos_resources_toolchain_dir(command_dir),
  ]
  for candidate in candidates {
    let complete = moonbit_seed_looks_complete(candidate)
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_seed_candidate",
        "engine_command": engine_command,
        "command_dir": command_dir.to_string(),
        "candidate": candidate.to_string(),
        "complete": complete,
      }
    if complete {
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
  seed_dir~ : @path.Path,
  runtime_dir? : @path.Path,
) -> @path.Path? {
  guard runtime_dir is Some(runtime_dir) else {
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_payload_dir_missing_runtime",
        "seed_dir": seed_dir.to_string(),
      }
    return None
  }
  let seed_name = seed_dir.basename().to_owned()
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
fn moonbit_bin_dir(moon_home : @path.Path) -> @path.Path {
  moon_home.join("bin")
}

///|
#cfg(platform="windows")
const ExecutableSuffix : String = ".exe"

///|
#cfg(not(platform="windows"))
const ExecutableSuffix : String = ""

///|
fn moonbit_command(moon_home : @path.Path) -> @path.Path {
  moon_home.join("bin/moon\{ExecutableSuffix}")
}

///|
fn moonbit_compiler_command(moon_home : @path.Path) -> @path.Path {
  moon_home.join("bin/moonc\{ExecutableSuffix}")
}

///|
fn moonbit_lsp_command(moon_home : @path.Path) -> @path.Path {
  moon_home.join("bin/moon-lsp\{ExecutableSuffix}")
}

///|
fn moonbit_bundle_stamp_path(moon_home : @path.Path) -> @path.Path {
  moon_home.join(MoonbitBundleStampFile)
}

///|
fn moonbit_seed_version_path(seed_dir : @path.Path) -> @path.Path {
  seed_dir.join(MoonbitSeedVersionFile)
}

///|
fn moonbit_native_bundle_probe_path(moon_home : @path.Path) -> @path.Path {
  moon_home.join("lib/core/_build/native/release/bundle/prelude/prelude.mi")
}

///|
fn moonbit_wasm_gc_bundle_probe_path(moon_home : @path.Path) -> @path.Path {
  moon_home.join("lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi")
}

///|
#cfg(platform="windows")
const PathSep : String = ";"

///|
#cfg(not(platform="windows"))
const PathSep : String = ":"

///|
fn prepend_to_path_env(bin_dir : String, current_path : String?) -> String {
  if current_path is Some(path) && !path.is_empty() {
    "\{bin_dir}\{PathSep}\{path}"
  } else {
    bin_dir
  }
}
