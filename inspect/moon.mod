name = "moonbitlang/inspect"

version = "0.1.0"

import {
  "moonbitlang/openseek@0.5.0",
  "moonbitlang/async@0.22.4",
}

readme = "README.md"

repository = "https://github.com/moonbitlang/openseek"

license = "Apache-2.0"

keywords = [ "openseek", "session", "viewer" ]

description = "Web viewer for OpenSeek session logs: serves the session visualizer, live with --watch; run it with `moonx moonbitlang/inspect`."

preferred_target = "wasm"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value+implicit_impl_as_method"
