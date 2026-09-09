default:
    just --list

# Check the two production targets together and verify repository formatting.
check:
    just check-prompt
    moon check --target native --deny-warn
    moon check --target js --deny-warn
    moon fmt --check

# Build every root workspace member for the production targets.
build:
    moon build --target native
    moon build --target js

# The runtime lives outside the repository in ~/.proton/store, keyed by the CEF
# archive digest and layout version pinned in the Proton release, so every
# Proton upgrade that moves either key is a cache miss. The resulting failure
# reads as a missing cef_browser_capi.h rather than a missing runtime.
# Install the CEF runtime Desktop's Proton dependency compiles against.
cef-setup:
    moonx moonbit-community/proton_cefsetup

# Serve recorded sessions in the browser; flags pass through to the server
# (e.g. just inspect --session-root path/to/sessions --port 8081).
inspect *args:
    moon build cmd/viz_app --target js
    moon run inspect -- {{ args }}

# Run workspace MoonBit tests plus the offline OpenSeek CLI documentation tests.
test: test-moon
    moon cram test tests/cram
    just test-turn-finish

# Real CLI lifecycle regression with an offline scripted model (Python 3).
test-turn-finish:
    moon build cmd/openseek --target native
    python3 tests/integration/turn_finish.py _build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe

test-moon:
    moon test --target native
    moon test --target js

# Refresh filesystem-derived prompt content even when only share/ changed.
prompt:
    moon run scripts/md_to_mbt_string -- prompt/default_prompt.mbt.md prompt/generated_default_prompt.mbt

check-prompt:
    moon run scripts/md_to_mbt_string -- --check prompt/default_prompt.mbt.md prompt/generated_default_prompt.mbt

# Import the latest markdown build (or a specified commit) and regenerate the prompt.
update-docs commit="latest":
    moon run scripts/update-moonbit-docs.mbtx {{quote(commit)}}

# Build the editor's web distribution and reference server in its scoped workspace.
editor-build:
    just --justfile editor/justfile build

# Run the editor's MoonBit tests on every target supported by its scoped workspace.
editor-test:
    just --justfile editor/justfile test

# Run the editor's required Playwright smoke and component suites.
editor-test-browser:
    just --justfile editor/justfile test-browser-smoke

# Run Desktop's Rabbita views in Chromium through the browser-console bundle.
desktop-test-browser:
    just --justfile desktop/justfile test-browser

# Parse Desktop's checked-in build scripts.
desktop-build-scripts-check:
    just --justfile desktop/justfile build-scripts-check

# Build the current host's Desktop package.
desktop-package:
    just --justfile desktop/justfile package

# Build and launch the unbundled Desktop host.
desktop-dev:
    just --justfile desktop/justfile dev

# Run the session viewer's Rabbita views in Chromium.
viz-test-browser:
    just --justfile cmd/viz_app/justfile test-browser
