param(
    [ValidateSet('Check', 'Install', 'Uninstall', 'Verify')][string]$Mode = 'Check',
    [string]$ResultPath = (Join-Path $env:TEMP 'ViGEmBus-ezz-result.txt'),
    [switch]$ShowResult
)
$ErrorActionPreference = 'Stop'
$hardwareId = 'Nefarius\ViGEmBus\Gen1'
$packageDir = $PSScriptRoot
$reboot = $false
$log = Join-Path $env:TEMP 'ViGEmBus-ezz-setup.log'
Start-Transcript -Path $log -Append | Out-Null
function Write-Result([string]$Message) {
    $Message | Set-Content -LiteralPath $ResultPath -Encoding utf8
    if ($ShowResult) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Message, 'ViGEmBus 安装状态') | Out-Null
    }
}
try {
    if ($Mode -in @('Check', 'Install')) {
        $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Administrator privileges are required to install the driver. Run setup as administrator.'
        }
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
    if ($Mode -eq 'Check') { Write-Result '安装环境检查通过。'; exit 0 }

    . "$packageDir/Driver-Status.ps1"
    if ($Mode -eq 'Verify') {
        $status = Get-DriverInstallationStatus -PackageDir $packageDir
        if ($status.State -eq 'RestartRequired') {
            Write-Result "需要重启：驱动已写入，但尚未确认正常运行。`r`n请重启后再次检查。`r`n目标版本：$($status.Version)`r`n日志：$log"
            exit 3010
        }
        Write-Result "安装成功，驱动正在运行。`r`n当前版本：$($status.Version)`r`n设备状态：正常（错误码 0）`r`n驱动文件校验：通过`r`n日志：$log"
        exit 0
    }

    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new("$packageDir/ViGEmBus-Test.cer")
    if ($Mode -eq 'Install') {
        $newStores = @()
        $driverStaged = $false
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
            $driverStaged = $true
            $existing = Get-CimInstance Win32_PnPEntity | Where-Object { $_.HardwareID -contains $hardwareId }
            $verb = if ($existing) { 'update' } else { 'install' }
            & "$packageDir/devcon.exe" $verb "$packageDir/ViGEmBus.inf" $hardwareId
            if ($LASTEXITCODE -notin @(0, 1)) { throw "Device installation failed: $LASTEXITCODE" }
            if ($LASTEXITCODE -eq 1) { $reboot = $true }
            $status = Get-DriverInstallationStatus -PackageDir $packageDir -RebootRequested $reboot
            $reboot = $status.State -eq 'RestartRequired'
            if ($reboot) {
                Write-Result "需要重启：驱动安装已提交，尚未确认新驱动正常运行。`r`n目标版本：$($status.Version)`r`n重启后，从开始菜单打开“ViGEmBus-ezz → 检查安装状态”。`r`n日志：$log"
            } else {
                Write-Result "安装成功，驱动正在运行。`r`n当前版本：$($status.Version)`r`n设备状态：正常（错误码 0）`r`n驱动文件校验：通过`r`n日志：$log"
            }
        } catch {
            if (-not $driverStaged) {
                foreach ($store in $newStores) { Remove-Item "Cert:/LocalMachine/$store/$($certificate.Thumbprint)" -ErrorAction SilentlyContinue }
            }
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
    if ($Mode -eq 'Uninstall') { Write-Result '驱动卸载完成。' }
    if ($reboot) { exit 3010 }
    exit 0
} catch {
    Write-Result "检查或安装失败，未确认驱动正常工作。`r`n原因：$($_.Exception.Message)`r`n日志：$log`r`nWindows 驱动日志：$env:windir\INF\setupapi.dev.log"
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
