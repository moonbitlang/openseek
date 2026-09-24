name = "moonbitlang/editor"

version = "0.4.5"

readme = "README.md"

repository = "https://github.com/moonbitlang/openseek"

license = "Apache-2.0"

keywords = [ "editor", "moonbit", "readonly", "syntax-highlighting" ]

description = "Readonly MoonBit code viewer harness inspired by Monaco and CodeMirror."

supported_targets = "+js+native+wasm"

preferred_target = "js"

warnings = "+prefer_readonly_array+implicit_impl_as_method+test_unqualified_package"

import {
  "moonbit-community/cmark@0.4.5",
  "moonbit-community/moondiff@0.0.7",
  "moonbitlang/async@0.22.4",
  "moonbit-community/rabbita@0.16.2",
  "Milky2018/diago@0.3.0",
  "moonbitlang/x@0.4.50",
  "kokic/uml@0.4.0",
}
