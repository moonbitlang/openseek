name = "openseek_desktop/server"

version = "0.1.5"

import {
  "moonbitlang/async@0.22.4",
  "tonyfettes/xlog@0.4.2",
  "openseek_desktop/backend@0.1.5",
}

license = "Apache-2.0"

description = "SeekMoon shared server for terminal and desktop clients."

preferred_target = "native"

supported_targets = "native"

warnings = "+implicit_impl_as_method+test_unqualified_package+unnecessary_annotation"
