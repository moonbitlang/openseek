///|
fn ssh_destination(destination : String, port : Int32?) -> String raise {
  guard !destination.is_blank() &&
    !destination.has_prefix("-") &&
    !destination.iter().any(ch => ch is ('\u0000'..<='\u0020' | '\u007f')) else {
    raise SshError("Enter an SSH host or user@host")
  }
  match port {
    None => destination
    Some(port) => {
      guard port > 0 && port <= 65535 && !destination.contains("://") else {
        raise SshError(
          "SSH port must be between 1 and 65535; omit it when using an SSH URI",
        )
      }
      "ssh://" + destination + ":" + port.to_string()
    }
  }
}

///|
pub async fn Store::add(
  self : Store,
  request : @protocol.SshAdd,
) -> @protocol.SshProfile {
  guard !request.name.is_blank() else { raise SshError("Enter a display name") }
  let destination = ssh_destination(request.destination, request.port)
  let (launcher, build_id, data_dir) = @headless_installer.discover(destination)
  self.save({
    id: None,
    name: request.name,
    destination,
    launcher,
    build_id,
    data_dir,
  })
}

///|
test "SSH port is an address component and invalid destinations never become options" {
  assert_eq(ssh_destination("dev", None), "dev")
  assert_eq(ssh_destination("me@dev", Some(2222)), "ssh://me@dev:2222")
  assert_eq(ssh_destination("me@[::1]", Some(2222)), "ssh://me@[::1]:2222")
  for
    (destination, port) in [
      ("-oProxyCommand=x", None),
      ("host\ncommand", None),
      ("dev", Some(0)),
      ("dev", Some(65536)),
      ("ssh://dev:22", Some(23)),
    ] {
    let refused = try {
      ignore(ssh_destination(destination, port))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}
