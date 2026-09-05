name = "bobzhang/openseek"

version = "0.3.1"

import {
  "moonbitlang/async@0.21.1",
  "moonbitlang/x@0.4.50",
  "moonbitlang/jsonl@0.2.0",
  "bobzhang/openseek_protocol@0.1.1",
  "moonbit-community/rabbita@0.15.4",
  "moonbitlang/editor@0.4.5",
  "moonbitlang/workflow@0.7.0",
}

readme = "README.mbt.md"

repository = "https://github.com/bobzhang/openseek"

license = "Apache-2.0"

keywords = [ ]

description = "DeepSeek-backed MoonBit coding agent"

preferred_target = "native"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value+implicit_impl_as_method+unused_optional_argument"

rule(
  name: "md_to_mbt_string",
  command: "moon run scripts/md_to_mbt_string -- \"$input\" \"$output\"",
)
