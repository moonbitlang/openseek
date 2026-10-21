name = "openseek_desktop/app"

version = "0.1.5"

import {
  "moonbitlang/async@0.22.5",
  "moonbit-community/proton@0.5.1",
  "moonbit-community/proton_ext@0.5.1",
  "tonyfettes/xlog@0.4.2",
  "moonbit-community/proton_contract@0.5.1",
  "openseek_desktop@0.1.5",
  "openseek_desktop/backend@0.1.5",
}

license = "Apache-2.0"

description = "SeekMoon native desktop window host."

warnings = "+implicit_impl_as_method+test_unqualified_package"

preferred_target = "native"

supported_targets = "native"
