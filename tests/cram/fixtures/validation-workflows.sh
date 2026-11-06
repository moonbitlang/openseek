#!/usr/bin/env bash
# One isolated lifecycle: every command retains its original exit assertion.
expect_status() {
  actual=$?
  if [ "$actual" -ne "$1" ]; then
    printf 'Expected exit %s, got %s near fixture line %s\n' "$1" "$actual" "${BASH_LINENO[0]}" >&2
    exit 1
  fi
}

CHECK="$TESTDIR/../../share/workflow/check.mbtx"
expect_status 0

TEST="$TESTDIR/../../share/workflow/test.mbtx"
expect_status 0

CHECK_TEST="$TESTDIR/../../share/workflow/check-test.mbtx"
expect_status 0

INFO_FMT="$TESTDIR/../../share/workflow/info-fmt.mbtx"
expect_status 0

CHECK_JSON="$TESTDIR/../../share/workflow/check-json.mbtx"
expect_status 0

cat > moon.mod <<'EOF'
name = "example/workflow_docs"
EOF
expect_status 0

touch moon.pkg
expect_status 0

cat > answer.mbt <<'EOF'
///|
pub fn answer() -> Int {42}
EOF
expect_status 0

cat > answer_test.mbt <<'EOF'
///|
test "answer" { assert_eq(@workflow_docs.answer(), 42) }
EOF
expect_status 0

moonx "$CHECK"
expect_status 0

moonx "$TEST"
expect_status 0

moonx "$CHECK_TEST"
expect_status 0

moonx "$INFO_FMT"
expect_status 0

grep '^pub fn' pkg.generated.mbti
expect_status 0

cat answer.mbt
expect_status 0

moonx "$CHECK_JSON"
expect_status 0

cat > answer.mbt <<'EOF'
///|
pub fn answer() -> Int { "wrong" }
EOF
expect_status 0

moonx "$CHECK" 2> check.err
expect_status 1

tail -n 1 check.err
expect_status 0

moonx "$CHECK_TEST" 2> check-test.err
expect_status 1

tail -n 1 check-test.err
expect_status 0
