#!/usr/bin/env bash
set -euo pipefail

# Test runner for Cobolge on Linux (GnuCOBOL)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin/cobolge"
FIXTURES="$ROOT/tests/fixtures"
PROG="$FIXTURES/hello_classic.mal"
TMP_DIR="$(mktemp -d /tmp/cob_test_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== Cobolge Test Suite (Linux) ==="

# 1. Gate (full run, 48 steps)
echo "--- Test 1: Gate (48 steps) ---"
"$BIN" "$PROG" --json < /dev/null > "$TMP_DIR/gate.out" 2> "$TMP_DIR/gate.err"
DIFF_OUT="$(diff -u <(printf 'Hello, world.\n') "$TMP_DIR/gate.out" || true)"
if [ -n "$DIFF_OUT" ]; then
    echo "FAIL: Output mismatch in Gate"
    exit 1
fi
grep -q '{"final":{"a":19758,"c":85,"d":63},"halt_reason":"VInstruction","output_len":13,"status":"HALTED","steps":48}' "$TMP_DIR/gate.err"
echo "  PASS"

# 2. Step-17 snapshot
echo "--- Test 2: Step-17 snapshot ---"
"$BIN" "$PROG" 17 --json --snapshot-out "$TMP_DIR/snap17.json" < /dev/null > "$TMP_DIR/snap.out" 2> "$TMP_DIR/snap.err"
DIFF_OUT="$(diff -u <(printf 'Hello\n') "$TMP_DIR/snap.out" || true)"
if [ -n "$DIFF_OUT" ]; then
    echo "FAIL: Output mismatch in Step-17"
    exit 1
fi
grep -q '{"final":{"a":40,"c":17,"d":57},"halt_reason":"StepsExhausted","output_len":5,"status":"TIMEOUT","steps":17}' "$TMP_DIR/snap.err"
SNAP_SHA="$(sha256sum "$TMP_DIR/snap17.json" | cut -d' ' -f1)"
EXPECTED_SHA="29372aad12caa5afd340328d6c9afb51408a3a60a477bda94a671a0dd79a2fe4"
if [ "$SNAP_SHA" != "$EXPECTED_SHA" ]; then
    echo "FAIL: Snapshot SHA mismatch: got $SNAP_SHA, expected $EXPECTED_SHA"
    exit 1
fi
echo "  PASS"

# 3. Resume from step-17
echo "--- Test 3: Resume from step-17 ---"
"$BIN" --resume "$TMP_DIR/snap17.json" --json < /dev/null > "$TMP_DIR/res.out" 2> "$TMP_DIR/res.err"
DIFF_OUT="$(diff -u <(printf 'Hello, world.\n') "$TMP_DIR/res.out" || true)"
if [ -n "$DIFF_OUT" ]; then
    echo "FAIL: Output mismatch in Resume"
    exit 1
fi
grep -q '{"final":{"a":19758,"c":85,"d":63},"halt_reason":"VInstruction","output_len":13,"status":"HALTED","steps":48}' "$TMP_DIR/res.err"
echo "  PASS"

echo "ALL TESTS PASSED"
