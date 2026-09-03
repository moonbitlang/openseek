name = "moonbitlang/editor"

version = "0.4.5"

readme = "README.md"

repository = "https://github.com/moonbitlang/openseek"

license = "Apache-2.0"

keywords = [ "editor", "moonbit", "readonly", "syntax-highlighting" ]

description = "Readonly MoonBit code viewer harness inspired by Monaco and CodeMirror."

supported_targets = "+js+native+wasm"

preferred_target = "js"

warnings = "+prefer_readonly_array+implicit_impl_as_method"

import {
  "moonbit-community/cmark@0.4.5",
  "moonbit-community/moondiff@0.0.6",
  "moonbitlang/async@0.21.0",
  "moonbit-community/rabbita@0.15.4",
  "Milky2018/diago@0.3.0",
  "moonbitlang/x@0.4.50",
  "kokic/uml@0.2.2",
}

options(
  exclude: [
    "codemirror",
    "vscode",
    "internal/shell",
    "server",
    "moon.work",
    "tests",
    "scripts",
    "internal/viewer/ui/scrollbar/mouse_wheel_classifier_reference_wbtest.mbt",
    "AGENTS.md",
    "justfile",
    "package.json",
    "package-lock.json",
    "playwright.config.js",
    "docs/exec-plans",
    "docs/references",
    "docs/notes",
    "docs/styles.md",
  ],
)
