name = "openseek_desktop/backend"

version = "0.1.5"

import {
  "tonyfettes/url@0.3.5",
  "moonbitlang/jsonl@0.2.1",
  "moonbitlang/openseek_protocol@0.4.3",
  "moonbit-community/pty@0.4.4",
  "moonbit-community/flate@0.10.0",
  "moonbit-community/skills@0.2.0",
  "moonbitlang/x@0.5.7",
  "moonbitlang/async@0.22.10",
  "moonbitlang/moonback@0.8.10",
  "tonyfettes/xlog@0.5.1",
  "moonbitlang/openseek@0.8.0",
  "openseek_desktop@0.1.5",
  "Yoorkin/multipart@0.2.2",
}

license = "Apache-2.0"

description = "SeekMoon desktop backend: the engine host, the host operations, and the remote transports, with no window toolkit."

warnings = "+implicit_impl_as_method+test_unqualified_package"

preferred_target = "native"

supported_targets = "native+wasm+js"
