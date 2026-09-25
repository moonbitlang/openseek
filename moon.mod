name = "moonbitlang/openseek"

version = "0.4.1"

import {
  "moonbitlang/async@0.22.4",
  "moonbitlang/x@0.4.50",
  "moonbitlang/jsonl@0.2.0",
  "moonbitlang/openseek_protocol@0.2.1",
  "moonbit-community/rabbita@0.16.3",
  "moonbitlang/editor@0.4.5",
  "moonbitlang/workflow@0.7.1",
}

readme = "README.md"

repository = "https://github.com/moonbitlang/openseek"

license = "Apache-2.0"

keywords = [ ]

description = "DeepSeek-backed MoonBit coding agent"

preferred_target = "native"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value+implicit_impl_as_method+unused_optional_argument+unnecessary_annotation"

rule(
  name: "md_to_mbt_string",
  command: "moon run scripts/md_to_mbt_string -- \"$input\" \"$output\"",
)

rule(
  name: "mbtx_bundle",
  command: "moonx scripts/mbtx_bundle.mbtx \"$output\" $input",
)
