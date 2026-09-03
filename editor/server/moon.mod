name = "moonbitlang/editor-server"

version = "0.1.0"

license = "Apache-2.0"

description = "Remote-workspace server host for the readonly MoonBit editor."

supported_targets = "native+wasm"

preferred_target = "wasm"

warnings = "+prefer_readonly_array+implicit_impl_as_method"

import {
  "moonbitlang/editor@0.4.5",
  "moonbitlang/async@0.21.0",
}
