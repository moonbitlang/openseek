///|
/// Desktop discovery remains an embedding policy. Headless launchers select a
/// platform-checked seed explicitly, or use the working machine's toolchain.
pub(all) enum ToolchainSource {
  DesktopBundle
  External
  Bundled(platform~ : String, seed_dir~ : @pathx.Absolute)
}

///|
/// Validate the selected seed before starting work with this toolchain.
/// None means its version marker is absent or empty. Invalid platform/path
/// selections and filesystem errors propagate separately.
pub async fn bundled_source(
  platform~ : String,
  seed_dir~ : String,
  host_platform~ : String,
) -> ToolchainSource? {
  let expected = match platform {
    "linux-x64" => "Linux-x86_64"
    "linux-arm64" => "Linux-aarch64"
    "macos-arm64" => "Darwin-arm64"
    _ => fail("unsupported MoonBit seed platform: \{platform}")
  }
  guard expected == host_platform else {
    fail(
      "MoonBit seed \{platform} does not match working host \{host_platform}",
    )
  }
  guard @pathx.Path(seed_dir).to_absolute() is Some(directory) else {
    fail("MoonBit seed directory must be absolute")
  }
  guard bundled_moonbit_seed_version(directory) is Some(_) else { return None }
  Some(Bundled(platform~, seed_dir=directory))
}

///|
/// Where a usable MoonBit toolchain's executable lives, probed once at
/// resolution. `moon` serves the engine tools and every host language request.
/// Everything else a moon command needs (`moonc`, `lib/core`, `include`) is
/// moon's own business: moon locates its compiler assets relative to its own
/// executable, so handing children the right binary is the whole job.
/// `MOON_HOME` is never read or written — it holds the user's registry
/// identity (`credentials.json`) and caches, not the toolchain, and plays
/// no part in which moon binary runs.
pub struct ResolvedToolchain {
  bin_dir : @pathx.Absolute
  moon : @pathx.Absolute
}

///|
/// Assemble the toolchain living at `bin_dir`, `None` when the directory
/// does not hold the binary the desktop spawns (a usable `moon`). All
/// executable probing happens here, once. Only the current
/// platform's name counts: the suffix rejects a directory holding just
/// `moon.exe` (a Windows install leaking into a foreign-platform search),
/// where command lookup for `moon` would never resolve and accepting the
/// directory would shadow a valid `~/.moon/bin` later in the chain.
async fn toolchain_at(bin_dir : @pathx.Absolute) -> ResolvedToolchain? {
  let moon = bin_dir.join("moon" + ExecutableSuffix)
  guard @fsx.is_executable_file(moon.to_path()) else { return None }
  Some({ bin_dir, moon, })
}

///|
/// No usable MoonBit toolchain on this machine: nothing bundled, and the
/// external search found no directory holding an executable `moon`.
/// Consumers must fail their operation rather than substitute a toolchain
/// from ambient state.
pub suberror ToolchainUnavailable

///|
/// The canonical description used verbatim in consumer logs and surfaced
/// errors, so every report of an unavailable toolchain reads the same.
pub impl Show for ToolchainUnavailable with fn output(_self, logger) {
  logger.write_string(
    "no MoonBit toolchain found: nothing bundled, and no usable moon on PATH or in ~/.moon/bin",
  )
}

///|
/// Locate the MoonBit toolchain the desktop hands to engines and the LSP
/// pool. `DesktopBundle` prefers the user's own installation and falls back to
/// the bundled seed's prepared payload (see [desktop_toolchain]). Raises
/// [ToolchainUnavailable] when the machine has none; a bundled seed that
/// fails to prepare raises a plain failure — that is the app's own artifact
/// breaking, not machine configuration.
pub async fn resolve_toolchain(
  engine_command : String,
  runtime_dir? : @pathx.Path,
  source~ : ToolchainSource = DesktopBundle,
) -> ResolvedToolchain {
  let path_env = @env.get("PATH")
  let home_dir = @home.dir()
  match source {
    DesktopBundle =>
      desktop_toolchain(engine_command, runtime_dir?, path_env?, home_dir?)
    External => external_toolchain(path_env?, home_dir?)
    Bundled(platform~, seed_dir~) =>
      bundled_toolchain(seed_dir, runtime_dir?, payload_name=platform)
  }
}

///|
/// The user's toolchain, found the way their shell finds `moon`, wins as long
/// as it also carries the `moonx` the host spawns for registry tools. The
/// bundled seed fills in only when no such installation exists, so a working
/// user install is used as-is and the seed's payload is never prepared.
async fn desktop_toolchain(
  engine_command : String,
  runtime_dir? : @pathx.Path,
  path_env? : String,
  home_dir? : @pathx.Path,
) -> ResolvedToolchain {
  let external = find_external_toolchain(path_env?, home_dir?)
  if external is Some(toolchain) {
    if @fsx.is_executable_file(toolchain.moonx().to_path()) {
      return toolchain
    }
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_external_without_moonx",
        "bin_dir": toolchain.bin_dir.to_string(),
      }
  }
  if bundled_moonbit_seed_dir(engine_command) is Some(seed_dir) {
    return bundled_toolchain(seed_dir, runtime_dir?)
  }
  guard external is Some(toolchain) else { raise ToolchainUnavailable }
  toolchain
}

///|
async fn bundled_toolchain(
  seed_dir : @pathx.Absolute,
  runtime_dir? : @pathx.Path,
  payload_name? : String,
) -> ResolvedToolchain {
  guard prepared_bundled_moonbit_payload(seed_dir~, runtime_dir?, payload_name?)
    is Some(payload) else {
    fail("failed to prepare bundled MoonBit toolchain")
  }
  guard moonbit_bin_dir(payload).to_absolute() is Some(bin_dir) &&
    toolchain_at(bin_dir) is Some(toolchain) else {
    fail("bundled MoonBit toolchain payload is not a complete toolchain")
  }
  toolchain
}

///|
/// The external search chain: the path variable's entries in order, then
/// `~/.moon/bin`. The path scan mirrors the shell's own command lookup —
/// which moon binary runs is the path's decision, and `MOON_HOME` plays no
/// part in it, so the resolver never reads the variable. The default
/// install location is probed last as a rescue for environments whose path
/// variable is bare (Finder or launchd launches): it is a constant, not an
/// environment variable, so it survives the stripped launchd environment
/// that hides the terminal's configuration.
async fn external_toolchain(
  path_env? : String,
  home_dir? : @pathx.Path,
) -> ResolvedToolchain {
  guard find_external_toolchain(path_env?, home_dir?) is Some(toolchain) else {
    raise ToolchainUnavailable
  }
  toolchain
}

///|
async fn find_external_toolchain(
  path_env? : String,
  home_dir? : @pathx.Path,
) -> ResolvedToolchain? {
  if path_env is Some(path_value) {
    for entry in path_value.split(@env.path_sep) {
      if entry.is_empty() {
        continue
      }
      let bin_dir = @pathx.Path(entry.to_owned())
      // A relative entry only means something from the resolver's own
      // working directory; children spawn elsewhere, so it must not be
      // selected or re-exported.
      guard bin_dir.to_absolute() is Some(bin_dir) else {
        @xlog.debug() <?
          { "event": "desktop_moonbit_path_entry_relative", "entry": entry }
        continue
      }
      if toolchain_at(bin_dir) is Some(toolchain) {
        @xlog.debug() <?
          {
            "event": "desktop_moonbit_external_toolchain",
            "source": "path",
            "bin_dir": bin_dir.to_string(),
          }
        return Some(toolchain)
      }
    }
  }
  if home_dir is Some(home) {
    let bin_dir = home.join(".moon").join("bin")
    if bin_dir.to_absolute() is Some(bin_dir) &&
      toolchain_at(bin_dir) is Some(toolchain) {
      @xlog.debug() <?
        {
          "event": "desktop_moonbit_external_toolchain",
          "source": "home_default",
          "bin_dir": bin_dir.to_string(),
        }
      return Some(toolchain)
    }
  }
  None
}

///|
/// The `moonx` beside this toolchain's `moon`; not probed.
fn ResolvedToolchain::moonx(self : ResolvedToolchain) -> @pathx.Absolute {
  self.bin_dir.join("moonx" + ExecutableSuffix)
}

///|
/// Prepend the toolchain's bin directory to `env`'s path variable (updating
/// `Path` in place on Windows — see `@env.prepend_path_entry`). `MOON_HOME`
/// is deliberately left alone: moon reads the user's registry identity
/// (`credentials.json`) and caches from it, while compiler assets resolve
/// relative to the moon executable itself — scrubbing or rewriting the
/// variable buys no isolation and breaks `moon login` / `moon publish` in
/// spawned sessions.
pub fn ResolvedToolchain::apply_to_env(
  self : ResolvedToolchain,
  env : Map[String, String],
) -> Unit {
  @env.prepend_path_entry(env, self.bin_dir.to_string()) |> ignore
}

///|
/// A complete child environment (pass with `inherit_env=false`) for spawning
/// a binary out of this toolchain: the current environment with the
/// toolchain's environment policy applied.
pub fn ResolvedToolchain::tool_env(
  self : ResolvedToolchain,
) -> Map[String, String] {
  let env = @sys.get_env_vars()
  self.apply_to_env(env)
  env
}

///|
pub extend ToolchainUnavailable with Show::{output, to_string}
