name = "openseek_desktop"

version = "0.1.5"

import {
  "bobzhang/jsonl@0.2.0",
  "bobzhang/openseek_protocol@0.1.0",
  "moonbit-community/cmark@0.4.5",
  "moonbit-community/pty@0.4.1",
  "moonbit-community/fuzzy_match@0.2.6",
  "moonbit-community/rabbita@0.14.3",
  "moonbitlang/x@0.4.50",
  "moonbitlang/async@0.21.0",
  "moonbit-community/proton@0.1.18",
  "moonbit-community/proton_ext@0.1.14",
  "tonyfettes/platform@0.1.1",
  "tonyfettes/xlog@0.4.0",
  "moonbitlang/editor@0.4.4",
  "moonbit-community/proton_contract@0.1.18",
  "bobzhang/openseek@0.2.2",
}

readme = "README.md"

license = "Apache-2.0"

description = "SeekMoon — a Proton + Rabbita desktop client for the OpenSeek agent."

options(
  "--moonbit-unstable-prebuild": "native_link_config.mjs",
  preferred_target: "native",
  supported_targets: "native+js",
)
