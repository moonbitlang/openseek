name = "openseek_desktop/backend"

version = "0.1.5"

import {
  "bobzhang/jsonl@0.2.0",
  "bobzhang/openseek_protocol@0.1.0",
  "moonbit-community/pty@0.4.1",
  "moonbit-community/flate@0.7.1",
  "moonbitlang/x@0.4.50",
  "moonbitlang/async@0.21.0",
  "moonbit-community/proton@0.2.5",
  "moonbit-community/proton_ext@0.2.5",
  "tonyfettes/platform@0.1.1",
  "tonyfettes/xlog@0.4.0",
  "moonbitlang/editor@0.4.4",
  "moonbit-community/proton_contract@0.2.5",
  "bobzhang/openseek@0.2.2",
  "moonbit-community/proton_cefsetup@0.2.5",
  "moonbit-community/proton_config@0.2.5",
  "openseek_desktop@0.1.5",
}

license = "Apache-2.0"

description = "SeekMoon native desktop backend and platform packagers."

warnings = "+implicit_impl_as_method"

options(
  preferred_target: "native",
  supported_targets: "native",
)
