///|
/// Formats an IPv4 address returned by the socket package in network byte
/// order.
fn format_ipv4_address(ip : UInt32) -> String {
  "\{ip >> 24}.\{(ip >> 16) & 255}.\{(ip >> 8) & 255}.\{ip & 255}"
}

///|
/// Resolves the IPv4 address selected by the operating system's default
/// route. Connecting a UDP socket selects an interface without transmitting a
/// packet; failure simply omits the optional Network URL at startup.
async fn default_route_ipv4_address() -> String? {
  let probe = Some(@socket.UdpClient(@socket.Addr::parse("192.0.2.1:80"))) catch {
    _ => None
  }
  guard probe is Some(probe) else { return None }
  let address = probe.addr
  probe.close()
  if address.is_ipv6() || address.ip() == 0 || address.ip() == 0x7f000001 {
    None
  } else {
    Some(format_ipv4_address(address.ip()))
  }
}

///|
fn editor_server_url(host : String, port : Int32) -> String {
  "http://\{host}:\{port}/"
}

///|
/// Builds the reachable startup URLs for the selected bind address. A
/// wildcard listener accepts both loopback and LAN traffic; a concrete address
/// is reported only through the route on which it was bound.
fn editor_server_listening_messages(
  bind_host : String,
  port : Int32,
  network_host : String?,
) -> Array[String] {
  let messages = ["Readonly editor native server listening on:"]
  if bind_host == "0.0.0.0" {
    messages.push("  Local:   \{editor_server_url("127.0.0.1", port)}")
    match network_host {
      Some(host) => messages.push("  Network: \{editor_server_url(host, port)}")
      None =>
        messages.push(
          "  Network: use this device's LAN IPv4 address on port \{port}",
        )
    }
    messages.push(
      "  WARNING: no authentication; use only on a trusted network.",
    )
  } else if bind_host == "127.0.0.1" {
    messages.push("  Local:   \{editor_server_url(bind_host, port)}")
  } else {
    messages.push("  Network: \{editor_server_url(bind_host, port)}")
    messages.push(
      "  WARNING: no authentication; use only on a trusted network.",
    )
  }
  messages
}
