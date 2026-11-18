name = "openseek_desktop"

version = "0.1.5"

import {
  "Yoorkin/multipart@0.1.3",
  "tonyfettes/url@0.3.5",
  "moonbitlang/async@0.22.7",
  "moonbitlang/openseek_protocol@0.4.2",
  "moonbit-community/fuzzy_match@0.2.6",
  "moonbit-community/proton_contract@0.9.1",
}

readme = "README.md"

license = "Apache-2.0"

description = "Shared desktop contracts, policies, and packaging tools for SeekMoon."

warnings = "+implicit_impl_as_method+test_unqualified_package"

preferred_target = "native"

supported_targets = "native+js+wasm"
