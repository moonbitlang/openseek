name = "openseek_desktop/backend"

version = "0.1.5"

import {
  "moonbitlang/jsonl@0.2.1",
  "moonbitlang/openseek_protocol@0.3.1",
  "moonbit-community/pty@0.4.3",
  "moonbit-community/flate@0.8.4",
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.22.4",
  "tonyfettes/xlog@0.4.2",
  "moonbit-community/proton_contract@0.3.4",
  "moonbitlang/openseek@0.6.2",
  "openseek_desktop@0.1.5",
}

license = "Apache-2.0"

description = "SeekMoon desktop backend: the engine host, the host operations, and the remote transports, with no window toolkit."

warnings = "+implicit_impl_as_method+test_unqualified_package"

preferred_target = "native"

supported_targets = "native"
