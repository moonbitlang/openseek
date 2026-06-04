name = "bobzhang/openseek"

version = "0.1.4"

import {
  "moonbit-community/tty@0.2.4",
  "moonbitlang/async@0.19.1",
  "moonbitlang/x@0.4.45",
  "moonbit-community/displaytext@0.1.4",
}

readme = "README.mbt.md"

repository = "https://github.com/bobzhang/openseek"

license = "Apache-2.0"

keywords = [ ]

description = "DeepSeek-backed MoonBit coding agent"

preferred_target = "native"

rule(
  name: "md_to_mbt_string",
  command: "moon run --quiet --target native scripts/md_to_mbt_string -- \"$input\" \"$output\"",
)
