# Background job lifecycle

Run the offline test against the native CLI:

```sh
moon build cmd/openseek --target native
python3 tests/integration/turn_finish.py \
  _build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe
```

The local scripted provider checks the actual request messages through a real
`mbtx` background execution, plain-text finish reminder, `job_wait`, completion
notice, `job_output`, and explicit `finish`. A file gate controls completion.
The test does not call an external model service. It requires Python 3 and the
same MoonBit runtime dependencies as `mbtx`.

The agent and runtime MoonBit tests cover input, cancellation, invalid calls,
multi-job selection, and notification ordering separately.
