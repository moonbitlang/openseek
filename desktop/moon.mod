name = "openseek_desktop"

version = "0.1.5"

import {
  "moonbitlang/openseek_protocol@0.1.2",
  "moonbit-community/fuzzy_match@0.2.6",
  "moonbit-community/proton_contract@0.3.3",
  "moonbitlang/async@0.22.1",
}

readme = "README.md"

license = "Apache-2.0"

description = "Shared desktop contracts, policies, and packaging tools for SeekMoon."

warnings = "+implicit_impl_as_method+test_unqualified_package"

preferred_target = "native"

supported_targets = "native+js"
