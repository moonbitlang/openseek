name = "openseek_desktop/backend"

version = "0.1.5"

import {
  "moonbitlang/jsonl@0.2.0",
  "moonbitlang/openseek_protocol@0.2.0",
  "moonbit-community/pty@0.4.1",
  "moonbit-community/flate@0.7.1",
  "moonbitlang/x@0.4.50",
  "moonbitlang/async@0.22.4",
  "moonbit-community/proton@0.3.3",
  "moonbit-community/proton_ext@0.3.3",
  "tonyfettes/platform@0.1.1",
  "tonyfettes/xlog@0.4.0",
  "moonbit-community/proton_contract@0.3.3",
  "moonbitlang/openseek@0.3.2",
  "openseek_desktop@0.1.5",
}

license = "Apache-2.0"

description = "SeekMoon native desktop backend."

warnings = "+implicit_impl_as_method+test_unqualified_package"

preferred_target = "native"

supported_targets = "native"
