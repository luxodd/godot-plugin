#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Luxodd Godot Plugin — Automated Test Runner
#
# Prerequisites:
#   - Node.js (for the mock WebSocket server)
#   - Godot 4.3+ on PATH (as `godot` or set GODOT_BIN)
#
# Usage:
#   ./tests/run_tests.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
MOCK_PORT=8765
MOCK_PID=""
WORK_DIR="$(mktemp -d)"
export LUXODD_MOCK_FRAMES="$WORK_DIR/frames.json"
GODOT_LOG="$WORK_DIR/godot.log"

cleanup() {
    # Stop any Godot this script started, even on Ctrl-C or failure.
    pkill -P $$ 2>/dev/null || true
    if [ -n "$MOCK_PID" ] && kill -0 "$MOCK_PID" 2>/dev/null; then
        echo "[runner] Stopping mock server (PID $MOCK_PID)..."
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
}
trap 'cleanup; rm -rf "$WORK_DIR"' EXIT

echo "========================================"
echo "  Luxodd Godot Plugin — Test Runner"
echo "========================================"
echo ""

# ── 1. Install mock server dependencies ──────────────────────────────────────
echo "[runner] Installing mock server dependencies..."
cd "$SCRIPT_DIR"
npm install --silent 2>&1
echo ""

# ── 2. Start mock WebSocket server ───────────────────────────────────────────
echo "[runner] Starting mock server on port $MOCK_PORT..."
node mock_server.js "$MOCK_PORT" &
MOCK_PID=$!

# Wait for server to be ready
sleep 1
if ! kill -0 "$MOCK_PID" 2>/dev/null; then
    echo "[runner] ERROR: Mock server failed to start"
    exit 1
fi
echo "[runner] Mock server running (PID $MOCK_PID)"
echo ""

# ── 3. Run Godot tests ──────────────────────────────────────────────────────
echo "[runner] Running Godot tests (headless)..."
echo ""

cd "$PROJECT_DIR"
set +e
"$GODOT_BIN" --headless --path . 2>&1 | tee "$GODOT_LOG"
TEST_EXIT=${PIPESTATUS[0]}
set -e

# Backward compatibility: the 1.0.0 suite, unchanged, against this plugin.
if [ $TEST_EXIT -eq 0 ]; then
    echo ""
    echo "[runner] Running the frozen 1.0.0 suite (backward compatibility)..."
    set +e
    "$GODOT_BIN" --headless --path . res://tests/compat/test_runner_1_0_0.tscn 2>&1
    TEST_EXIT=$?
    set -e
fi

# Plugin logs are on in the test config. They must never contain the player's email or a
# session token (integration checks SEC-5 and SR-6).
# Server notices and unknown types must not warn: a warning is a console error in a web build.
if grep -q -- "Unknown response type" "$GODOT_LOG"; then
    echo "[runner] FAIL: the plugin warned about a server message type"
    TEST_EXIT=1
fi
for secret in "test@luxodd.com" "test_token_abc123" "test_token_B"; do
    if grep -q -- "$secret" "$GODOT_LOG"; then
        echo "[runner] FAIL: the Godot log contains a test secret ($secret)"
        TEST_EXIT=1
    fi
done

echo ""

# ── 4. Report ────────────────────────────────────────────────────────────────
if [ $TEST_EXIT -eq 0 ]; then
    echo "[runner] All tests passed!"
else
    echo "[runner] Tests FAILED (exit code $TEST_EXIT)"
fi

exit $TEST_EXIT
