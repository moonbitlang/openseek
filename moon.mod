name = "moonbitlang/openseek"

version = "0.6.2"

import {
  "openseek_desktop/backend@0.1.5",
  "moonbitlang/async@0.22.4",
  "moonbit-community/flate@0.8.4",
  "moonbit-community/fuzzy_match@0.2.6",
  "bobzhang/open_in_browser@0.1.0",
  "moonbitlang/x@0.5.5",
  "moonbitlang/jsonl@0.2.1",
  "moonbitlang/openseek_protocol@0.3.1",
  "moonbit-community/rabbita@0.16.4",
  "Lampese/office-viewer@0.1.3",
  "moonbitlang/editor@0.4.6",
  "moonbitlang/workflow@0.10.0",
  "Yoorkin/multipart@0.1.3",
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
