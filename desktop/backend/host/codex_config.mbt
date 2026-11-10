// The Codex home's `config.toml`, opened from Settings.

///|
/// Seed content for a `config.toml` this desktop creates. Codex treats an
/// empty file as default configuration, so the header only orients whoever
/// opens it.
const CodexConfigHeader : String = "# Codex configuration for this desktop's CODEX_HOME.\n# Reference: https://github.com/openai/codex/blob/main/docs/config.md\n# The Codex app-server reads this file at startup; restart the desktop to\n# apply edits.\n"

///|
/// The Codex home's `config.toml`, created (with its home directory) when
/// missing so the Settings button works on a fresh home before Codex writes
/// anything. Without an isolated home the CLI's own resolution applies: the
/// inherited `CODEX_HOME`, or `~/.codex`.
async fn ensure_codex_config(home : @pathx.Path?) -> String {
  let home_path : @pathx.Path = match home {
    Some(home) => home
    None =>
      match @sys.get_env_var("CODEX_HOME") {
        Some(value) if !value.is_blank() => Path(value)
        _ => @home.expand(Path("~/.codex"))
      }
  }
  let config = "\{home_path.0}/config.toml"
  let existing = Some(@fs.kind(config)) catch { _ => None }
  match existing {
    Some(Directory) => raise HostError("\{config} is a directory")
    Some(_) => config
    None => {
      // Recursive mkdir on an existing directory raises EEXIST; the steady
      // state is not an error here any more than in the home preparation.
      @fs.mkdir(home_path.0, recursive=true) catch {
        _ => ()
      }
      @fs.write_text(config, CodexConfigHeader, create_mode=CreateNew) catch {
        error => raise HostError("Could not create \{config}: \{error}")
      }
      config
    }
  }
}

///|
/// Ensure and open the Codex home's `config.toml` with the platform opener.
pub async fn open_codex_config(home : @pathx.Path?) -> Unit {
  let config = ensure_codex_config(home)
  let code = @platform.open_path(config) catch {
    error => raise HostError("Could not open \{config}: \{error}")
  }
  guard code == 0 else { raise HostError("Could not open \{config}") }
}
