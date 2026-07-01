name = "openseek_desktop"

version = "0.1.0"

import {
  "bobzhang/jsonl@0.2.0",
  "moonbit-community/cmark@0.4.4",
  "moonbit-community/editor@0.1.0",
  "moonbit-community/rabbita@0.12.4",
  "moonbitlang/x@0.4.45",
  "moonbitlang/async@0.19.4",
  "justjavac/proton@0.1.6",
  "tonyfettes/xlog@0.4.0",
}

readme = "README.md"

license = "MIT"

description = "OpenSeek Desktop — a Proton + Rabbita desktop client for the OpenSeek agent."

source = ""

options(
  "--moonbit-unstable-prebuild": "native_link_config.mjs",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "native+js",
)
