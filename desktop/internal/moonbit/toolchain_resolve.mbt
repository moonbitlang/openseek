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
  /// The MoonBit reference docs shipped with this toolchain, when it carries
  /// them: the bundled payload's `share/doc/moonbit/`, the moonbit-docs
  /// markdown build the packager stages into the seed. An external toolchain
  /// never has any. The engine advertises the directory to the model as
  /// `OPENSEEK_REFERENCES`.
  references : @pathx.Absolute?
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
  Some({ bin_dir, moon, references: None, })
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
/// pool: the bundled seed's prepared payload when the app ships one,
/// otherwise the first external toolchain found. Raises
/// [ToolchainUnavailable] when the machine has none; a bundled seed that
/// fails to prepare raises a plain failure — that is the app's own artifact
/// breaking, not machine configuration.
pub async fn resolve_toolchain(
  engine_command : String,
  runtime_dir? : @pathx.Path,
) -> ResolvedToolchain {
  if bundled_moonbit_seed_dir(engine_command) is Some(seed_dir) {
    guard prepared_bundled_moonbit_payload(seed_dir~, runtime_dir?)
      is Some(payload) else {
      fail("failed to prepare bundled MoonBit toolchain")
    }
    guard moonbit_bin_dir(payload).to_absolute() is Some(bin_dir) &&
      toolchain_at(bin_dir) is Some(toolchain) else {
      fail("bundled MoonBit toolchain payload is not a complete toolchain")
    }
    // The seed's `share/doc/moonbit/` came along in the payload copy, so the
    // reference path is exactly as stable as `moon` itself: the per-user
    // runtime directory, never the bundle (an AppImage mounts afresh per
    // launch).
    let docs = moonbit_docs_dir(payload)
    let references = if @fsx.is_dir(docs) { docs.to_absolute() } else { None }
    return { ..toolchain, references, }
  }
  external_toolchain(path_env?=@env.get("PATH"), home_dir?=@home.dir())
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
          {
            "event": "desktop_moonbit_path_entry_relative",
            "entry": entry.to_owned(),
          }
        continue
      }
      if toolchain_at(bin_dir) is Some(toolchain) {
        @xlog.debug() <?
          {
            "event": "desktop_moonbit_external_toolchain",
            "source": "path",
            "bin_dir": bin_dir.to_string(),
          }
        return toolchain
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
      return toolchain
    }
  }
  raise ToolchainUnavailable
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
