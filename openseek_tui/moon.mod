name = "moonbitlang/openseek_tui"

version = "0.8.0"

import {
  "moonbitlang/jsonl@0.2.1",
  "moonbitlang/openseek@0.8.0",
  "moonbitlang/openseek_protocol@0.4.3",
  "moonbit-community/displaytext@0.1.7",
  "moonbit-community/tty@0.6.2",
  "moonbitlang/async@0.22.10",
  "bobzhang/open_in_browser@0.1.2",
  "moonbitlang/x@0.5.7",
}

readme = "README.md"

repository = "https://github.com/moonbitlang/openseek"

license = "Apache-2.0"

keywords = [ "openseek", "tui", "terminal", "agent" ]

description = "OpenSeek interactive terminal UI: the openseek_tui binary"

preferred_target = "native"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value+implicit_impl_as_method"
