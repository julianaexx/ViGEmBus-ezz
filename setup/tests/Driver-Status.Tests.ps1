$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../Driver-Status.ps1"
$fixture = Join-Path $env:TEMP ('ViGEmBus-status-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
'DriverVer=10/16/2026,1.22.1.0' | Set-Content "$fixture/ViGEmBus.inf"

# These hardware snapshots exercise failure cases without installing a kernel driver.
function Get-ChildItem { [pscustomobject]@{ FullName = 'oem-test.inf'; Name = 'oem-test.inf' } }
function Get-FileHash {
    param([string]$Path, [string]$Algorithm)
    $hash = if ($Path -like '*System32*' -and -not $script:binaryMatches) { 'OLD' } else { 'EXPECTED' }
    [pscustomobject]@{ Hash = $hash }
}
function Test-Path { param([string]$Path) $true }
function Get-CimInstance {
    param([string]$ClassName, [string]$Filter)
    switch ($ClassName) {
        'Win32_PnPEntity' { $script:devices }
        'Win32_PnPSignedDriver' { $script:bindings }
        'Win32_SystemDriver' { [pscustomobject]@{ State = $script:serviceState } }
    }
}
function Reset-Snapshot {
    $script:devices = @([pscustomobject]@{
        HardwareID = @('Nefarius\ViGEmBus\Gen1'); PNPDeviceID = 'ROOT\VIGEMBUS\0000'; ConfigManagerErrorCode = 0
    })
    $script:bindings = @([pscustomobject]@{ DeviceID = 'ROOT\VIGEMBUS\0000'; InfName = 'oem-test.inf'; DriverVersion = '1.22.1.0' })
    $script:serviceState = 'Running'
    $script:binaryMatches = $true
}
function Assert-State([string]$Expected, [bool]$Reboot = $false) {
    $result = Get-DriverInstallationStatus -PackageDir $fixture -RebootRequested $Reboot
    if ($result.State -ne $Expected) { throw "Expected $Expected, got $($result.State)" }
}
function Assert-Fails([string]$ExpectedError, [bool]$Reboot = $false) {
    $errorMessage = $null
    try { Get-DriverInstallationStatus -PackageDir $fixture -RebootRequested $Reboot | Out-Null }
    catch { $errorMessage = $_.Exception.Message }
    if (-not $errorMessage -or $errorMessage -notlike "*$ExpectedError*") { throw "Expected failure '$ExpectedError', got '$errorMessage'" }
}
try {
    Reset-Snapshot; Assert-State 'Ready'
    Reset-Snapshot; $script:devices = @(); Assert-Fails 'Device Manager'
    Reset-Snapshot; $script:bindings[0].DriverVersion = '1.22.0.0'; Assert-Fails 'older driver'
    Reset-Snapshot; $script:bindings[0].InfName = 'oem-old.inf'; Assert-Fails 'older driver'
    Reset-Snapshot; $script:devices[0].ConfigManagerErrorCode = 52; Assert-Fails 'error code 52' -Reboot $true
    Reset-Snapshot; $script:devices[0].ConfigManagerErrorCode = 10; Assert-Fails 'error code 10'
    Reset-Snapshot; $script:devices[0].ConfigManagerErrorCode = 14; Assert-State 'RestartRequired'
    Reset-Snapshot; Assert-State 'RestartRequired' -Reboot $true
    Reset-Snapshot; $script:serviceState = 'Stopped'; Assert-Fails 'not running'
    Reset-Snapshot; $script:binaryMatches = $false; Assert-Fails 'binary does not match'
    Write-Host 'PASS: 10 driver status scenarios, including wrong version, signature error, stopped driver and restart required.'
} finally {
    Remove-Item -LiteralPath "$fixture/ViGEmBus.inf" -Force
    Remove-Item -LiteralPath $fixture -Force
}
