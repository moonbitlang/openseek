name = "bobzhang/openseek"

version = "0.2.2"

import {
  "moonbit-community/tty@0.3.0",
  "moonbitlang/async@0.20.4",
  "moonbitlang/x@0.4.49",
  "moonbit-community/displaytext@0.1.5",
  "tonyfettes/xlog@0.4.0",
  "bobzhang/jsonl@0.2.0",
  "bobzhang/openseek_protocol@0.1.0",
  "moonbit-community/rabbita@0.14.3",
}

readme = "README.mbt.md"

repository = "https://github.com/bobzhang/openseek"

license = "Apache-2.0"

keywords = [ ]

description = "DeepSeek-backed MoonBit coding agent"

preferred_target = "native"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value"

rule(
  name: "md_to_mbt_string",
  command: "moon run scripts/md_to_mbt_string -- \"$input\" \"$output\"",
)
