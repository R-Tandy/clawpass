Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$configPath = "C:\Users\Reno\.openclaw\openclaw.json"

function Get-OCConfig {
    if (Test-Path $configPath) {
        return Get-Content $configPath | ConvertFrom-Json
    }
    return $null
}

function Save-OCConfig($config) {
    $json = $config | ConvertTo-Json -Depth 100
    $json | Set-Content $configPath
}

# --- UI Definition ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "OpenClaw Control Center v2"
$form.Size = New-Object System.Drawing.Size(500, 700)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$form.ForeColor = [System.Drawing.Color]::White

$fontLabel = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fontInput = New-Object System.Drawing.Font("Segoe UI", 10)

# Helper to create labeled inputs
function Add-LabeledInput($labeltext, $top, $left, $width = 440) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labeltext
    $lbl.Location = New-Object System.Drawing.Point($left, $top)
    $lbl.Size = New-Object System.Drawing.Size($width, 20)
    $lbl.ForeColor = [System.Drawing.Color]::LightGray
    $lbl.Font = $fontLabel
    $form.Controls.Add($lbl)
    
    $input = New-Object System.Windows.Forms.TextBox
    $input.Location = New-Object System.Drawing.Point($left, $top + 20)
    $input.Size = New-Object System.Drawing.Size($width, 25)
    $input.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $input.ForeColor = [System.Drawing.Color]::White
    $input.Font = $fontInput
    $form.Controls.Add($input)
    
    return $input
}

# --- Sections ---

# 1. Model Section
$modelLabel = New-Object System.Windows.Forms.Label
$modelLabel.Text = "MODEL SETTINGS"
$modelLabel.Location = New-Object System.Drawing.Point(20, 20)
$modelLabel.Size = New-Object System.Drawing.Size(200, 25)
$modelLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$modelLabel.ForeColor = [System.Drawing.Color]::Cyan
$form.Controls.Add($modelLabel)

$modelCombo = New-Object System.Windows.Forms.ComboBox
$modelCombo.Location = New-Object System.Drawing.Point(20, 50)
$modelCombo.Size = New-Object System.Drawing.Size(440, 30)
$modelCombo.DropDownStyle = "DropDownList"
$modelCombo.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$modelCombo.ForeColor = [System.Drawing.Color]::White
$modelCombo.Font = $fontInput
$form.Controls.Add($modelCombo)

$modelComboLabel = New-Object System.Windows.Forms.Label
$modelComboLabel.Text = "Select Primary Model"
$modelComboLabel.Location = New-Object System.Drawing.Point(20, 30)
$modelComboLabel.Size = New-Object System.Drawing.Size(200, 20)
$modelComboLabel.ForeColor = [System.Drawing.Color]::LightGray
$modelComboLabel.Font = $fontLabel
$form.Controls.Add($modelComboLabel)

# 2. Auth Section
$authLabel = New-Object System.Windows.Forms.Label
$authLabel.Text = "AUTHENTICATION & KEYS"
$authLabel.Location = New-Object System.Drawing.Point(20, 110)
$authLabel.Size = New-Object System.Drawing.Size(200, 25)
$authLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$authLabel.ForeColor = [System.Drawing.Color]::Cyan
$form.Controls.Add($authLabel)

$gatewayTokenInput = Add-LabeledInput "Gateway Token" 140 20
$gatewayTokenInput.Width = 440

$ollamaKeyInput = Add-LabeledInput "Ollama API Key" 190 20
$ollamaKeyInput.Width = 440
$ollamaKeyInput.PasswordChar = '*'

$nvidiaKeyInput = Add-LabeledInput "Nvidia API Key" 240 20
$nvidiaKeyInput.Width = 440
$nvidiaKeyInput.PasswordChar = '*'

# 3. Toggles
$toggleLabel = New-Object System.Windows.Forms.Label
$toggleLabel.Text = "ADVANCED TOGGLES"
$toggleLabel.Location = New-Object System.Drawing.Point(20, 300)
$toggleLabel.Size = New-Object System.Drawing.Size(200, 25)
$toggleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$toggleLabel.ForeColor = [System.Drawing.Color]::Cyan
$form.Controls.Add($toggleLabel)

$cbDisableDeviceAuth = New-Object System.Windows.Forms.CheckBox
$cbDisableDeviceAuth.Text = "Dangerously Disable Device Auth"
$cbDisableDeviceAuth.Location = New-Object System.Drawing.Point(20, 330)
$cbDisableDeviceAuth.Size = New-Object System.Drawing.Size(300, 25)
$form.Controls.Add($cbDisableDeviceAuth)

$cbInsecureAuth = New-Object System.Windows.Forms.CheckBox
$cbInsecureAuth.Text = "Allow Insecure Auth"
$cbInsecureAuth.Location = New-Object System.Drawing.Point(20, 360)
$cbInsecureAuth.Size = New-Object System.Drawing.Size(300, 25)
$form.Controls.Add($cbInsecureAuth)

$cbTailscale = New-Object System.Windows.Forms.CheckBox
$cbTailscale.Text = "Enable Tailscale Mode"
$cbTailscale.Location = New-Object System.Drawing.Point(20, 390)
$cbTailscale.Size = New-Object System.Drawing.Size(300, 25)
$form.Controls.Add($cbTailscale)

# 4. Gateway Controls
$gwLabel = New-Object System.Windows.Forms.Label
$gwLabel.Text = "GATEWAY ACTIONS"
$gwLabel.Location = New-Object System.Drawing.Point(20, 430)
$gwLabel.Size = New-Object System.Drawing.Size(200, 25)
$gwLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$gwLabel.ForeColor = [System.Drawing.Color]::Cyan
$form.Controls.Add($gwLabel)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = "Restart Gateway"
$btnRestart.Location = New-Object System.Drawing.Point(20, 460)
$btnRestart.Size = New-Object System.Drawing.Size(150, 40)
$btnRestart.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
$btnRestart.ForeColor = [System.Drawing.Color]::White
$btnRestart.Font = $fontLabel
$form.Controls.Add($btnRestart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop Gateway"
$btnStop.Location = New-Object System.Drawing.Point(180, 460)
$btnStop.Size = New-Object System.Drawing.Size(150, 40)
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.Font = $fontLabel
$form.Controls.Add($btnStop)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh Status"
$btnRefresh.Location = New-Object System.Drawing.Point(340, 460)
$btnRefresh.Size = New-Object System.Drawing.Size(130, 40)
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$btnRefresh.ForeColor = [System.Drawing.Color]::White
$btnRefresh.Font = $fontLabel
$form.Controls.Add($btnRefresh)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "SAVE ALL CHANGES"
$btnSave.Location = New-Object System.Drawing.Point(20, 530)
$btnSave.Size = New-Object System.Drawing.Size(440, 60)
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnSave)

# --- Logic ---

function Refresh-UI {
    $config = Get-OCConfig
    if ($config) {
        # Populate Model Dropdown
        $modelCombo.Items.Clear()
        $allModels = $config.agents.defaults.models.PSObject.Properties | ForEach-Object { $_.Name }
        foreach ($m in $allModels) { [void]$modelCombo.Items.Add($m) }
        $modelCombo.SelectedItem = $config.agents.defaults.model.primary
        
        # Populate Keys
        $gatewayTokenInput.Text = $config.gateway.auth.token
        $ollamaKeyInput.Text = $config.models.providers.ollama.apiKey
        $nvidiaKeyInput.Text = $config.models.providers.nvidia.apiKey
        
        # Populate Toggles
        $cbDisableDeviceAuth.Checked = $config.gateway.controlUi.dangerouslyDisableDeviceAuth
        $cbInsecureAuth.Checked = $config.gateway.controlUi.allowInsecureAuth
        $cbTailscale.Checked = $config.gateway.tailscale.mode -ne "off"
    }
}

$btnRefresh.Add_Click({
    Refresh-UI
    [System.Windows.Forms.MessageBox]::Show("Configuration re-read from disk successfully.", "Refresh")
})

$btnSave.Add_Click({
    $config = Get-OCConfig
    if ($config) {
        $config.agents.defaults.model.primary = $modelCombo.SelectedItem
        $config.gateway.auth.token = $gatewayTokenInput.Text
        $config.models.providers.ollama.apiKey = $ollamaKeyInput.Text
        $config.models.providers.nvidia.apiKey = $nvidiaKeyInput.Text
        $config.gateway.controlUi.dangerouslyDisableDeviceAuth = $cbDisableDeviceAuth.Checked
        $config.gateway.controlUi.allowInsecureAuth = $cbInsecureAuth.Checked
        $config.gateway.tailscale.mode = if ($cbTailscale.Checked) { "on" } else { "off" }
        
        Save-OCConfig $config
        [System.Windows.Forms.MessageBox]::Show("All changes saved to openclaw.json!", "Saved")
    }
})

$btnRestart.Add_Click({
    Start-Process "openclaw" -ArgumentList "gateway restart" -WindowStyle Hidden
    [System.Windows.Forms.MessageBox]::Show("Gateway restart command sent!", "Restart")
})

$btnStop.Add_Click({
    Stop-Process -Name "node" -Force -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show("All Node processes terminated. Gateway stopped.", "Stopped")
})

# Initial Load
Refresh-UI

$form.ShowDialog()
