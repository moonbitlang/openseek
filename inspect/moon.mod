name = "moonbitlang/inspect"

version = "0.1.0"

import {
  "moonbitlang/openseek@0.3.1",
  "moonbitlang/async@0.21.0",
}

preferred_target = "wasm"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value+implicit_impl_as_method"
