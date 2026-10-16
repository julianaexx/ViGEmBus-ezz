param([ValidateSet('Check', 'Install', 'Uninstall')][string]$Mode = 'Check')
$ErrorActionPreference = 'Stop'
$hardwareId = 'Nefarius\ViGEmBus\Gen1'
$packageDir = $PSScriptRoot
$reboot = $false
$log = Join-Path $env:TEMP 'ViGEmBus-ezz-setup.log'
Start-Transcript -Path $log -Append | Out-Null
try {
    if ($Mode -ne 'Uninstall') {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DriverCodeIntegrity {
    [DllImport("ntdll.dll")]
    private static extern int NtQuerySystemInformation(int info, int[] data, int size, out int returned);
    public static bool TestSigningEnabled() {
        int[] data = { 8, 0 }; int returned;
        int status = NtQuerySystemInformation(103, data, 8, out returned);
        if (status != 0) throw new Exception("Cannot query Windows code integrity: " + status);
        return (data[1] & 2) != 0;
    }
}
'@
        if (-not [DriverCodeIntegrity]::TestSigningEnabled()) {
            throw 'This modified driver is TEST-SIGNED. Windows test-signing mode must already be enabled. See INSTALL.txt. Setup will not change boot settings.'
        }
    }
    if ($Mode -eq 'Check') { exit 0 }

    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new("$packageDir/ViGEmBus-Test.cer")
    if ($Mode -eq 'Install') {
        $newStores = @()
        try {
            foreach ($store in @('Root', 'TrustedPublisher')) {
                if (-not (Test-Path "Cert:/LocalMachine/$store/$($certificate.Thumbprint)")) {
                    Import-Certificate -FilePath "$packageDir/ViGEmBus-Test.cer" -CertStoreLocation "Cert:/LocalMachine/$store" | Out-Null
                    $newStores += $store
                }
            }
            & "$env:windir/System32/pnputil.exe" /add-driver "$packageDir/ViGEmBus.inf" /install
            if ($LASTEXITCODE -notin @(0, 3010)) { throw "Driver staging failed: $LASTEXITCODE" }
            if ($LASTEXITCODE -eq 3010) { $reboot = $true }
            $existing = Get-CimInstance Win32_PnPEntity | Where-Object { $_.HardwareID -contains $hardwareId }
            $verb = if ($existing) { 'update' } else { 'install' }
            & "$packageDir/devcon.exe" $verb "$packageDir/ViGEmBus.inf" $hardwareId
            if ($LASTEXITCODE -notin @(0, 1)) { throw "Device installation failed: $LASTEXITCODE" }
            if ($LASTEXITCODE -eq 1) { $reboot = $true }
            $devices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.HardwareID -contains $hardwareId })
            if ($devices.Count -eq 0) { throw 'ViGEmBus device was not created.' }
            foreach ($device in $devices) {
                if ($device.ConfigManagerErrorCode -eq 14) { $reboot = $true }
                elseif ($device.ConfigManagerErrorCode -ne 0 -and -not $reboot) {
                    throw "ViGEmBus device error: $($device.ConfigManagerErrorCode). See Device Manager and $log"
                }
            }
        } catch {
            foreach ($store in $newStores) { Remove-Item "Cert:/LocalMachine/$store/$($certificate.Thumbprint)" -ErrorAction SilentlyContinue }
            throw
        }
    } else {
        # Remove only devices and OEM INFs belonging to this exact driver package.
        $hash = (Get-FileHash "$packageDir/ViGEmBus.inf" -Algorithm SHA256).Hash
        $infs = @(Get-ChildItem "$env:windir/INF/oem*.inf" | Where-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash -eq $hash })
        $devices = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.InfName -in $infs.Name }
        foreach ($device in $devices) {
            & "$packageDir/devcon.exe" remove "@$($device.DeviceID)"
            if ($LASTEXITCODE -notin @(0, 1)) { throw "Device removal failed: $LASTEXITCODE" }
            if ($LASTEXITCODE -eq 1) { $reboot = $true }
        }
        foreach ($inf in $infs) {
            & "$env:windir/System32/pnputil.exe" /delete-driver $inf.Name /uninstall
            if ($LASTEXITCODE -notin @(0, 3010)) { throw "Driver removal failed: $LASTEXITCODE" }
            if ($LASTEXITCODE -eq 3010) { $reboot = $true }
        }
        foreach ($store in @('Root', 'TrustedPublisher')) {
            Remove-Item "Cert:/LocalMachine/$store/$($certificate.Thumbprint)" -ErrorAction SilentlyContinue
        }
    }
    if ($reboot) { exit 3010 }
    exit 0
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
