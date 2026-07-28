# Maintainer-only ZIP fixture and test generation

This excluded directory contains the scripts used to build the full fixture
corpus and generate staging MoonBit tests. It is hidden from benchmark agents
because source selection and the generated expected output reveal private test
cases.

Run the commands below from the ZIP task directory.

## Pipeline

1. **Download fixtures** (ZIP/JAR files) from official sources:

```bash
python3 generation_priv_test/fetch_fixtures.py
```

2. **Run zipinfo** against every fixture:

```bash
python3 generation_priv_test/run_zipinfo.py
```

3. **Parse zipinfo output** into structured JSON:

```bash
python3 generation_priv_test/parse_zipinfo.py
```

4. **Generate MoonBit tests**:

```bash
python3 generation_priv_test/generate_zip_tests.py
```

Outputs:

- `generation_priv_test/fixtures/manifest.json`: fixture list + checksums
- `generation_priv_test/fixtures/zipinfo_raw/`: raw `zipinfo -l` output
- `generation_priv_test/fixtures/expected/`: structural JSON oracles
- `generation_priv_test/zip_valid_generated.mbt` and
  `generation_priv_test/zip_invalid_generated.mbt`: unsplit staging tests

The checked-in suite uses `zip_pub_test.mbt` and `zip_priv_test.mbt`. Preserve
their public/private split and global valid/invalid indices when refreshing the
staging output.
