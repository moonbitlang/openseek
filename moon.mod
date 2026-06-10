name = "bobzhang/openseek"

version = "0.1.5"

import {
  "moonbit-community/tty@0.2.4",
  "moonbitlang/async@0.19.1",
  "moonbitlang/x@0.4.45",
  "moonbit-community/displaytext@0.1.5",
  "tonyfettes/xlog@0.4.0",
  "bobzhang/jsonl@0.2.0",
}

readme = "README.mbt.md"

repository = "https://github.com/bobzhang/openseek"

license = "Apache-2.0"

keywords = [ ]

description = "DeepSeek-backed MoonBit coding agent"

preferred_target = "native"

warnings = "+missing_doc"

rule(
  name: "md_to_mbt_string",
  command: "moon run --quiet --target native scripts/md_to_mbt_string -- \"$input\" \"$output\"",
)
