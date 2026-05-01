param(
    [string]$SourceScript = "ssh-manager.ps1",
    [string]$OutputExe = "ssh-manager.exe",
    [string]$ProductName = "SSH Key Manager",
    [string]$ProductVersion = "1.0.0"
)

$ErrorActionPreference = "Stop"

# Re-launch build in a clean PowerShell process without loading user profiles.
# This avoids noisy/breaking profile hooks during ps2exe compilation.
if ($env:SSHMANAGER_BUILD_INTERNAL -ne "1") {
    $pwsh = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $pwsh)) {
        throw "powershell.exe not found at: $pwsh"
    }

    $env:SSHMANAGER_BUILD_INTERNAL = "1"
    $argList = @(
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", $MyInvocation.MyCommand.Path,
        "-SourceScript", $SourceScript,
        "-OutputExe", $OutputExe,
        "-ProductName", $ProductName,
        "-ProductVersion", $ProductVersion
    )

    & $pwsh @argList
    exit $LASTEXITCODE
}

function Write-Step([string]$msg) {
    Write-Host "[BUILD] $msg" -ForegroundColor Cyan
}

function Ensure-Module([string]$moduleName) {
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Step "Installing module '$moduleName' for current user..."
        Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $moduleName -Force
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location $scriptDir

    Write-Step "Working directory: $scriptDir"
    Write-Step "Source: $SourceScript"
    Write-Step "Output: $OutputExe"

    if (-not (Test-Path $SourceScript)) {
        throw "Source script not found: $SourceScript"
    }

    Ensure-Module "ps2exe"

    Write-Step "Building executable..."
    Invoke-PS2EXE `
        -inputFile $SourceScript `
        -outputFile $OutputExe `
        -noConsole `
        -title $ProductName `
        -description "Mini AWX-style SSH key manager" `
        -company "Community Build" `
        -product $ProductName `
        -copyright "MIT" `
        -version $ProductVersion `
        -requireAdmin:$false

    if (-not (Test-Path $OutputExe)) {
        throw "Build finished without output file: $OutputExe"
    }

    $sha = Get-FileHash $OutputExe -Algorithm SHA256
    $hashFile = "$OutputExe.sha256.txt"
    $hashLine = "$($sha.Hash) *$OutputExe"
    Set-Content -Path $hashFile -Value $hashLine -Encoding ASCII

    Write-Step "Build successful."
    Write-Step "EXE: $OutputExe"
    Write-Step "SHA256: $($sha.Hash)"
    Write-Step "Hash file: $hashFile"
}
catch {
    Write-Host "[BUILD][ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
