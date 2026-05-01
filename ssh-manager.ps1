Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------- LOG ----------------
$LogFile = Join-Path $PSScriptRoot "ssh-manager.log"

function Log($msg) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time | $msg" | Out-File -Append -FilePath $LogFile
}

function Set-Status($label, $text) {
    if ($label) {
        $label.Text = "Status: $text"
        [System.Windows.Forms.Application]::DoEvents()
    }
    if ($script:StatusTextBox) {
        $time = Get-Date -Format "HH:mm:ss"
        $script:StatusTextBox.AppendText("[$time] $text`r`n")
        $script:StatusTextBox.SelectionStart = $script:StatusTextBox.TextLength
        $script:StatusTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
    Log "STATUS: $text"
}

function Set-LiveStatus($text) {
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = "Status: $text"
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SshTimeoutSeconds {
    $defaultTimeout = 30
    $raw = $null

    if ($script:TimeoutTextBox) {
        $raw = $script:TimeoutTextBox.Text
    }

    $parsed = 0
    if ([int]::TryParse("$raw", [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 600) {
        return $parsed
    }

    if ($script:TimeoutTextBox) {
        $script:TimeoutTextBox.Text = "$defaultTimeout"
    }
    Set-Status $script:StatusLabel "Invalid timeout value. Using default: ${defaultTimeout}s"
    return $defaultTimeout
}

function Wait-ProcessResponsive($proc, $timeoutMs, $livePrefix) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.HasExited -and $sw.ElapsedMilliseconds -lt $timeoutMs) {
        $prefix = if ([string]::IsNullOrWhiteSpace($livePrefix)) { "Waiting for server response..." } else { $livePrefix }
        Set-LiveStatus "$prefix $([int]($sw.ElapsedMilliseconds / 1000))s"
        Start-Sleep -Milliseconds 100
    }

    if (-not $proc.HasExited) {
        try { $proc.Kill() } catch {}
        return $false
    }

    return $true
}

# ---------------- SAFE SSH RUN ----------------
function Invoke-SshProcess($targetHost, $cmd, $connectTimeoutSec, $timeoutSec, $statusPrefix) {
    if ([string]::IsNullOrWhiteSpace($targetHost)) {
        Log "SSH ERROR: host is empty"
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        Log "SSH ERROR: command is empty"
        return $null
    }

    $sshArgList = @(
        "-o", "BatchMode=yes",
        "-o", "NumberOfPasswordPrompts=0",
        "-o", "StrictHostKeyChecking=accept-new",
        "$targetHost",
        "$cmd"
    )

    Log "SSH START: ssh $targetHost <command>"
    $displayCmd = if ($cmd.Length -gt 140) { $cmd.Substring(0, 140) + "..." } else { $cmd }
    Set-Status $script:StatusLabel "Executing SSH: $targetHost :: $displayCmd"

    try {
        $script:LastSshExitCode = $null
        $script:LastSshTimedOut = $false
        $script:LastSshStderr = $null
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $stdoutFile = Join-Path $env:TEMP ("ssh-manager-stdout-" + [Guid]::NewGuid().ToString("N") + ".txt")
        $stderrFile = Join-Path $env:TEMP ("ssh-manager-stderr-" + [Guid]::NewGuid().ToString("N") + ".txt")

        $proc = Start-Process -FilePath "ssh" -ArgumentList $sshArgList -PassThru -NoNewWindow -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

        while (-not $proc.HasExited -and $sw.Elapsed.TotalSeconds -lt $timeoutSec) {
            Set-LiveStatus ("$statusPrefix {0}s" -f [int]$sw.Elapsed.TotalSeconds)
            Start-Sleep -Milliseconds 1000
            $proc.Refresh()
        }

        if (-not $proc.HasExited) {
            try { Stop-Process -Id $proc.Id -Force } catch {}
            $sw.Stop()
            Log "SSH TIMEOUT: process killed after ${timeoutSec}s"
            Set-Status $script:StatusLabel "SSH timeout (${timeoutSec}s): $targetHost"
            $script:LastSshTimedOut = $true
            return $null
        }

        $sw.Stop()
        $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { "" }
        $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }
        $exitCode = [int]$proc.ExitCode
        $script:LastSshStderr = $stderr
        $script:LastSshExitCode = $exitCode

        Log "SSH EXIT CODE: $exitCode"
        if ($stdout) { "SSH STDOUT:`n$stdout" | Out-File -Append -FilePath $LogFile }
        if ($stderr) { "SSH STDERR:`n$stderr" | Out-File -Append -FilePath $LogFile }

        if ($exitCode -ne 0) {
            Log "SSH ERROR: non-zero exit code"
            Set-Status $script:StatusLabel "SSH failed (exit code $exitCode): $targetHost"
        }
        else {
            Set-Status $script:StatusLabel ("SSH done: {0} ({1}s)" -f $targetHost, [int]$sw.Elapsed.TotalSeconds)
        }

        return ($stdout -replace "`r", "")
    }
    catch {
        Log "SSH EXCEPTION: $_"
        Set-Status $script:StatusLabel "SSH exception: $targetHost"
        $script:LastSshTimedOut = $true
        $script:LastSshStderr = "$_"
        return $null
    }
    finally {
        if ($stdoutFile -and (Test-Path $stdoutFile)) {
            Remove-Item -Path $stdoutFile -Force -ErrorAction SilentlyContinue
        }
        if ($stderrFile -and (Test-Path $stderrFile)) {
            Remove-Item -Path $stderrFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Run-Ssh($targetHost, $cmd) {
    $timeoutSec = Get-SshTimeoutSeconds
    $connectTimeout = [Math]::Min(30, [Math]::Max(15, $timeoutSec))
    return Invoke-SshProcess $targetHost $cmd $connectTimeout $timeoutSec "Waiting for server response..."
}

function Get-LastSshFailureDetails {
    $exit = $script:LastSshExitCode
    $err = "$($script:LastSshStderr)".Trim()
    if ($script:LastSshTimedOut) {
        return "SSH timed out."
    }
    if ($null -eq $exit) {
        return "SSH did not return an exit code (unexpected)."
    }
    if ($err) {
        $snippet = $err
        if ($snippet.Length -gt 800) {
            $snippet = $snippet.Substring(0, 800) + "..."
        }
        return "Exit code: $exit`r`n`r`n$snippet"
    }
    return "Exit code: $exit (no stderr captured)"
}

# ---------------- CONFIG ----------------
function Get-DefaultConfig {
    $p = "$env:USERPROFILE\.ssh\config"
    if (Test-Path $p) { return $p }
    return $null
}

function Parse-Config($file) {
    if ([string]::IsNullOrWhiteSpace($file)) {
        Log "CONFIG ERROR: empty config path"
        return @()
    }
    if (!(Test-Path $file)) {
        Log "CONFIG ERROR: file not found: $file"
        return @()
    }

    $hosts = @()
    foreach ($l in Get-Content $file) {
        if ($l -match "^\s*Host\s+(.+)$") {
            $hostName = $matches[1].Trim()
            if ($hostName -and $hostName -notmatch "[\*\?]") {
                $hosts += $hostName
            }
        }
    }
    $hosts = $hosts | Select-Object -Unique
    if ($hosts.Count -eq 0) {
        Log "CONFIG WARNING: no valid hosts in $file"
    }
    return @($hosts)
}

# ---------------- SSH KEY ----------------
function Ensure-SshFolder {
    New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null
}

function Get-KeyPath($keyName) {
    if ([string]::IsNullOrWhiteSpace($keyName)) {
        return $null
    }
    return (Join-Path "$env:USERPROFILE\.ssh" $keyName.Trim())
}

function Get-UniqueKeyName($preferredName) {
    $baseName = $preferredName
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = "id_ed25519"
    }

    # keep names filesystem-safe
    $baseName = ($baseName -replace "[^\w\.-]", "_").Trim()
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = "id_ed25519"
    }

    $candidate = $baseName
    $index = 1
    while ((Test-Path (Get-KeyPath $candidate)) -or (Test-Path ((Get-KeyPath $candidate) + ".pub"))) {
        $candidate = "{0}_{1}" -f $baseName, $index
        $index = $index + 1
    }
    return $candidate
}

function Generate-Key($requestedKeyName) {
    Ensure-SshFolder

    $effectiveKeyName = Get-UniqueKeyName $requestedKeyName
    $keyPath = Get-KeyPath $effectiveKeyName
    Log "Generating key: $keyPath (requested: $requestedKeyName)"

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "ssh-keygen"
        $psi.Arguments = "-q -t ed25519 -f ""$keyPath"" -N """""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $null = $proc.Start()

        if (-not (Wait-ProcessResponsive $proc 30000 "Generating key...")) {
            Log "SSH-KEYGEN TIMEOUT: process killed after 30s"
            return $null
        }

        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $exitCode = $proc.ExitCode

        Log "SSH-KEYGEN EXIT CODE: $exitCode"
        if ($stdout) { "SSH-KEYGEN STDOUT:`n$stdout" | Out-File -Append -FilePath $LogFile }
        if ($stderr) { "SSH-KEYGEN STDERR:`n$stderr" | Out-File -Append -FilePath $LogFile }

        if ($exitCode -eq 0 -and (Test-Path "$keyPath.pub")) {
            Log "KEY OK"
            return $effectiveKeyName
        }
        else {
            Log "KEY FAILED (no file)"
            return $null
        }
    }
    catch {
        Log "EXCEPTION: $_"
        return $null
    }
}

function Get-PubKey($keyName) {
    $keyPath = Get-KeyPath $keyName
    if ([string]::IsNullOrWhiteSpace($keyPath)) { return $null }
    $p = $keyPath + ".pub"
    if (!(Test-Path $p)) { return $null }
    return Get-Content $p -Raw
}

function Resolve-EffectiveKeyName($rawName) {
    if ([string]::IsNullOrWhiteSpace($rawName)) {
        return "id_ed25519"
    }
    return $rawName.Trim()
}

function Test-KeyExists($keyName) {
    $effective = Resolve-EffectiveKeyName $keyName
    $keyPath = Get-KeyPath $effective
    if ([string]::IsNullOrWhiteSpace($keyPath)) { return $false }
    return (Test-Path ($keyPath + ".pub"))
}

function Update-AddKeyUiState($txtKeyNameControl, $lblAddKeyInfoControl, $btnAddControl) {
    $effective = Resolve-EffectiveKeyName $txtKeyNameControl.Text
    $exists = Test-KeyExists $effective
    if ($exists) {
        $lblAddKeyInfoControl.Text = "Will add key: $effective (found)"
        $lblAddKeyInfoControl.ForeColor = [System.Drawing.Color]::DarkGreen
        $btnAddControl.Enabled = $true
    }
    else {
        $lblAddKeyInfoControl.Text = "Will add key: $effective (not found)"
        $lblAddKeyInfoControl.ForeColor = [System.Drawing.Color]::DarkRed
        $btnAddControl.Enabled = $false
    }
}

function Add-Key($targetHost, $keyName) {
    $key = Get-PubKey $keyName
    if (!$key) {
        Log "ADD KEY ERROR: no local public key"
        return $false
    }

    Log "Add key -> $targetHost (key: $keyName)"

    $cleanKey = $key.Trim()
    $remoteCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF '$cleanKey' ~/.ssh/authorized_keys || echo '$cleanKey' >> ~/.ssh/authorized_keys"
    $result = Run-Ssh $targetHost $remoteCmd
    return ($null -ne $result)
}

function Add-KeyContent($targetHost, $keyContent, $keyLabel) {
    if ([string]::IsNullOrWhiteSpace($keyContent)) {
        Log "ADD KEY ERROR: key content is empty"
        return $false
    }

    Log "Add key content -> $targetHost (key: $keyLabel)"
    $cleanKey = $keyContent.Trim()
    $remoteCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF '$cleanKey' ~/.ssh/authorized_keys || echo '$cleanKey' >> ~/.ssh/authorized_keys"
    $result = Run-Ssh $targetHost $remoteCmd
    return ($null -ne $result)
}

function Get-RemoteKeys($targetHost) {
    $result = Run-Ssh $targetHost "cat ~/.ssh/authorized_keys 2>/dev/null || true"
    if ($null -eq $result) {
        return $null
    }

    if ($script:LastSshExitCode -eq 0) {
        return @($result -split "`n")
    }

    if ($script:LastSshTimedOut) {
        return $null
    }

    # Some ssh versions may return non-zero even when remote output was produced.
    # If stdout is empty, treat as failure; otherwise accept output.
    if ([string]::IsNullOrWhiteSpace($result)) {
        return $null
    }

    return @($result -split "`n")
}

function Delete-Keys($targetHost, $keys) {
    Log "Delete keys -> $targetHost"

    $remoteLines = Get-RemoteKeys $targetHost | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_.Trim() -ne "" }
    if ($remoteLines.Count -eq 0) {
        Log "DELETE WARNING: remote authorized_keys is empty"
        return $false
    }

    $toDelete = @($keys | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    if ($toDelete.Count -eq 0) {
        Log "DELETE WARNING: no keys selected"
        return $false
    }

    $filtered = @()
    foreach ($line in $remoteLines) {
        if ($toDelete -notcontains $line.Trim()) {
            $filtered += $line
        }
    }

    $content = ($filtered -join "`n")
    if ($content -ne "") { $content += "`n" }
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))

    $writeCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s' '$base64' | base64 -d > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $result = Run-Ssh $targetHost $writeCmd
    return ($null -ne $result)
}

function Get-PubKeyFromFile($filePath) {
    if ([string]::IsNullOrWhiteSpace($filePath)) { return $null }
    if (!(Test-Path $filePath)) { return $null }
    try {
        $raw = Get-Content $filePath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw.Trim()
    }
    catch {
        Log "READ KEY FILE EXCEPTION ($filePath): $_"
        return $null
    }
}

# ---------------- UI ----------------
$form = New-Object Windows.Forms.Form
$form.Text = "SSH Key Manager FINAL"
$form.Size = New-Object Drawing.Size(1180, 760)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Location = "10,10"
$tabs.Size = "1145,600"
$form.Controls.Add($tabs)

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = "10,620"
$lblStatus.Text = "Status: Ready"
$form.Controls.Add($lblStatus)
$script:StatusLabel = $lblStatus

$statusTextBox = New-Object Windows.Forms.TextBox
$statusTextBox.Location = "10,645"
$statusTextBox.Size = "1145,70"
$statusTextBox.Multiline = $true
$statusTextBox.ReadOnly = $true
$statusTextBox.ScrollBars = "Vertical"
$statusTextBox.WordWrap = $true
$form.Controls.Add($statusTextBox)
$script:StatusTextBox = $statusTextBox

$lblTimeout = New-Object Windows.Forms.Label
$lblTimeout.Location = "980,620"
$lblTimeout.AutoSize = $true
$lblTimeout.Text = "SSH timeout (sec):"
$form.Controls.Add($lblTimeout)

$txtTimeout = New-Object Windows.Forms.TextBox
$txtTimeout.Location = "1085,617"
$txtTimeout.Size = "70,24"
$txtTimeout.Text = "30"
$form.Controls.Add($txtTimeout)
$script:TimeoutTextBox = $txtTimeout

# ================= TAB 1 =================
$tab1 = New-Object Windows.Forms.TabPage
$tab1.Text = "Keys"

$listHosts = New-Object Windows.Forms.ListBox
$listHosts.Location = "10,10"
$listHosts.Size = "300,230"
$tab1.Controls.Add($listHosts)

$btnDefault = New-Object Windows.Forms.Button
$btnDefault.Text = "Load default config"
$btnDefault.Location = "10,250"
$btnDefault.Size = "180,34"

$btnDefault.Add_Click({
    $cfg = Get-DefaultConfig
    if ($cfg) {
        Set-Status $lblStatus "Loading default config..."
        $listHosts.Items.Clear()
        Parse-Config $cfg | ForEach-Object { [void]$listHosts.Items.Add($_) }
        Sync-HostLists
        Log "Default config loaded"
        Set-Status $lblStatus "Default config loaded"
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Default SSH config not found")
        Set-Status $lblStatus "Default config not found"
    }
})
$tab1.Controls.Add($btnDefault)

$btnCustom = New-Object Windows.Forms.Button
$btnCustom.Text = "Load custom config"
$btnCustom.Location = "10,290"
$btnCustom.Size = "180,34"

$btnCustom.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    if ($dlg.ShowDialog() -eq "OK") {
        Set-Status $lblStatus "Loading custom config..."
        $listHosts.Items.Clear()
        Parse-Config $dlg.FileName | ForEach-Object { [void]$listHosts.Items.Add($_) }
        Sync-HostLists
        Log "Custom config loaded"
        Set-Status $lblStatus "Custom config loaded"
    }
})
$tab1.Controls.Add($btnCustom)

$btnGen = New-Object Windows.Forms.Button
$btnGen.Text = "Generate key"
$btnGen.Location = "10,410"
$btnGen.Size = "180,34"
$txtKeyName = New-Object Windows.Forms.TextBox
$txtKeyName.Location = "10,360"
$txtKeyName.Size = "300,24"
$txtKeyName.Text = ""
$tab1.Controls.Add($txtKeyName)

$lblKeyName = New-Object Windows.Forms.Label
$lblKeyName.Location = "320,364"
$lblKeyName.AutoSize = $true
$lblKeyName.Text = "Key name (optional)"
$tab1.Controls.Add($lblKeyName)

$btnGen.Add_Click({
    Set-Status $lblStatus "Generating key..."
    $generatedName = Generate-Key $txtKeyName.Text
    if ($generatedName) {
        $txtKeyName.Text = $generatedName
        Update-AddKeyUiState $txtKeyName $lblAddKeyInfo $btnAdd
        [System.Windows.Forms.MessageBox]::Show("Key generated successfully")
        Set-Status $lblStatus "Key generated: $generatedName"
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Key generation failed. See ssh-manager.log")
        Set-Status $lblStatus "Key generation failed"
    }
})
$tab1.Controls.Add($btnGen)

$btnAdd = New-Object Windows.Forms.Button
$btnAdd.Text = "Add key"
$btnAdd.Location = "10,450"
$btnAdd.Size = "180,34"
$btnAdd.Enabled = $false

$lblAddKeyInfo = New-Object Windows.Forms.Label
$lblAddKeyInfo.Location = "200,458"
$lblAddKeyInfo.AutoSize = $true
$lblAddKeyInfo.Text = "Will add key: id_ed25519 (not found)"
$lblAddKeyInfo.ForeColor = [System.Drawing.Color]::DarkRed
$tab1.Controls.Add($lblAddKeyInfo)

$btnAdd.Add_Click({
    if ($listHosts.SelectedItem) {
        Set-Status $lblStatus "Adding key to server..."
        $effectiveKeyName = Resolve-EffectiveKeyName $txtKeyName.Text
        if (!(Test-KeyExists $effectiveKeyName)) {
            [System.Windows.Forms.MessageBox]::Show("Selected key '$effectiveKeyName' does not exist in ~/.ssh")
            Set-Status $lblStatus "Selected key does not exist"
            Update-AddKeyUiState $txtKeyName $lblAddKeyInfo $btnAdd
            return
        }

        if (Add-Key $listHosts.SelectedItem $effectiveKeyName) {
            [System.Windows.Forms.MessageBox]::Show("Key '$effectiveKeyName' added successfully to '$($listHosts.SelectedItem)'")
            Set-Status $lblStatus "Key added"
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Failed to add key. See ssh-manager.log")
            Set-Status $lblStatus "Failed to add key"
        }
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Select server in Hosts list")
        Set-Status $lblStatus "Server is not selected"
    }
})
$tab1.Controls.Add($btnAdd)

$keyNameDebounceTimer = New-Object System.Windows.Forms.Timer
$keyNameDebounceTimer.Interval = 450
$keyNameDebounceTimer.Add_Tick({
    $keyNameDebounceTimer.Stop()
    Update-AddKeyUiState $txtKeyName $lblAddKeyInfo $btnAdd
})

$txtKeyName.Add_TextChanged({
    $keyNameDebounceTimer.Stop()
    $keyNameDebounceTimer.Start()
})

Update-AddKeyUiState $txtKeyName $lblAddKeyInfo $btnAdd

$tabs.TabPages.Add($tab1)

# ================= TAB 2 =================
$tab2 = New-Object Windows.Forms.TabPage
$tab2.Text = "Delete Keys"

$listKeys = New-Object Windows.Forms.ListBox
$listKeys.Location = "10,10"
$listKeys.Size = "1120,280"
$listKeys.SelectionMode = "MultiExtended"
$listKeys.HorizontalScrollbar = $true
$tab2.Controls.Add($listKeys)

$txtSelectedKeyPreview = New-Object Windows.Forms.TextBox
$txtSelectedKeyPreview.Location = "10,300"
$txtSelectedKeyPreview.Size = "1120,220"
$txtSelectedKeyPreview.Multiline = $true
$txtSelectedKeyPreview.ReadOnly = $true
$txtSelectedKeyPreview.ScrollBars = "Vertical"
$txtSelectedKeyPreview.WordWrap = $true
$tab2.Controls.Add($txtSelectedKeyPreview)

$listKeys.Add_SelectedIndexChanged({
    if ($listKeys.SelectedItems.Count -eq 0) {
        $txtSelectedKeyPreview.Text = ""
        return
    }

    $selectedText = @($listKeys.SelectedItems | ForEach-Object { "$_" }) -join "`r`n`r`n"
    $txtSelectedKeyPreview.Text = $selectedText
})

$btnLoadKeys = New-Object Windows.Forms.Button
$btnLoadKeys.Text = "Load keys"
$btnLoadKeys.Location = "10,530"
$btnLoadKeys.Size = "180,34"
$btnLoadKeys.Visible = $false

$btnLoadKeys.Add_Click({
    if ($listHosts.SelectedItem) {
        $loadSw = [System.Diagnostics.Stopwatch]::StartNew()
        Set-Status $lblStatus "Loading remote keys..."
        $listKeys.Items.Clear()

        $keys = Get-RemoteKeys $listHosts.SelectedItem
        if ($null -eq $keys) {
            $loadSw.Stop()
            $details = Get-LastSshFailureDetails
            [System.Windows.Forms.MessageBox]::Show("Failed to load keys from server.`r`n`r`n$details`r`n`r`nSee also ssh-manager.log")
            Set-Status $lblStatus ("Failed to load remote keys ({0}s)" -f [int]$loadSw.Elapsed.TotalSeconds)
            return
        }

        foreach ($k in $keys) {
            if ($k.Trim()) { [void]$listKeys.Items.Add($k) }
        }
        $txtSelectedKeyPreview.Text = ""

        $loadSw.Stop()
        Log "Keys loaded"
        Set-Status $lblStatus ("Remote keys loaded ({0}s)" -f [int]$loadSw.Elapsed.TotalSeconds)
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Select server in Hosts list")
        Set-Status $lblStatus "Server is not selected"
    }
})
$tab2.Controls.Add($btnLoadKeys)

$btnDelete = New-Object Windows.Forms.Button
$btnDelete.Text = "Delete selected"
$btnDelete.Location = "210,530"
$btnDelete.Size = "180,34"
$btnDelete.Visible = $false

$btnDelete.Add_Click({
    if ($listHosts.SelectedItem -and $listKeys.SelectedItems.Count -gt 0) {
        Set-Status $lblStatus "Deleting selected keys..."
        if (Delete-Keys $listHosts.SelectedItem @($listKeys.SelectedItems)) {
            Log "Keys deleted"
            Set-Status $lblStatus "Keys deleted"
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Failed to delete selected keys. See ssh-manager.log")
            Set-Status $lblStatus "Failed to delete keys"
        }

        $listKeys.Items.Clear()
        $keys = Get-RemoteKeys $listHosts.SelectedItem
        if ($null -eq $keys) {
            [System.Windows.Forms.MessageBox]::Show("Failed to reload keys from server after delete. See ssh-manager.log")
            Set-Status $lblStatus "Failed to reload remote keys"
            return
        }

        foreach ($k in $keys) {
            if ($k.Trim()) { [void]$listKeys.Items.Add($k) }
        }
        $txtSelectedKeyPreview.Text = ""
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Select server and at least one key")
        Set-Status $lblStatus "Nothing selected for deletion"
    }
})
$tab2.Controls.Add($btnDelete)

$tabs.TabPages.Add($tab2)

# ================= TAB 3 =================
$tab3 = New-Object Windows.Forms.TabPage
$tab3.Text = "Rotate Keys"

$lblRotateHosts = New-Object Windows.Forms.Label
$lblRotateHosts.Location = "10,10"
$lblRotateHosts.AutoSize = $true
$lblRotateHosts.Text = "Servers (multi-select):"
$tab3.Controls.Add($lblRotateHosts)

$listRotateHosts = New-Object Windows.Forms.ListBox
$listRotateHosts.Location = "10,35"
$listRotateHosts.Size = "350,250"
$listRotateHosts.SelectionMode = "MultiExtended"
$tab3.Controls.Add($listRotateHosts)

$lblOldKeys = New-Object Windows.Forms.Label
$lblOldKeys.Location = "380,10"
$lblOldKeys.AutoSize = $true
$lblOldKeys.Text = "Old public keys to remove (.pub, multi-select):"
$tab3.Controls.Add($lblOldKeys)

$txtOldKeyPaths = New-Object Windows.Forms.TextBox
$txtOldKeyPaths.Location = "380,35"
$txtOldKeyPaths.Size = "750,160"
$txtOldKeyPaths.Multiline = $true
$txtOldKeyPaths.ReadOnly = $true
$txtOldKeyPaths.ScrollBars = "Vertical"
$txtOldKeyPaths.WordWrap = $true
$tab3.Controls.Add($txtOldKeyPaths)

$btnPickOldKeys = New-Object Windows.Forms.Button
$btnPickOldKeys.Text = "Select old keys"
$btnPickOldKeys.Location = "380,205"
$btnPickOldKeys.Size = "180,34"
$btnPickOldKeys.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Filter = "Public key files (*.pub)|*.pub|All files (*.*)|*.*"
    if ($dlg.ShowDialog() -eq "OK") {
        $txtOldKeyPaths.Text = ($dlg.FileNames -join "`r`n")
        Set-Status $lblStatus "Selected old keys: $($dlg.FileNames.Count)"
    }
})
$tab3.Controls.Add($btnPickOldKeys)

$lblNewKey = New-Object Windows.Forms.Label
$lblNewKey.Location = "380,255"
$lblNewKey.AutoSize = $true
$lblNewKey.Text = "New public key to add (.pub):"
$tab3.Controls.Add($lblNewKey)

$txtNewKeyPath = New-Object Windows.Forms.TextBox
$txtNewKeyPath.Location = "380,280"
$txtNewKeyPath.Size = "750,24"
$tab3.Controls.Add($txtNewKeyPath)

$btnPickNewKey = New-Object Windows.Forms.Button
$btnPickNewKey.Text = "Select new key"
$btnPickNewKey.Location = "380,315"
$btnPickNewKey.Size = "180,34"
$btnPickNewKey.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $false
    $dlg.Filter = "Public key files (*.pub)|*.pub|All files (*.*)|*.*"
    if ($dlg.ShowDialog() -eq "OK") {
        $txtNewKeyPath.Text = $dlg.FileName
        Set-Status $lblStatus "Selected new key file"
    }
})
$tab3.Controls.Add($btnPickNewKey)

$btnRotateStart = New-Object Windows.Forms.Button
$btnRotateStart.Text = "Start rotate"
$btnRotateStart.Location = "380,365"
$btnRotateStart.Size = "180,40"
$btnRotateStart.Add_Click({
    $selectedServers = @($listRotateHosts.SelectedItems | ForEach-Object { "$_" })
    if ($selectedServers.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one server")
        return
    }

    $newKeyContent = Get-PubKeyFromFile $txtNewKeyPath.Text
    if ([string]::IsNullOrWhiteSpace($newKeyContent)) {
        [System.Windows.Forms.MessageBox]::Show("New key file is not set or invalid")
        return
    }

    $oldKeyFiles = @($txtOldKeyPaths.Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    $oldKeys = @()
    foreach ($oldPath in $oldKeyFiles) {
        $k = Get-PubKeyFromFile $oldPath
        if ($k) { $oldKeys += $k }
        else { Set-Status $lblStatus "Skipping invalid old key file: $oldPath" }
    }

    Set-Status $lblStatus "Rotate started. Servers: $($selectedServers.Count)"
    $okCount = 0
    $skipCount = 0

    foreach ($srv in $selectedServers) {
        Set-Status $lblStatus "[$srv] Adding new key..."
        $added = Add-KeyContent $srv $newKeyContent $txtNewKeyPath.Text
        if (-not $added) {
            Set-Status $lblStatus "[$srv] Add failed. Skipping delete."
            $skipCount = $skipCount + 1
            continue
        }

        Set-Status $lblStatus "[$srv] New key added"
        if ($oldKeys.Count -gt 0) {
            Set-Status $lblStatus "[$srv] Removing old keys..."
            if (Delete-Keys $srv $oldKeys) {
                Set-Status $lblStatus "[$srv] Old keys removed"
            }
            else {
                Set-Status $lblStatus "[$srv] Failed to remove old keys"
            }
        }
        else {
            Set-Status $lblStatus "[$srv] No old keys selected, delete step skipped"
        }

        $okCount = $okCount + 1
    }

    Set-Status $lblStatus "Rotate finished. Success: $okCount, skipped: $skipCount"
    [System.Windows.Forms.MessageBox]::Show("Rotate finished.`r`nSuccess: $okCount`r`nSkipped: $skipCount")
})
$tab3.Controls.Add($btnRotateStart)

$tabs.TabPages.Add($tab3)

function Update-DeleteTabButtonsState {
    $hasHost = $null -ne $listHosts.SelectedItem -and -not [string]::IsNullOrWhiteSpace("$($listHosts.SelectedItem)")
    $btnLoadKeys.Visible = $hasHost
    $btnDelete.Visible = $hasHost
}

function Sync-HostLists {
    if (-not $listRotateHosts) { return }
    $listRotateHosts.Items.Clear()
    foreach ($item in $listHosts.Items) {
        $listRotateHosts.Items.Add("$item") | Out-Null
    }
}

$listHosts.Add_SelectedIndexChanged({
    Update-DeleteTabButtonsState
})

# ---------------- AUTO LOAD ----------------
$cfg = Get-DefaultConfig
if ($cfg) {
    Parse-Config $cfg | ForEach-Object { [void]$listHosts.Items.Add($_) }
    Sync-HostLists
    Log "Auto-loaded default config"
}

Update-DeleteTabButtonsState

$form.ShowDialog()