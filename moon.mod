name = "bobzhang/openseek"

version = "0.1.3"

import {
  "moonbit-community/tty@0.2.4",
  "moonbitlang/async@0.19.1",
  "kawaz/grapheme@0.10.2",
  "rami3l/unicodewidth@0.2.0",
}

readme = "README.mbt.md"

repository = "https://github.com/bobzhang/openseek"

license = "Apache-2.0"

keywords = [ ]

description = "DeepSeek-backed MoonBit coding agent"

preferred_target = "native"

rule(
  name: "md_to_mbt_string",
  command: "sh scripts/md_to_mbt_string.sh $input $output",
)
