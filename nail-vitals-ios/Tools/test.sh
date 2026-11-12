#!/bin/bash
# Builds and runs every harness. Exit code 0 only if all pass.
#   ./test.sh
# angle-harness: prints AngleAnalyzer / FingerSigns numbers on synthetic
# fingers; its output must match angle-harness/expected.txt exactly. After
# an intended change to those numbers, review the diff and update the file.
# signs-harness: named checks for the sign model (Signs/, Session/).
set -u
cd "$(dirname "$0")"
APP=../NailVitals/NailVitals/NailVitals
D=$APP/Detection
# The pure-logic and Vision files the harnesses share (photo-lab's set).
DETECTION=($D/DetectedSilhouette.swift $D/AngleAnalyzer.swift $D/HandPoseDetector.swift
  $D/FingerMaskSegmenter.swift $D/FingerSigns.swift $D/ClubbingAssessment.swift
  $D/OutlineFingerFinder.swift $D/HumanLabel.swift $D/NailColor.swift $D/EdgeSharpness.swift
  $D/BackgroundContrast.swift $D/FingerIdentity.swift $D/ReadingQuality.swift
  $D/PublishedNorms.swift $D/SchamrothWindow.swift)
fail=0

echo "== angle-harness"
if swiftc -O "${DETECTION[@]}" angle-harness/main.swift -o angle-harness/angle-harness 2> angle-harness/build.log; then
  if ./angle-harness/angle-harness | diff -q - angle-harness/expected.txt > /dev/null; then
    echo "PASS: output matches expected.txt"
  else
    echo "FAIL: output differs from angle-harness/expected.txt"; fail=1
  fi
else
  echo "FAIL: build (see angle-harness/build.log)"; grep error angle-harness/build.log | head -5; fail=1
fi

if [ -f signs-harness/main.swift ]; then
  echo "== signs-harness"
  shopt -s nullglob; SIGNS=($APP/Signs/*.swift); shopt -u nullglob
  EXTRA=()
  [ -f signs-harness/extra-sources.txt ] && while read -r f; do [ -n "$f" ] && EXTRA+=("$APP/$f"); done < signs-harness/extra-sources.txt
  if swiftc -O "${DETECTION[@]}" ${SIGNS[@]+"${SIGNS[@]}"} ${EXTRA[@]+"${EXTRA[@]}"} signs-harness/main.swift -o signs-harness/signs-harness 2> signs-harness/build.log; then
    ./signs-harness/signs-harness "$APP" || fail=1
  else
    echo "FAIL: build (see signs-harness/build.log)"; grep error signs-harness/build.log | head -8; fail=1
  fi
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
