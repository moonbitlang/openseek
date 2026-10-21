name = "moonbitlang/openseek_tui"

version = "0.7.2"

import {
  "moonbitlang/jsonl@0.2.0",
  "moonbitlang/openseek@0.7.2",
  "moonbitlang/openseek_protocol@0.4.1",
  "moonbit-community/displaytext@0.1.6",
  "moonbit-community/tty@0.3.0",
  "moonbitlang/async@0.22.4",
  "bobzhang/open_in_browser@0.1.0",
  "moonbitlang/x@0.4.50",
}

readme = "README.md"

repository = "https://github.com/moonbitlang/openseek"

license = "Apache-2.0"

keywords = [ "openseek", "tui", "terminal", "agent" ]

description = "OpenSeek interactive terminal UI: the openseek_tui binary"

preferred_target = "native"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value+implicit_impl_as_method"
