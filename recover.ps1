# OpenClaw Recovery Tool (Break-Glass)
# This script runs independently of the Gateway.

$configPath = "C:\Users\Reno\.openclaw\openclaw.json"
$backupPath = "C:\Users\Reno\.openclaw\openclaw.json.last-good"

function Show-Menu {
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host " 🦇 OPENCLAW RECOVERY CONSOLE (Break-Glass) " -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "1. [FORCE] Disable All Authentication (None Mode)"
    Write-Host "2. [CLEAN] Kill all Node.exe processes (Zombie Clear)"
    Write-Host "3. [RESTART] Trigger Gateway Service Restart"
    Write-Host "4. [RESTORE] Rollback to last-good config"
    Write-Host "5. [RESET] Set Primary Model to Stable Default"
    Write-Host "6. Exit"
    Write-Host "----------------------------------------------"
}

function Disable-Auth {
    Write-Host "Disabling authentication..." -ForegroundColor Yellow
    $json = Get-Content $configPath | ConvertFrom-Json
    $json.gateway.auth.mode = "none"
    $json | ConvertTo-Json -Depth 100 | Set-Content $configPath
    Write-Host "DONE: gateway.auth.mode set to 'none'. Please restart Gateway." -ForegroundColor Green
}

function Kill-Node {
    Write-Host "Killing all node.exe processes..." -ForegroundColor Yellow
    Stop-Process -Name "node" -Force -ErrorAction SilentlyContinue
    Write-Host "DONE: All Node processes terminated." -ForegroundColor Green
}

function Restart-Gateway {
    Write-Host "Triggering Gateway restart..." -ForegroundColor Yellow
    # Attempt to use the installed gateway.cmd
    Start-Process "C:\Users\Reno\.openclaw\gateway.cmd" -WindowStyle Hidden
    Write-Host "DONE: Restart command sent." -ForegroundColor Green
}

function Restore-Config {
    if (Test-Path $backupPath) {
        Write-Host "Restoring from $backupPath..." -ForegroundColor Yellow
        Copy-Item -Path $backupPath -Destination $configPath -Force
        Write-Host "DONE: Config rolled back." -ForegroundColor Green
    } else {
        Write-Host "ERROR: No last-good config found!" -ForegroundColor Red
    }
}

function Reset-Model {
    Write-Host "Resetting primary model..." -ForegroundColor Yellow
    $json = Get-Content $configPath | ConvertFrom-Json
    $json.agents.defaults.model.primary = "ollama/gemma4:31b-cloud"
    $json | ConvertTo-Json -Depth 100 | Set-Content $configPath
    Write-Host "DONE: Primary model reset." -ForegroundColor Green
}

do {
    Show-Menu
    $input = Read-Host "Select an option [1-6]"
    switch ($input) {
        "1" { Disable-Auth }
        "2" { Kill-Node }
        "3" { Restart-Gateway }
        "4" { Restore-Config }
        "5" { Reset-Model }
    }
    if ($input -ne "6") {
        Write-Host "`nPress any key to return to menu..."
        $null = [System.Console]::ReadKey($true)
    }
} while ($input -ne "6")
