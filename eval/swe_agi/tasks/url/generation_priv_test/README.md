# URL Benchmark Generation Scripts

These maintainer-only scripts regenerate the benchmark corpus. The
`generation_priv_test` directory is excluded while an agent works on a trial.

## generate_wpt_tests.py

Generates MoonBit test cases from the checked-in WHATWG WPT (Web Platform
Tests) URL test data.

### Usage

```bash
python3 generation_priv_test/generate_wpt_tests.py > url_wpt_test.mbt
python3 generation_priv_test/generate_wpt_tests.py path/to/urltestdata.json \
  > url_wpt_test.mbt
```

### Data Source

The default input is `specs/wpt/resources/urltestdata.json`, a checked-in
selection from the official WPT URL test data. The generator performs no
network requests.

### Output

The script generates one MoonBit test block for every test object in the
selected input, covering:
  - Basic URL parsing
  - Relative URL resolution
  - IPv4 and IPv6 addresses
  - Special schemes (http, https, ftp, file, ws, wss)
  - IDNA/Punycode domains
  - Percent encoding
  - Edge cases and error conditions

### Test Structure

Each generated test block parses one input and compares the result with the
expected serialized URL:

```moonbit
test "WPT #0" {
  let result = @url.Url::parse("https://example.com/")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "https://example.com/")
}
```

## generate_wpt_setters_tests.py

Generates MoonBit test cases from the WPT URL setters test data.

### Usage

```bash
python3 generation_priv_test/generate_wpt_setters_tests.py \
  > url_wpt_setters_test.mbt
python3 generation_priv_test/generate_wpt_setters_tests.py \
  path/to/setters_tests.json \
  > url_wpt_setters_test.mbt
```

### Data Source

The default input is `specs/wpt/resources/setters_tests.json`, a checked-in
selection from the official WPT URL setter data. The generator performs no
network requests.
