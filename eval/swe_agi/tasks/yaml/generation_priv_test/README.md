# Generate Test Cases from yaml-test-suites

`generate_yaml_tests.py` is a script generate test cases from
[yaml-test-suites](https://github.com/yaml/yaml-test-suite) data.

## Usage

```bash
# Make sure you are in yaml/ subdirectory
cd yaml/
# Clone the yaml-test-suites repository if you haven't already
git clone https://github.com/yaml/yaml-test-suite.git
# Make data directory
cd yaml-test-suite
make data
# Go back to yaml/ directory
cd ../
# Run this script
python3.10 generation_priv_test/generate_yaml_tests.py
```

Python 3.10 or newer is required.
