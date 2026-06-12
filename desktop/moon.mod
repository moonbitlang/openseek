name = "openseek_desktop"

version = "0.1.0"

import {
  "bobzhang/jsonl@0.2.0",
  "moonbit-community/cmark@0.4.4",
  "moonbit-community/rabbita@0.12.1",
  "moonbitlang/x@0.4.43",
  "moonbitlang/async@0.19.3",
  "justjavac/lepus_app@0.1.0",
  "justjavac/lepus_manifest@0.1.0",
  "extensions@0.1.0",
  "tonyfettes/xlog@0.4.0",
}

readme = "README.md"

license = "MIT"

description = "OpenSeek Desktop — a Lepus + Rabbita desktop client for the OpenSeek agent."

options(
  source: "",
  "--moonbit-unstable-prebuild": "native_link_config.mjs",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "native+js",
)
