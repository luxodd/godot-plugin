# ──────────────────────────────────────────────────────────────────────────────
# Luxodd Godot Plugin — Automated Test Runner (Windows)
#
# Prerequisites:
#   - Node.js (for the mock WebSocket server)
#   - Godot 4.3+ on PATH (as `godot` or set $env:GODOT_BIN)
#
# Usage:
#   .\tests\run_tests.ps1
# ──────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "godot" }
$MockPort = 8765
$MockProcess = $null

function Cleanup {
    if ($MockProcess -and !$MockProcess.HasExited) {
        Write-Host "[runner] Stopping mock server (PID $($MockProcess.Id))..."
        Stop-Process -Id $MockProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

try {
    Write-Host "========================================"
    Write-Host "  Luxodd Godot Plugin — Test Runner"
    Write-Host "========================================"
    Write-Host ""

    # 1. Install mock server dependencies
    Write-Host "[runner] Installing mock server dependencies..."
    Push-Location $ScriptDir
    npm install --silent 2>&1 | Out-Null
    Pop-Location
    Write-Host ""

    # 2. Start mock WebSocket server
    Write-Host "[runner] Starting mock server on port $MockPort..."
    $MockProcess = Start-Process -FilePath "node" `
        -ArgumentList "$ScriptDir\mock_server.js", "$MockPort" `
        -PassThru -NoNewWindow -RedirectStandardOutput "$ScriptDir\mock_server.log"

    Start-Sleep -Seconds 1
    if ($MockProcess.HasExited) {
        Write-Host "[runner] ERROR: Mock server failed to start"
        exit 1
    }
    Write-Host "[runner] Mock server running (PID $($MockProcess.Id))"
    Write-Host ""

    # 3. Run Godot tests
    Write-Host "[runner] Running Godot tests (headless)..."
    Write-Host ""

    Push-Location $ProjectDir
    $godotResult = & $GodotBin --headless --path . 2>&1
    $TestExit = $LASTEXITCODE
    $godotResult | ForEach-Object { Write-Host $_ }
    Pop-Location

    Write-Host ""

    # 4. Report
    if ($TestExit -eq 0) {
        Write-Host "[runner] All tests passed!"
    } else {
        Write-Host "[runner] Tests FAILED (exit code $TestExit)"
    }

    exit $TestExit
}
finally {
    Cleanup
}
