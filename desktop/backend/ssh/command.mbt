///|
pub(all) suberror SshError {
  SshError(String)
}

///|
pub fn arguments(command : String) -> Array[String] raise {
  let options = @protocol.ssh_connection_arguments(command) catch {
    @protocol.SshCommandError(message) => raise SshError(message)
    error => raise error
  }
  [
    "-T", "-oControlMaster=no", "-oControlPath=none", "-oRemoteCommand=none", "-oRequestTTY=no",
    "-oBatchMode=no", "-oStrictHostKeyChecking=ask", "-oConnectTimeout=15", "-oServerAliveInterval=15",
    "-oServerAliveCountMax=2", ..options,
  ]
}

///|
fn remote_command(
  server : String,
  model_environment~ : Bool = false,
) -> String raise {
  guard !server.is_empty() && !server.contains("\n") else {
    raise SshError("Missing remote app-server executable")
  }
  // The old default in saved profiles still selects automatic preparation.
  let command = if server == "openseek-app-server" || server == "openseek" {
    match @env.get_env_var("SEEKMOON_SSH_RELEASE_URL") {
      Some(url) => prepare_command(url, "=https,http,file")
      None =>
        prepare_command(
          "https://cli.moonbitlang.com/openseek/cli/releases/v" + CliRelease,
          "=https",
        )
    }
  } else {
    "exec " + shell_quote(server)
  }
  if model_environment {
    // Fixed names, literal single-line values over stdin, never evaluated as
    // shell code. An absent local key leaves the remote environment unchanged.
    // The remaining stdin continues to own app-server lifetime.
    let reads = model_environment_names
      .map(name => {
        "IFS= read -r _openseek_key || exit 1; " +
        "if [ -n \"$_openseek_key\" ]; then export " +
        name +
        "=\"$_openseek_key\"; fi; "
      })
      .join("")
    reads + "unset _openseek_key; " + command
  } else {
    command
  }
}

///|
let model_environment_names : Array[String] = ["DEEPSEEK", "KIMI", "GLM"]

///|
fn model_environment_input(
  values : Map[String, String],
) -> String raise SshError {
  let lines = model_environment_names.map(name => {
    let value = values.get(name).unwrap_or("")
    guard !value.contains("\n") &&
      !value.contains("\r") &&
      !value.contains("\u0000") else {
      raise SshError("Model environment values must be single-line text")
    }
    value
  })
  lines.join("\n") + "\n"
}
