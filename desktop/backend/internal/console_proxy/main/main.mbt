///|
/// `console-proxy [--relay ORIGIN] [--port PORT] [--bundle DIR] [--demo]`
async fn main {
  let command = @argparse.Command(
    "console-proxy",
    about="Serve a locally built browser console against a SeekMoon relay.",
    flags=[
      @argparse.FlagArg(
        "demo",
        long="demo",
        about="Answer account and device routes with fixed demo data instead of a relay.",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "relay",
        long="relay",
        default_values=[@console_proxy.DefaultRelay],
        about="Relay origin that receives the console's API and device traffic.",
      ),
      @argparse.OptionArg(
        "port",
        long="port",
        default_values=["27190"],
        about="Loopback port to serve on.",
      ),
      @argparse.OptionArg(
        "bundle",
        long="bundle",
        default_values=["dist/browser"],
        about="Built browser bundle directory (`moon run package/browser --target native`).",
      ),
    ],
  )
  let parsed = command.parse()
  guard parsed.values
    is { "relay": [relay], "port": [port], "bundle": [bundle], .. } else {
    fail("missing parsed options")
  }
  let upstream : @console_proxy.Upstream = if parsed.flags
    is { "demo": true, .. } {
    Demo
  } else {
    Relay(
      relay.strip_suffix("/").map(origin => origin.to_owned()).unwrap_or(relay),
    )
  }
  @console_proxy.serve(upstream, bundle~, port=@string.parse_int(port), on_ready=origin => {
    let target = match upstream {
      Relay(relay) => relay
      Demo => "demo data"
    }
    println("Console on \{origin}/cloud — \{bundle} against \{target}")
  })
}
