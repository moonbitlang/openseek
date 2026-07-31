name = "openseek_desktop"

version = "0.1.0"

import {
  "bobzhang/jsonl@0.2.0",
  "bobzhang/openseek_protocol@0.1.0",
  "moonbit-community/cmark@0.4.4",
  "moonbit-community/fuzzy_match@0.2.5",
  "moonbit-community/rabbita@0.13.1",
  "moonbitlang/x@0.4.46",
  "moonbitlang/async@0.20.1",
  "justjavac/proton@0.1.12",
  "justjavac/proton_ext@0.1.7",
  "tonyfettes/platform@0.1.1",
  "tonyfettes/xlog@0.4.0",
  "moonbitlang/editor@0.2.3",
  "justjavac/proton_contract@0.1.0",
}

readme = "README.md"

license = "Apache-2.0"

description = "OpenSeek Desktop — a Proton + Rabbita desktop client for the OpenSeek agent."

options(
  "--moonbit-unstable-prebuild": "native_link_config.mjs",
  preferred_target: "native",
  supported_targets: "native+js",
)
