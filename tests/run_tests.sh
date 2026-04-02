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

cleanup() {
    if [ -n "$MOCK_PID" ] && kill -0 "$MOCK_PID" 2>/dev/null; then
        echo "[runner] Stopping mock server (PID $MOCK_PID)..."
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

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
"$GODOT_BIN" --headless --path . 2>&1
TEST_EXIT=$?
set -e

echo ""

# ── 4. Report ────────────────────────────────────────────────────────────────
if [ $TEST_EXIT -eq 0 ]; then
    echo "[runner] All tests passed!"
else
    echo "[runner] Tests FAILED (exit code $TEST_EXIT)"
fi

exit $TEST_EXIT
