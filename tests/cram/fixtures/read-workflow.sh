#!/usr/bin/env bash
# Fresh input files for each read.mbtx scenario; no state crosses testcli cases.
set -e
READ="$TESTDIR/../../share/workflow/read.mbtx"
printf 'first\nselected\nlast\n' > sample.mbt
printf 'whole file' > note.txt
touch empty.txt
mkdir dir
printf 'kept' > log:12
printf 'dash' > ./--weird
moonx "$READ" "$@"
